import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';
import 'json.dart';
import 'pkce.dart';
import 'storage.dart';
import 'token_set.dart';

/// Opens [authorizeUrl] in a browser session and completes with the full
/// callback URL once the login page redirects to a URL with
/// [callbackUrlScheme]. Throw a `PlatformException(code: 'CANCELED')` when the
/// user dismisses it.
typedef Authenticator = Future<String> Function(Uri authorizeUrl, String callbackUrlScheme);

/// Default scope requested by [LowcoAuth.loginWithRedirect].
const String defaultScope = 'openid profile email offline_access';

const Duration _requestTimeout = Duration(seconds: 30);

Future<String> _flutterWebAuth2(Uri authorizeUrl, String callbackUrlScheme) =>
    FlutterWebAuth2.authenticate(
        url: authorizeUrl.toString(), callbackUrlScheme: callbackUrlScheme);

/// OAuth 2.0 Authorization Code + PKCE client for the lowco identity service
/// — the Flutter counterpart of the React `LowcoAuthProvider`.
///
/// Create one per app, call [initialize] once, and expose it with
/// `LowcoAuthProvider`. It is a [ChangeNotifier]: listeners are notified
/// whenever [isLoading], [isAuthenticated], [user], [tokens] or [error] change.
class LowcoAuth extends ChangeNotifier {
  /// * [domain] — identity service base, including its route prefix, e.g.
  ///   `https://api.lowco.ai/v1/identity` (tokens are exchanged at
  ///   `<domain>/tenants/<tenantId>/oauth/token`).
  /// * [loginPageUrl] — hosted login page that receives the PKCE parameters.
  /// * [redirectUri] — must be registered on the OAuth client **exactly** (the
  ///   server does an exact-match check), e.g. `com.example.app://callback`.
  /// * [callbackUrlScheme] — scheme the browser session waits for; defaults to
  ///   the scheme of [redirectUri].
  /// * [storage] — token persistence, default [SecureTokenStorage].
  /// * [onTokens] — called whenever a fresh token set is obtained (login or
  ///   refresh), not when one is restored from storage.
  /// * [onRedirectCallback] — called with the `appState` passed to
  ///   [loginWithRedirect] after a successful login.
  /// * [authenticator] — browser integration, default
  ///   `FlutterWebAuth2.authenticate`. Wrap it to pass
  ///   `FlutterWebAuth2Options` (e.g. `preferEphemeral: true`).
  /// * [httpClient] — client for the token endpoint (not closed by [dispose]).
  LowcoAuth({
    required String domain,
    required this.loginPageUrl,
    required this.tenantId,
    required this.clientId,
    required this.redirectUri,
    String? callbackUrlScheme,
    this.scope = defaultScope,
    TokenStorage? storage,
    this.onTokens,
    this.onRedirectCallback,
    Authenticator? authenticator,
    http.Client? httpClient,
  })  : domain = domain.replaceAll(RegExp(r'/+$'), ''),
        callbackUrlScheme = callbackUrlScheme ?? Uri.parse(redirectUri).scheme,
        _storage = storage ?? SecureTokenStorage(),
        _authenticator = authenticator ?? _flutterWebAuth2,
        _ownsHttp = httpClient == null,
        _http = httpClient ?? http.Client() {
    for (final (name, value) in [
      ('domain', domain),
      ('loginPageUrl', loginPageUrl),
      ('tenantId', tenantId),
      ('clientId', clientId),
      ('redirectUri', redirectUri),
    ]) {
      if (value.trim().isEmpty) {
        throw ArgumentError.value(value, name, 'LowcoAuth: $name is required');
      }
    }
  }

  /// Identity service base URL (trailing slashes removed).
  final String domain;
  final String loginPageUrl;
  final String tenantId;
  final String clientId;
  final String redirectUri;
  final String callbackUrlScheme;

  /// Default scope for [loginWithRedirect].
  final String scope;
  final void Function(TokenSet tokens)? onTokens;
  final void Function(Map<String, dynamic>? appState)? onRedirectCallback;

  final TokenStorage _storage;
  final Authenticator _authenticator;
  final bool _ownsHttp;
  final http.Client _http;

  /// Clock used for expiry checks. Tests may replace it.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  bool _isLoading = true;
  LowcoAuthException? _error;
  TokenSet? _tokens;
  UserProfile? _user;
  Timer? _refreshTimer;
  Future<void>? _initializing;
  Future<void>? _loggingIn;
  Future<TokenSet>? _refreshing;
  int _epoch = 0;
  bool _disposed = false;

  /// Storage key of the token set: `lowco:tokens:<tenantId>:<clientId>`.
  String get storageKey => 'lowco:tokens:$tenantId:$clientId';

  /// True until [initialize] has finished, and while a login or a startup
  /// refresh is in flight.
  bool get isLoading => _isLoading;

  /// True when the session is usable: a valid access token, or a refresh
  /// token to recover one.
  bool get isAuthenticated => _tokens?.canRecoverSession(now: now()) ?? false;

  /// The last login failure; cleared by the next login attempt and by
  /// [logout]. A cancelled login is not an error.
  LowcoAuthException? get error => _error;

  /// The signed-in user (display only: the JWT signature is not verified).
  UserProfile? get user => _user;

  /// The current token set.
  TokenSet? get tokens => _tokens;

  Uri get _tokenEndpoint =>
      Uri.parse('$domain/tenants/${Uri.encodeComponent(tenantId)}/oauth/token');

  /// Restores the session from storage (call once at startup; repeated calls
  /// return the same future):
  ///
  /// * a valid access token is used as is and refreshed 60 s before expiry;
  /// * an expired one with a refresh token is refreshed now;
  /// * anything else is cleared.
  ///
  /// Unlike the browser SDK, a rejected refresh never opens the login page by
  /// itself: the session is cleared and listeners are notified, so the app (or
  /// `WithAuthenticationRequired`) decides when to call [loginWithRedirect].
  /// A refresh that fails for network reasons keeps the stored session.
  Future<void> initialize() => _initializing ??= _restore();

  Future<void> _restore() async {
    final stored = await _readStoredTokens();
    if (stored == null || !stored.canRecoverSession(now: now())) {
      if (stored != null) await _deleteStoredTokens();
      _setLoading(false);
      return;
    }
    if (stored.isAccessTokenValid(now: now())) {
      _applyTokens(stored);
      _setLoading(false);
      return;
    }
    try {
      await _refresh(stored);
    } catch (error) {
      if (_isTransient(error)) {
        _applyTokens(stored); // offline: keep the session, retry on demand
      } else {
        await _expireSession();
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Signs the user in: opens [loginPageUrl] with the PKCE parameters in a
  /// browser session, validates the callback, exchanges the code for tokens
  /// and persists them.
  ///
  /// Failures (an OAuth `error` on the callback, a state mismatch, a rejected
  /// code exchange) do not throw: they clear the session and are exposed via
  /// [error]. If the user cancels, nothing changes and [error] stays `null`.
  /// [appState] is handed to `onRedirectCallback` after a successful login;
  /// [scope] overrides the default scope. Concurrent calls share one flow.
  Future<void> loginWithRedirect({Map<String, dynamic>? appState, String? scope}) =>
      _loggingIn ??= _login(appState, scope ?? this.scope).whenComplete(() => _loggingIn = null);

  Future<void> _login(Map<String, dynamic>? appState, String scope) async {
    final state = randomUrlSafeString(24);
    final nonce = randomUrlSafeString(24);
    final codeVerifier = randomUrlSafeString(48);

    _error = null;
    _setLoading(true);
    try {
      final authorizeUrl = _authorizeUrl(
        state: state,
        nonce: nonce,
        scope: scope,
        codeChallenge: pkceChallenge(codeVerifier),
      );
      final callback = Uri.parse(await _authenticator(authorizeUrl, callbackUrlScheme));
      final code = _readCallback(callback, expectedState: state);
      final response = await _postToken(
        {
          'grant_type': 'authorization_code',
          'tenant_id': tenantId,
          'client_id': clientId,
          'code': code,
          'code_verifier': codeVerifier,
          'redirect_uri': redirectUri,
        },
        failureMessage: 'Authorization code exchange failed.',
      );
      final tokens = TokenSet(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        idToken: response.idToken,
        expiresAt: _expiresAt(response),
        scope: response.scope,
      );
      _epoch++;
      _applyTokens(tokens);
      await _writeStoredTokens(tokens);
      onTokens?.call(tokens);
      onRedirectCallback?.call(appState);
    } on PlatformException catch (error) {
      if (error.code != 'CANCELED') await _failLogin(error);
    } catch (error) {
      await _failLogin(error);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _failLogin(Object error) async {
    _error = error is LowcoAuthException
        ? error
        : LowcoAuthException('Authentication failed.', cause: error);
    await _clearSession();
  }

  Uri _authorizeUrl({
    required String state,
    required String nonce,
    required String scope,
    required String codeChallenge,
  }) {
    final base = Uri.parse(loginPageUrl);
    return base.replace(queryParameters: {
      ...base.queryParameters,
      'tenant_id': tenantId,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'state': state,
      'nonce': nonce,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });
  }

  /// Validates the callback URL and returns the authorization code.
  String _readCallback(Uri callback, {required String expectedState}) {
    final params = <String, String>{};
    final fragment = callback.fragment;
    if (fragment.contains('=')) {
      try {
        params.addAll(Uri.splitQueryString(fragment));
      } on FormatException {
        // Not a parameter fragment.
      }
    }
    params.addAll(callback.queryParameters);

    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      final description = params['error_description'];
      throw LowcoAuthException(
        description == null || description.isEmpty ? error : description,
        code: error,
      );
    }
    if (params['state'] != expectedState) {
      throw const LowcoAuthException('OAuth state mismatch.', code: 'invalid_state');
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const LowcoAuthException('Missing authorization code.', code: 'invalid_request');
    }
    return code;
  }

  /// Returns a valid access token, refreshing it first when it expires within
  /// 60 seconds. Concurrent calls share one refresh request.
  ///
  /// Throws `LowcoAuthException('Not authenticated.')` without a session and
  /// `LowcoAuthException('Session expired.')` (after clearing the session)
  /// when there is no refresh token or the server rejects it. A refresh that
  /// fails for network reasons throws
  /// `LowcoAuthException('Refresh token exchange failed.')` and keeps the
  /// session for a later retry.
  Future<String> getAccessTokenSilently() async {
    final current = _tokens ?? await _readStoredTokens();
    if (current == null || current.accessToken.isEmpty) {
      throw const LowcoAuthException('Not authenticated.');
    }
    if (current.isAccessTokenValid(now: now())) return current.accessToken;
    if (current.refreshToken == null) {
      await _expireSession();
      throw const LowcoAuthException('Session expired.');
    }
    try {
      return (await _refresh(current)).accessToken;
    } catch (error) {
      if (_isTransient(error)) {
        throw LowcoAuthException('Refresh token exchange failed.', cause: error);
      }
      await _expireSession();
      throw LowcoAuthException('Session expired.', cause: error);
    }
  }

  /// Signs out locally: clears the stored tokens and the in-memory state and
  /// cancels the refresh timer. (Like the browser SDK it does not revoke the
  /// tokens or end the login page's own browser session.)
  Future<void> logout() async {
    _error = null;
    await _clearSession();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_ownsHttp) _http.close();
    super.dispose();
  }

  // --- Refresh -------------------------------------------------------------

  Future<TokenSet> _refresh(TokenSet current) =>
      _refreshing ??= _doRefresh(current).whenComplete(() => _refreshing = null);

  Future<TokenSet> _doRefresh(TokenSet current) async {
    final epoch = _epoch;
    final response = await _postToken(
      {
        'grant_type': 'refresh_token',
        'tenant_id': tenantId,
        'client_id': clientId,
        'refresh_token': current.refreshToken!,
      },
      failureMessage: 'Refresh token exchange failed.',
    );
    if (epoch != _epoch) {
      // Logged out (or in again) while the request was in flight.
      throw const LowcoAuthException('Not authenticated.');
    }
    // Same merge as the TS SDK: `{...previous, ...refreshed, expires_at}`.
    final next = TokenSet(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken ?? current.refreshToken,
      idToken: response.idToken ?? current.idToken,
      expiresAt: _expiresAt(response),
      scope: response.scope ?? current.scope,
    );
    _applyTokens(next);
    await _writeStoredTokens(next);
    onTokens?.call(next);
    _notify();
    return next;
  }

  void _scheduleRefresh(TokenSet tokens) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (tokens.refreshToken == null || _disposed) return;
    final delay = tokens.expiresAt - now().millisecondsSinceEpoch - tokenRefreshSkew.inMilliseconds;
    if (delay <= 0) return;
    _refreshTimer = Timer(Duration(milliseconds: delay), () => unawaited(_refreshInBackground()));
  }

  Future<void> _refreshInBackground() async {
    final current = _tokens;
    if (current == null || current.refreshToken == null) return;
    try {
      await _refresh(current);
    } catch (error) {
      // Network trouble: keep the session, the next getAccessTokenSilently()
      // retries. A rejected refresh token ends the session (no auto-login).
      if (!_isTransient(error)) await _expireSession();
    }
  }

  // --- Token endpoint ------------------------------------------------------

  Future<_TokenResponse> _postToken(
    Map<String, String> fields, {
    required String failureMessage,
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest('POST', _tokenEndpoint, abortTrigger: abort.future)
      ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
      ..bodyBytes = utf8.encode(_formEncode(fields));
    final response = await _http.send(request).then(http.Response.fromStream).timeout(
      _requestTimeout,
      onTimeout: () {
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException('lowco auth: token request timed out', _requestTimeout);
      },
    );

    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    final json = readMap(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LowcoAuthException(
        failureMessage,
        statusCode: response.statusCode,
        code: readString(json?['error']),
      );
    }
    final accessToken = readString(json?['access_token']);
    if (json == null || accessToken == null || accessToken.isEmpty) {
      throw LowcoAuthException(failureMessage, statusCode: response.statusCode);
    }
    return _TokenResponse(
      accessToken: accessToken,
      refreshToken: _nonEmpty(readString(json['refresh_token'])),
      idToken: _nonEmpty(readString(json['id_token'])),
      expiresIn: readInt(json['expires_in']) ?? 0,
      scope: _nonEmpty(readString(json['scope'])),
    );
  }

  // --- State helpers -------------------------------------------------------

  int _expiresAt(_TokenResponse response) =>
      now().millisecondsSinceEpoch + response.expiresIn * 1000;

  void _applyTokens(TokenSet tokens) {
    _tokens = tokens;
    _user = UserProfile.fromTokens(tokens);
    _scheduleRefresh(tokens);
  }

  /// The mobile version of the TS `sessionExpiredRedirect`: clear everything
  /// and notify, but never open the login page automatically.
  Future<void> _expireSession() async {
    _error = null;
    await _clearSession();
  }

  Future<void> _clearSession() async {
    _epoch++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _tokens = null;
    _user = null;
    await _deleteStoredTokens();
    _notify();
  }

  Future<TokenSet?> _readStoredTokens() async {
    String? raw;
    try {
      raw = await _storage.read(storageKey);
    } catch (error) {
      if (kDebugMode) debugPrint('LowcoAuth: could not read stored tokens: $error');
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = readMap(jsonDecode(raw));
      if (json != null) return TokenSet.fromJson(json);
    } on FormatException {
      // Corrupt entry: fall through and drop it.
    }
    await _deleteStoredTokens();
    return null;
  }

  Future<void> _writeStoredTokens(TokenSet tokens) async {
    try {
      await _storage.write(storageKey, jsonEncode(tokens.toJson()));
    } catch (error) {
      // The session still works for this run; it just won't survive a restart.
      if (kDebugMode) debugPrint('LowcoAuth: could not persist tokens: $error');
    }
  }

  Future<void> _deleteStoredTokens() async {
    try {
      await _storage.delete(storageKey);
    } catch (error) {
      if (kDebugMode) debugPrint('LowcoAuth: could not delete stored tokens: $error');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// A token request that did not reach a verdict from the server (network
/// failure, timeout, 5xx) — the session is kept for a later retry.
bool _isTransient(Object error) {
  if (error is! LowcoAuthException) return true;
  final status = error.statusCode;
  return status != null && status >= 500;
}

String _formEncode(Map<String, String> fields) => fields.entries
    .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
    .join('&');

String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

class _TokenResponse {
  const _TokenResponse({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    required this.expiresIn,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;

  /// Seconds.
  final int expiresIn;
  final String? scope;
}
