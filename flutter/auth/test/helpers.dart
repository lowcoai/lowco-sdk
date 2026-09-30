import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_auth/lowcoai_auth.dart';

const domain = 'https://api.lowco.ai/v1/identity/';
const loginPage = 'https://login.lowco.ai/login?theme=dark';
const tenantId = 't1';
const clientId = 'c1';
const redirectUri = 'com.example.app://callback';
const storageKey = 'lowco:tokens:t1:c1';
const tokenUrl = 'https://api.lowco.ai/v1/identity/tenants/t1/oauth/token';

/// An unsigned JWT carrying [claims].
String jwt(Map<String, dynamic> claims) => '${_segment({'alg': 'none'})}.${_segment(claims)}.sig';

String _segment(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

final idToken = jwt({
  'sub': 'user_1',
  'email': 'ada@example.com',
  'name': 'Ada Lovelace',
  'picture': 'https://img/ada.png',
  'tenant_id': 't1',
});

http.Response tokenResponse({
  String accessToken = 'at_1',
  String? refreshToken = 'rt_1',
  String? idToken,
  int expiresIn = 3600,
  String? scope = 'openid profile email offline_access',
}) =>
    http.Response(
      jsonEncode({
        'access_token': accessToken,
        'token_type': 'Bearer',
        'expires_in': expiresIn,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (idToken != null) 'id_token': idToken,
        if (scope != null) 'scope': scope,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Fake token endpoint recording every request.
class TokenServer {
  TokenServer([http.Response Function(Map<String, String> fields)? respond])
      : respond = respond ?? ((_) => tokenResponse(idToken: idToken));

  http.Response Function(Map<String, String> fields) respond;
  final requests = <http.Request>[];

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    return respond(request.bodyFields);
  });

  List<Map<String, String>> get bodies => [for (final r in requests) r.bodyFields];
}

/// Fake browser session: answers with the redirect URI carrying a code and
/// the state it was given, unless [handler] says otherwise.
class FakeAuthenticator {
  final calls = <Uri>[];
  final schemes = <String>[];

  Future<String> Function(Uri url) handler =
      (url) async => '$redirectUri?code=code_1&state=${url.queryParameters['state']}';

  Future<String> call(Uri url, String callbackUrlScheme) {
    calls.add(url);
    schemes.add(callbackUrlScheme);
    return handler(url);
  }
}

/// A controllable clock.
class Clock {
  Clock(this.current);

  DateTime current;

  DateTime call() => current;

  int get ms => current.millisecondsSinceEpoch;
}

/// Everything a [LowcoAuth] under test talks to.
class Harness {
  Harness({TokenServer? server, InMemoryTokenStorage? storage})
      : server = server ?? TokenServer(),
        storage = storage ?? InMemoryTokenStorage();

  final TokenServer server;
  final InMemoryTokenStorage storage;
  final authenticator = FakeAuthenticator();
  final clock = Clock(DateTime.utc(2026, 9, 30, 12));
  final issued = <TokenSet>[];
  final appStates = <Map<String, dynamic>?>[];
  var notifications = 0;

  LowcoAuth create({http.Client? httpClient, String? scope}) {
    final auth = LowcoAuth(
      domain: domain,
      loginPageUrl: loginPage,
      tenantId: tenantId,
      clientId: clientId,
      redirectUri: redirectUri,
      scope: scope ?? defaultScope,
      storage: storage,
      onTokens: issued.add,
      onRedirectCallback: appStates.add,
      authenticator: authenticator.call,
      httpClient: httpClient ?? server.client,
    )..now = clock.call;
    auth.addListener(() => notifications++);
    return auth;
  }

  /// Stores a token set expiring [expiresIn] from now.
  void store({
    String accessToken = 'at_stored',
    String? refreshToken = 'rt_stored',
    String? idToken,
    required Duration expiresIn,
    String? scope = 'openid',
  }) {
    storage.values[storageKey] = jsonEncode(TokenSet(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: clock.current.add(expiresIn).millisecondsSinceEpoch,
      scope: scope,
    ).toJson());
  }

  /// Form bodies of every token request.
  List<Map<String, String>> get bodies => server.bodies;

  Map<String, dynamic>? get stored {
    final raw = storage.values[storageKey];
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }
}
