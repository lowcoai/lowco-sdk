import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_integrations/lowcoai_integrations.dart';

/// Records every request and answers with [respond].
class Recorder {
  Recorder([http.Response Function(http.Request)? respond])
      : _respond = respond ?? ((_) => envelope(null));

  final http.Response Function(http.Request) _respond;
  final requests = <http.Request>[];

  http.Request get last => requests.last;
  Object? get lastJson => jsonDecode(last.body);

  IntegrationsClient client({
    String? orgId = 'org_1',
    Map<String, String>? headers,
    Duration? timeout = const Duration(seconds: 30),
  }) =>
      IntegrationsClient(
        token: 'tok_123',
        orgId: orgId,
        headers: headers,
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

http.Response jsonResponse(Object? body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// An `http.Client` that records whether it was closed.
class TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{"data":[]}')), 200);

  @override
  void close() => closed = true;
}
