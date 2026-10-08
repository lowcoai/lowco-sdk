import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

/// Records every request and answers with [respond].
class Recorder {
  Recorder([http.Response Function(http.Request)? respond])
      : _respond = respond ?? ((_) => envelope(null));

  final http.Response Function(http.Request) _respond;
  final requests = <http.Request>[];

  http.Request get last => requests.last;
  Object? get lastJson => jsonDecode(last.body);

  AgentxClient client({
    String? orgId = 'org_1',
    String? managerApiBasePath,
    String? kbApiBasePath,
    String? executorApiBasePath,
    Map<String, String>? defaultHeaders,
    Duration? timeout = const Duration(seconds: 30),
  }) =>
      AgentxClient(
        token: 'tok_123',
        orgId: orgId,
        managerApiBasePath: managerApiBasePath,
        kbApiBasePath: kbApiBasePath,
        executorApiBasePath: executorApiBasePath,
        defaultHeaders: defaultHeaders,
        timeout: timeout,
        httpClient: MockClient((req) async {
          requests.add(req);
          return _respond(req);
        }),
      );
}

http.Response envelope(Object? data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status,
        headers: {'content-type': 'application/json'});

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// One endpoint expectation for the table-driven sub-client tests.
class Endpoint {
  const Endpoint(
    this.name,
    this.call, {
    required this.method,
    required this.path,
    this.query = const {},
    this.body,
    this.response,
    this.check,
  });

  final String name;
  final Future<Object?> Function(AgentxClient c) call;
  final String method;
  final String path;
  final Map<String, String> query;

  /// Expected JSON body; `null` means no body at all.
  final Object? body;

  /// Canned reply (defaults to an envelope around `{}`).
  final http.Response Function()? response;

  /// Extra assertions on the decoded result.
  final void Function(Object? result)? check;
}

/// Registers one test per endpoint: verb, host, path, query, headers, body
/// and decoded result.
void runEndpoints(List<Endpoint> endpoints) {
  for (final e in endpoints) {
    test(e.name, () async {
      final rec = Recorder((_) => (e.response ?? () => envelope(<String, dynamic>{}))());
      final result = await e.call(rec.client());
      expect(rec.requests, hasLength(1));
      final req = rec.last;
      expect(req.method, e.method);
      expect(req.url.origin, lowcoBaseUrl);
      expect(req.url.path, e.path);
      expect(req.url.queryParameters, e.query);
      expect(req.headers['Authorization'], 'Bearer tok_123');
      expect(req.headers[headerOrgId], 'org_1');
      expect(req.headers['Accept'], 'application/json');
      if (e.body == null) {
        expect(req.body, isEmpty);
        expect(req.headers.containsKey('Content-Type'), isFalse);
      } else {
        expect(jsonDecode(req.body), e.body);
        expect(req.headers['Content-Type'], startsWith('application/json'));
      }
      e.check?.call(result);
    });
  }
}
