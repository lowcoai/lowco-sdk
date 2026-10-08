import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'codec.dart';
import 'errors.dart';

/// The fixed API host every lowco SDK talks to.
const String lowcoBaseUrl = 'https://api.lowco.ai';

/// Header carrying the organization id.
const String headerOrgId = 'X-Org-Id';

/// Low-level transport shared by every resource (the TS SDK's `HttpClient`).
///
/// Most callers use `IntegrationsClient` instead; this class is public so an
/// endpoint the SDK does not wrap yet can still be called with the same auth,
/// envelope and error handling.
class IntegrationsHttpClient {
  /// Creates a transport.
  ///
  /// * [token] — user token or API key, sent as `Authorization: Bearer <token>`
  ///   unless [headers] already carry an `Authorization` header. Required.
  /// * [orgId] — sent as `X-Org-Id` unless [headers] already carry one.
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it.
  /// * [headers] — extra headers added to every request.
  /// * [httpClient] — custom `http.Client`; it is not closed by [close].
  IntegrationsHttpClient({
    required String token,
    String? orgId,
    Duration? timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  })  : _token = _requireToken(token),
        _orgId = orgId,
        _timeout = timeout,
        _headers = Map.unmodifiable(headers ?? const <String, String>{}),
        _ownsHttp = httpClient == null,
        _http = httpClient ?? http.Client();

  final String _token;
  final String? _orgId;
  final Duration? _timeout;
  final Map<String, String> _headers;
  final bool _ownsHttp;
  final http.Client _http;

  /// Sends a request to `https://api.lowco.ai<path>` and returns the decoded
  /// response: `null` for an empty body, the `data` field of a JSON object
  /// that has one (the `{ success, data, ... }` envelope), otherwise the
  /// decoded JSON as-is.
  ///
  /// [body] is JSON-encoded (model classes via `toJson()`); `null` sends no
  /// body. [query] values follow the `PaginationQuery` encoding rules.
  /// [headers] are added after the client-wide headers.
  ///
  /// Throws [IntegrationsException] on failure.
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path, body: body, query: query, headers: headers);
    final text = _check(resp);
    if (text.trim().isEmpty) return null;
    final Object? payload;
    try {
      payload = jsonDecode(text);
    } on FormatException catch (e) {
      throw IntegrationsException(
          message: 'Invalid JSON response: ${e.message}', status: resp.statusCode, payload: text);
    }
    if (payload is Map && payload.containsKey('data')) return payload['data'];
    return payload;
  }

  /// Like [request] but ignores the response body (delete-style endpoints),
  /// so a non-JSON success body does not fail.
  Future<void> requestVoid(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    _check(await _send(method, path, body: body, query: query, headers: headers));
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    var url = Uri.parse('$lowcoBaseUrl${path.startsWith('/') ? path : '/$path'}');
    final params = query == null ? const <String, String>{} : encodeQuery(query);
    if (params.isNotEmpty) url = url.replace(queryParameters: params);

    final abort = Completer<void>();
    final req = http.AbortableRequest(method, url, abortTrigger: abort.future);
    // Same precedence as the TS SDK. `req.headers` is case-insensitive.
    req.headers['Accept'] = 'application/json';
    req.headers.addAll(_headers);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body, toEncodable: toEncodable);
    }
    if (!req.headers.containsKey('Authorization')) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    final orgId = _orgId;
    if (orgId != null && orgId.isNotEmpty && !req.headers.containsKey(headerOrgId)) {
      req.headers[headerOrgId] = orgId;
    }

    try {
      final future = _http.send(req).then(http.Response.fromStream);
      final timeout = _timeout;
      if (timeout == null) return await future;
      return await future.timeout(timeout, onTimeout: () {
        // Abort the in-flight request where the platform client supports it.
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException('Request timed out after ${timeout.inMilliseconds} ms', timeout);
      });
    } on http.ClientException catch (e) {
      throw IntegrationsException(message: e.message, status: 0);
    } on TimeoutException catch (e) {
      throw IntegrationsException(message: e.message ?? 'Request timed out', status: 0);
    }
  }
}

String _requireToken(String token) {
  if (token.trim().isEmpty) {
    throw ArgumentError.value(token, 'token', '`token` is required. Pass a user token or API key.');
  }
  return token;
}

/// Returns the body text, throwing [IntegrationsException] for a non-2xx status.
String _check(http.Response resp) {
  final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
  final status = resp.statusCode;
  if (status >= 200 && status < 300) return text;
  Object? payload;
  if (text.trim().isNotEmpty) {
    try {
      payload = jsonDecode(text);
    } on FormatException {
      // The TS SDK crashes here (status 0); keep the real status and raw text.
      payload = text;
    }
  }
  throw IntegrationsException(
      message: 'Request failed with status $status', status: status, payload: payload);
}
