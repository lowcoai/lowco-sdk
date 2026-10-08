import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'errors.dart';
import 'json.dart';

/// Pagination / filtering accepted by every list (and count) endpoint.
class ListParams {
  const ListParams({this.pageNo, this.size, this.filter, this.sort});

  final int? pageNo;
  final int? size;
  final String? filter;
  final String? sort;

  Map<String, String> toQuery() => {
        if (pageNo != null) 'pageNo': '$pageNo',
        if (size != null) 'size': '$size',
        if (filter != null) 'filter': filter!,
        if (sort != null) 'sort': sort!,
      };
}

/// Shared HTTP plumbing used by the manager, KB and executor sub-clients.
///
/// Internal: it is not exported from the package. [headers] is the mutable
/// header map owned by `AgentxClient`, so `setOrgId` / `setHeader` apply to
/// every sub-client at once.
class Transport {
  Transport({
    required http.Client httpClient,
    required bool ownsHttp,
    required this.headers,
    required Duration? timeout,
  })  : _http = httpClient,
        _ownsHttp = ownsHttp,
        _timeout = timeout;

  final http.Client _http;
  final bool _ownsHttp;
  final Duration? _timeout;

  /// Default headers sent with every request (Authorization, X-Org-Id, ...).
  final Map<String, String> headers;

  /// `/<apiBasePath>/<part>/<part>...` with every part slash-trimmed and
  /// URL-encoded.
  String joinPath(String apiBasePath, List<String> parts) => '/${[
        if (apiBasePath.isNotEmpty) apiBasePath,
        ...parts.map((p) => Uri.encodeComponent(trimSlashes(p))),
      ].join('/')}';

  http.AbortableRequest _build(String method, String path,
      {Map<String, String>? query,
      Object? body,
      required String accept,
      required Future<void> abortTrigger}) {
    var url = Uri.parse('$lowcoBaseUrl$path');
    if (query != null && query.isNotEmpty) url = url.replace(queryParameters: query);
    final req = http.AbortableRequest(method, url, abortTrigger: abortTrigger)
      ..headers.addAll({'Accept': accept, ...headers});
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    return req;
  }

  /// Sends a buffered request, aborting it and throwing [TimeoutException]
  /// when the configured timeout elapses.
  Future<http.Response> send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final abort = Completer<void>();
    final req = _build(method, path,
        query: query, body: body, accept: 'application/json', abortTrigger: abort.future);

    final future = _http.send(req).then(http.Response.fromStream);
    final timeout = _timeout;
    if (timeout == null) return future;
    return future.timeout(timeout, onTimeout: () {
      // Abort the in-flight request where the platform client supports it.
      if (!abort.isCompleted) abort.complete();
      throw TimeoutException('agentx: $method $path timed out', timeout);
    });
  }

  /// Opens a streamed request without any timeout. Completing [abortTrigger]
  /// aborts it (and closes the response stream).
  Future<http.StreamedResponse> openStream(String method, String path,
          {Object? body, required String accept, required Future<void> abortTrigger}) =>
      _http.send(_build(method, path, body: body, accept: accept, abortTrigger: abortTrigger));

  /// Sends a JSON request and decodes the (optionally enveloped) JSON reply.
  /// A 204 / blank body yields `null`.
  Future<Object?> request(String method, String path,
      {Map<String, String>? query, Object? body, required bool enveloped}) async {
    final resp = await send(method, path, query: query, body: body);
    return decodeResponse(resp, enveloped: enveloped);
  }

  /// Sends a request whose success body is irrelevant (it need not be JSON).
  Future<void> requestVoid(String method, String path, {Object? body}) async {
    checkStatus(await send(method, path, body: body));
  }

  /// Closes the underlying HTTP client if the SDK created it.
  void close() {
    if (_ownsHttp) _http.close();
  }
}

String trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/+$'), '');

String responseText(http.Response resp) => utf8.decode(resp.bodyBytes, allowMalformed: true);

void checkStatus(http.Response resp) {
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw buildHttpException(resp.statusCode, responseText(resp));
  }
}

Object? decodeResponse(http.Response resp, {required bool enveloped}) {
  checkStatus(resp);
  final text = responseText(resp);
  if (resp.statusCode == 204 || text.trim().isEmpty) return null;
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException catch (e) {
    throw AgentxException(
        statusCode: resp.statusCode,
        message: 'agentx: invalid JSON response: ${e.message}',
        body: text);
  }
  if (enveloped && parsed is Map && parsed.containsKey('data')) return parsed['data'];
  return parsed;
}

/// A JSON object as [T]; `null` / non-objects become `fromJson({})`.
T decodeOne<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObject(data, fromJson) ?? fromJson(const {});

/// A JSON array of objects as `List<T>`; `null` / non-arrays become `[]`.
List<T> decodeMany<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObjectList(data, fromJson) ?? <T>[];

/// A raw integer count. Tolerates a stringified number or an enveloped
/// `{ "data": n }`; anything else is 0.
int decodeCount(Object? data) => readInt(data is Map ? data['data'] : data) ?? 0;
