import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_auth/lowcoai_auth.dart';

import 'helpers.dart';

final _urlSafe32 = RegExp(r'^[A-Za-z0-9_-]{32}$');
final _urlSafe43 = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _urlSafe64 = RegExp(r'^[A-Za-z0-9_-]{64}$');

Matcher throwsAuth(String message) =>
    throwsA(isA<LowcoAuthException>().having((e) => e.message, 'message', message));

void main() {
  late Harness h;

  LowcoAuth create({http.Client? httpClient, String? scope}) {
    final auth = h.create(httpClient: httpClient, scope: scope);
    addTearDown(auth.dispose);
    return auth;
  }

  setUp(() => h = Harness());

  group('loginWithRedirect', () {
    test('opens the login page with the PKCE parameters', () async {
      final auth = create();
      await auth.loginWithRedirect();

      final url = h.authenticator.calls.single;
      expect(h.authenticator.schemes.single, 'com.example.app');
      expect(url.origin, 'https://login.lowco.ai');
      expect(url.path, '/login');
      final params = url.queryParameters;
      expect(params.keys, [
        'theme',
        'tenant_id',
        'client_id',
        'redirect_uri',
        'response_type',
        'scope',
        'state',
        'nonce',
        'code_challenge',
        'code_challenge_method',
      ]);
      expect(params['theme'], 'dark', reason: 'existing query parameters are kept');
      expect(params['tenant_id'], tenantId);
      expect(params['client_id'], clientId);
      expect(params['redirect_uri'], redirectUri);
      expect(params['response_type'], 'code');
      expect(params['scope'], 'openid profile email offline_access');
      expect(params['state'], matches(_urlSafe32));
      expect(params['nonce'], matches(_urlSafe32));
      expect(params['nonce'], isNot(params['state']));
      expect(params['code_challenge'], matches(_urlSafe43));
      expect(params['code_challenge_method'], 'S256');
      expect(url.query, contains('scope=openid+profile+email+offline_access'));
    });

    test('exchanges the code with the matching PKCE verifier', () async {
      final auth = create();
      await auth.loginWithRedirect();

      final request = h.server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), tokenUrl);
      expect(request.headers['Content-Type'], 'application/x-www-form-urlencoded');
      final body = request.bodyFields;
      expect(body.keys, [
        'grant_type',
        'tenant_id',
        'client_id',
        'code',
        'code_verifier',
        'redirect_uri',
      ]);
      expect(body['grant_type'], 'authorization_code');
      expect(body['tenant_id'], tenantId);
      expect(body['client_id'], clientId);
      expect(body['code'], 'code_1');
      expect(body['redirect_uri'], redirectUri);

      final verifier = body['code_verifier']!;
      expect(verifier, matches(_urlSafe64));
      final challenge =
          base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
      expect(h.authenticator.calls.single.queryParameters['code_challenge'], challenge);
    });

    test('persists the React SDK token JSON and updates the state', () async {
      final auth = create();
      expect(auth.isLoading, isTrue);
      await auth.loginWithRedirect(appState: {'returnTo': '/orders'});

      final expected = {
        'access_token': 'at_1',
        'refresh_token': 'rt_1',
        'id_token': idToken,
        'expires_at': h.clock.ms + 3600 * 1000,
        'scope': 'openid profile email offline_access',
      };
      expect(auth.storageKey, storageKey);
      expect(h.stored, expected);
      expect(h.issued.single.toJson(), expected);
      expect(auth.tokens!.toJson(), expected);
      expect(h.appStates, [
        {'returnTo': '/orders'},
      ]);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isLoading, isFalse);
      expect(auth.error, isNull);
      expect(auth.user!.sub, 'user_1');
      expect(auth.user!.email, 'ada@example.com');
      expect(h.notifications, greaterThan(0));
    });

    test('uses fresh state, nonce and verifier on every attempt and honours scope', () async {
      final auth = create(scope: 'openid');
      await auth.loginWithRedirect();
      await auth.loginWithRedirect(scope: 'openid email');

      final first = h.authenticator.calls[0].queryParameters;
      final second = h.authenticator.calls[1].queryParameters;
      expect(first['scope'], 'openid');
      expect(second['scope'], 'openid email');
      expect(second['state'], isNot(first['state']));
      expect(second['code_challenge'], isNot(first['code_challenge']));
      expect(h.bodies[0]['code_verifier'], isNot(h.bodies[1]['code_verifier']));
    });

    test('is loading while the browser is open and concurrent calls share one flow', () async {
      final callback = Completer<String>();
      h.authenticator.handler = (_) => callback.future;
      final auth = create();

      final first = auth.loginWithRedirect();
      final second = auth.loginWithRedirect();
      await Future<void>.delayed(Duration.zero);
      expect(auth.isLoading, isTrue);
      expect(h.authenticator.calls, hasLength(1));

      final state = h.authenticator.calls.single.queryParameters['state'];
      callback.complete('$redirectUri?code=code_1&state=$state');
      await Future.wait([first, second]);
      expect(auth.isLoading, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(h.server.requests, hasLength(1));
    });

    test('rejects a callback with the wrong state without exchanging the code', () async {
      h.authenticator.handler = (_) async => '$redirectUri?code=code_1&state=forged';
      final auth = create();
      await auth.loginWithRedirect();

      expect(auth.error!.message, 'OAuth state mismatch.');
      expect(auth.error!.code, 'invalid_state');
      expect(h.server.requests, isEmpty);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.isLoading, isFalse);
      expect(h.appStates, isEmpty);
    });

    test('surfaces an OAuth error returned to the redirect URI', () async {
      h.authenticator.handler =
          (url) async => '$redirectUri?error=access_denied&error_description=User+denied+access'
              '&state=${url.queryParameters['state']}';
      final auth = create();
      await auth.loginWithRedirect();

      expect(auth.error!.code, 'access_denied');
      expect(auth.error!.message, 'User denied access');
      expect(h.server.requests, isEmpty);
      expect(auth.isAuthenticated, isFalse);
    });

    test('a callback without a code is an error', () async {
      h.authenticator.handler = (url) async => '$redirectUri?state=${url.queryParameters['state']}';
      final auth = create();
      await auth.loginWithRedirect();
      expect(auth.error!.message, 'Missing authorization code.');
    });

    test('cancelling is not an error and keeps the existing session', () async {
      h.store(expiresIn: const Duration(hours: 1));
      final auth = create();
      await auth.initialize();
      h.authenticator.handler =
          (_) async => throw PlatformException(code: 'CANCELED', message: 'User canceled login');

      await auth.loginWithRedirect();
      expect(auth.error, isNull);
      expect(auth.isLoading, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(h.stored, isNotNull);
      expect(h.server.requests, isEmpty);
    });

    test('a rejected code exchange clears the session and sets error', () async {
      h.store(expiresIn: const Duration(hours: 1));
      h.server.respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
      final auth = create();
      await auth.initialize();
      await auth.loginWithRedirect();

      expect(auth.error!.message, 'Authorization code exchange failed.');
      expect(auth.error!.statusCode, 400);
      expect(auth.error!.code, 'invalid_grant');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.tokens, isNull);
      expect(h.stored, isNull);
      expect(h.issued, isEmpty);
    });

    test('other browser failures are wrapped', () async {
      h.authenticator.handler = (_) async => throw PlatformException(code: 'EUNKNOWN');
      final auth = create();
      await auth.loginWithRedirect();
      expect(auth.error!.message, 'Authentication failed.');
      expect(auth.error!.cause, isA<PlatformException>());
    });

    test('the next attempt clears the previous error', () async {
      h.authenticator.handler = (_) async => '$redirectUri?code=x&state=forged';
      final auth = create();
      await auth.loginWithRedirect();
      expect(auth.error, isNotNull);

      h.authenticator.handler = FakeAuthenticator().handler;
      await auth.loginWithRedirect();
      expect(auth.error, isNull);
      expect(auth.isAuthenticated, isTrue);
    });
  });

  group('initialize', () {
    test('without stored tokens the user is signed out', () async {
      final auth = create();
      expect(auth.isLoading, isTrue);
      await auth.initialize();
      expect(auth.isLoading, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
      expect(h.server.requests, isEmpty);
    });

    test('valid tokens are restored as is', () async {
      h.store(expiresIn: const Duration(minutes: 30), idToken: idToken);
      final auth = create();
      await auth.initialize();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.tokens!.accessToken, 'at_stored');
      expect(auth.user!.name, 'Ada Lovelace');
      expect(h.server.requests, isEmpty);
      expect(h.issued, isEmpty, reason: 'onTokens only fires for fresh tokens');
    });

    test('expired tokens with a refresh token are refreshed and merged', () async {
      h.store(expiresIn: const Duration(seconds: 30), idToken: idToken); // inside the 60 s skew
      h.server.respond = (_) =>
          tokenResponse(accessToken: 'at_new', refreshToken: null, scope: null, expiresIn: 600);
      final auth = create();
      await auth.initialize();

      expect(h.bodies.single, {
        'grant_type': 'refresh_token',
        'tenant_id': tenantId,
        'client_id': clientId,
        'refresh_token': 'rt_stored',
      });
      final expected = {
        'access_token': 'at_new',
        'refresh_token': 'rt_stored',
        'id_token': idToken,
        'expires_at': h.clock.ms + 600 * 1000,
        'scope': 'openid',
      };
      expect(auth.tokens!.toJson(), expected);
      expect(h.stored, expected);
      expect(h.issued.single.toJson(), expected);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isLoading, isFalse);
    });

    test('expired tokens without a refresh token are cleared', () async {
      h.store(expiresIn: const Duration(minutes: -5), refreshToken: null);
      final auth = create();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.tokens, isNull);
      expect(h.stored, isNull);
      expect(h.server.requests, isEmpty);
    });

    test('a rejected refresh clears the session without opening the login page', () async {
      h.store(expiresIn: const Duration(minutes: -5));
      h.server.respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
      final auth = create();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.isLoading, isFalse);
      expect(auth.error, isNull);
      expect(h.stored, isNull);
      expect(h.authenticator.calls, isEmpty);
      expect(h.notifications, greaterThan(0));
    });

    test('a refresh that fails for network reasons keeps the session', () async {
      h.store(expiresIn: const Duration(minutes: -5));
      final offline = MockClient((_) async => throw http.ClientException('offline'));
      final auth = create(httpClient: offline);
      await auth.initialize();

      expect(auth.isAuthenticated, isTrue, reason: 'the refresh token can still recover it');
      expect(auth.tokens!.accessToken, 'at_stored');
      expect(h.stored, isNotNull);
      expect(auth.isLoading, isFalse);
    });

    test('a 5xx during refresh is treated as transient', () async {
      h.store(expiresIn: const Duration(minutes: -5));
      h.server.respond = (_) => http.Response('upstream down', 503);
      final auth = create();
      await auth.initialize();
      expect(auth.isAuthenticated, isTrue);
      expect(h.stored, isNotNull);
    });

    test('a corrupt stored entry is dropped', () async {
      h.storage.values[storageKey] = '{not json';
      final auth = create();
      await auth.initialize();
      expect(auth.isAuthenticated, isFalse);
      expect(h.stored, isNull);
    });

    test('is idempotent', () async {
      final auth = create();
      expect(identical(auth.initialize(), auth.initialize()), isTrue);
    });
  });

  group('getAccessTokenSilently', () {
    test('returns a valid token without a request', () async {
      h.store(expiresIn: const Duration(minutes: 30));
      final auth = create();
      await auth.initialize();
      expect(await auth.getAccessTokenSilently(), 'at_stored');
      expect(h.server.requests, isEmpty);
    });

    test('refreshes an expiring token and merges the rotated one', () async {
      final auth = create();
      await auth.loginWithRedirect();
      h.server.respond =
          (_) => tokenResponse(accessToken: 'at_2', refreshToken: 'rt_2', scope: null);
      h.clock.current = h.clock.current.add(const Duration(minutes: 59, seconds: 30));

      expect(await auth.getAccessTokenSilently(), 'at_2');
      expect(h.bodies.last, {
        'grant_type': 'refresh_token',
        'tenant_id': tenantId,
        'client_id': clientId,
        'refresh_token': 'rt_1',
      });
      expect(h.stored, {
        'access_token': 'at_2',
        'refresh_token': 'rt_2',
        'id_token': idToken,
        'expires_at': h.clock.ms + 3600 * 1000,
        'scope': 'openid profile email offline_access',
      });
      expect(h.issued.map((t) => t.accessToken), ['at_1', 'at_2']);
      expect(auth.user!.email, 'ada@example.com');
    });

    test('concurrent callers share one refresh request', () async {
      h.store(expiresIn: const Duration(minutes: -1));
      h.server.respond = (_) => tokenResponse(accessToken: 'at_2');
      final auth = create();
      final tokens = await Future.wait([
        auth.getAccessTokenSilently(),
        auth.getAccessTokenSilently(),
        auth.getAccessTokenSilently(),
      ]);
      expect(tokens, ['at_2', 'at_2', 'at_2']);
      expect(h.server.requests, hasLength(1));
    });

    test('reads the stored tokens before initialize, like the TS SDK', () async {
      h.store(expiresIn: const Duration(minutes: 30));
      final auth = create();
      expect(await auth.getAccessTokenSilently(), 'at_stored');
    });

    test('throws Not authenticated. without a session', () async {
      final auth = create();
      await auth.initialize();
      await expectLater(auth.getAccessTokenSilently(), throwsAuth('Not authenticated.'));
    });

    test('throws Session expired. and clears when there is no refresh token', () async {
      h.server.respond = (_) => tokenResponse(refreshToken: null, idToken: idToken);
      final auth = create();
      await auth.loginWithRedirect();
      h.clock.current = h.clock.current.add(const Duration(hours: 2));

      await expectLater(auth.getAccessTokenSilently(), throwsAuth('Session expired.'));
      expect(auth.isAuthenticated, isFalse);
      expect(h.stored, isNull);
    });

    test('throws Session expired. and clears when the refresh is rejected', () async {
      h.store(expiresIn: const Duration(minutes: -1));
      h.server.respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
      final auth = create();

      await expectLater(auth.getAccessTokenSilently(), throwsAuth('Session expired.'));
      expect(auth.isAuthenticated, isFalse);
      expect(h.stored, isNull);
      expect(h.authenticator.calls, isEmpty);
    });

    test('keeps the session when the refresh fails for network reasons', () async {
      h.store(expiresIn: const Duration(minutes: -1));
      final auth =
          create(httpClient: MockClient((_) async => throw http.ClientException('offline')));

      await expectLater(
        auth.getAccessTokenSilently(),
        throwsA(isA<LowcoAuthException>()
            .having((e) => e.message, 'message', 'Refresh token exchange failed.')
            .having((e) => e.cause, 'cause', isA<http.ClientException>())),
      );
      expect(h.stored, isNotNull);
    });
  });

  group('logout', () {
    test('clears storage and state and notifies', () async {
      final auth = create();
      await auth.loginWithRedirect();
      final before = h.notifications;

      await auth.logout();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.tokens, isNull);
      expect(auth.user, isNull);
      expect(auth.error, isNull);
      expect(h.stored, isNull);
      expect(h.notifications, greaterThan(before));
      await expectLater(auth.getAccessTokenSilently(), throwsAuth('Not authenticated.'));
    });

    test('a refresh that lands after logout is discarded', () async {
      h.store(expiresIn: const Duration(minutes: -1));
      final response = Completer<http.Response>();
      final auth = create(httpClient: MockClient((_) => response.future));

      final pending = auth.getAccessTokenSilently();
      await Future<void>.delayed(Duration.zero);
      await auth.logout();
      response.complete(tokenResponse(accessToken: 'at_late'));

      await expectLater(pending, throwsA(isA<LowcoAuthException>()));
      expect(auth.isAuthenticated, isFalse);
      expect(h.stored, isNull);
    });
  });

  group('tokens and users', () {
    test('TokenSet JSON uses the React SDK keys and omits absent fields', () {
      const tokens = TokenSet(accessToken: 'a', expiresAt: 1790000000000);
      expect(tokens.toJson(), {'access_token': 'a', 'expires_at': 1790000000000});
      final parsed = TokenSet.fromJson({
        'access_token': 'a',
        'refresh_token': '',
        'expires_at': '1790000000000',
        'expires_in': 3600,
        'token_type': 'Bearer',
      });
      expect(parsed.toJson(), {'access_token': 'a', 'expires_at': 1790000000000});
      expect(parsed.expiresAtTime, DateTime.utc(2026, 9, 21, 14, 13, 20));
    });

    test('validity honours the 60 s skew', () {
      final now = DateTime.utc(2026);
      TokenSet at(Duration left, {String? refresh}) => TokenSet(
            accessToken: 'a',
            refreshToken: refresh,
            expiresAt: now.add(left).millisecondsSinceEpoch,
          );
      expect(at(const Duration(seconds: 61)).isAccessTokenValid(now: now), isTrue);
      expect(at(const Duration(seconds: 60)).isAccessTokenValid(now: now), isFalse);
      expect(at(const Duration(seconds: 10)).canRecoverSession(now: now), isFalse);
      expect(at(const Duration(seconds: 10), refresh: 'r').canRecoverSession(now: now), isTrue);
      expect(
        const TokenSet(accessToken: '', refreshToken: 'r', expiresAt: 0).canRecoverSession(),
        isFalse,
      );
    });

    test('decodes the JWT payload without verifying it (UTF-8 aware)', () {
      final token = jwt({
        'sub': 'u',
        'name': 'José Ñúñez',
        'roles': ['admin']
      });
      expect(decodeJwtPayload(token), {
        'sub': 'u',
        'name': 'José Ñúñez',
        'roles': ['admin'],
      });
      expect(decodeJwtPayload(null), isNull);
      expect(decodeJwtPayload('opaque-token'), isNull);
      expect(decodeJwtPayload('a.!!!.c'), isNull);
      expect(decodeJwtPayload('a.${base64Url.encode(utf8.encode('[1]'))}.c'), isNull);
    });

    test('UserProfile prefers the id_token and falls back to the access token', () {
      final fromId = UserProfile.fromTokens(
        TokenSet(accessToken: jwt({'sub': 'from_access'}), idToken: idToken, expiresAt: 0),
      )!;
      expect(fromId.sub, 'user_1');
      expect(fromId.name, 'Ada Lovelace');
      expect(fromId.picture, 'https://img/ada.png');
      expect(fromId['tenant_id'], 't1');
      expect(fromId.claims['email'], 'ada@example.com');

      final fromAccess = UserProfile.fromTokens(
        TokenSet(accessToken: jwt({'sub': 'from_access', 'email': 7}), expiresAt: 0),
      )!;
      expect(fromAccess.sub, 'from_access');
      expect(fromAccess.email, isNull, reason: 'non-string claims are not coerced');
      expect(fromAccess['email'], 7);

      expect(UserProfile.fromTokens(const TokenSet(accessToken: 'opaque', expiresAt: 0)), isNull);
    });
  });

  test('constructor validation and defaults', () {
    expect(
      () => LowcoAuth(
        domain: domain,
        loginPageUrl: loginPage,
        tenantId: ' ',
        clientId: clientId,
        redirectUri: redirectUri,
        storage: InMemoryTokenStorage(),
      ),
      throwsArgumentError,
    );
    final auth = LowcoAuth(
      domain: 'https://api.lowco.ai/v1/identity///',
      loginPageUrl: loginPage,
      tenantId: tenantId,
      clientId: clientId,
      redirectUri: 'https://app.example.com/auth.html',
      storage: InMemoryTokenStorage(),
      httpClient: h.server.client,
    );
    addTearDown(auth.dispose);
    expect(auth.domain, 'https://api.lowco.ai/v1/identity');
    expect(auth.callbackUrlScheme, 'https');
    expect(auth.scope, 'openid profile email offline_access');
  });
}
