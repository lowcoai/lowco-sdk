import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_docs/lowcoai_docs.dart';

/// Records every request and answers with [respond].
class Recorder {
  Recorder([http.Response Function(http.Request)? respond])
      : _respond = respond ?? ((_) => envelope(null));

  final http.Response Function(http.Request) _respond;
  final requests = <http.Request>[];

  http.Request get last => requests.last;
  Object? get lastJson => jsonDecode(last.body);

  DocsClient client({
    String orgId = 'org_1',
    Map<String, String>? headers,
    Duration? timeout = const Duration(seconds: 30),
  }) =>
      DocsClient(
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

/// A success envelope: `{"status": 1, "data": data}`.
http.Response envelope(Object? data, [int status = 200, Map<String, String>? headers]) =>
    http.Response(jsonEncode({'status': 1, 'data': data}), status,
        headers: {'content-type': 'application/json', ...?headers});

http.Response jsonResponse(Object? body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A `307` redirect to [location].
http.Response redirect(String location) => http.Response('', 307, headers: {'location': location});

/// One part of a parsed `multipart/form-data` body.
class Part {
  Part(this.name, this.filename, this.contentType, this.value);

  final String name;
  final String? filename;
  final String? contentType;
  final String value;

  @override
  String toString() => 'Part($name, $filename, $contentType, $value)';
}

/// Parses the multipart body of [req] (enough for the SDK's own output).
List<Part> parseMultipart(http.Request req) {
  final type = req.headers['content-type']!;
  final boundary = RegExp(r'boundary=(.+)$').firstMatch(type)!.group(1)!;
  final body = latin1.decode(req.bodyBytes);
  _require(body.endsWith('--$boundary--\r\n'), 'closing boundary');
  final chunks = body.split('--$boundary');
  final parts = <Part>[];
  for (final chunk in chunks.sublist(1, chunks.length - 1)) {
    final content = chunk.substring(2, chunk.length - 2); // leading / trailing CRLF
    final split = content.indexOf('\r\n\r\n');
    final headerLines = content.substring(0, split).split('\r\n');
    final value = utf8.decode(latin1.encode(content.substring(split + 4)));
    String? disposition;
    String? partType;
    for (final line in headerLines) {
      final i = line.indexOf(':');
      final key = line.substring(0, i).toLowerCase();
      final v = line.substring(i + 1).trim();
      if (key == 'content-disposition') disposition = v;
      if (key == 'content-type') partType = v;
    }
    final name = RegExp(r'name="([^"]*)"').firstMatch(disposition!)!.group(1)!;
    final filename = RegExp(r'filename="([^"]*)"').firstMatch(disposition)?.group(1);
    parts.add(Part(name, filename, partType, value));
  }
  return parts;
}

void _require(bool condition, String what) {
  if (!condition) throw StateError('malformed multipart body: $what');
}

/// An `http.Client` that records whether it was closed.
class TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{"data":[]}')), 200);

  @override
  void close() => closed = true;
}
