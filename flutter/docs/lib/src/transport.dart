import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'codec.dart';
import 'errors.dart';
import 'json.dart';
import 'models.dart';
import 'transfer.dart';

/// The fixed API host every lowco SDK talks to.
const String lowcoBaseUrl = 'https://api.lowco.ai';

/// Route prefix of the document service.
const String docsBasePath = '/v1/documents';

/// Header carrying the organization id.
const String headerOrgId = 'X-Org-Id';

/// Low-level transport shared by every resource.
///
/// Most callers use `DocsClient` instead; this class is public so an endpoint
/// the SDK does not wrap yet can still be called with the same auth, envelope
/// and error handling. Paths are relative to `https://api.lowco.ai` and must
/// include the `/v1/documents` prefix.
class DocsHttpClient {
  /// Creates a transport.
  ///
  /// * [token] — user token or API key, sent as `Authorization: Bearer <token>`
  ///   unless [headers] already carry an `Authorization` header. Required.
  /// * [orgId] — sent as `X-Org-Id` unless [headers] already carry one.
  ///   Required: the service rejects every request without it.
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it.
  /// * [headers] — extra headers added to every request.
  /// * [httpClient] — custom `http.Client`; it is not closed by [close].
  ///
  /// Throws [ArgumentError] when [token] or [orgId] is blank.
  DocsHttpClient({
    required String token,
    required String orgId,
    Duration? timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  })  : _token = _requireNonBlank(token, 'token', 'Pass a user token or API key.'),
        _orgId = _requireNonBlank(
            orgId, 'orgId', 'The document service rejects requests without X-Org-Id.'),
        _timeout = timeout,
        _headers = Map.unmodifiable(headers ?? const <String, String>{}),
        _ownsHttp = httpClient == null,
        _http = httpClient ?? http.Client();

  final String _token;
  final String _orgId;
  final Duration? _timeout;
  final Map<String, String> _headers;
  final bool _ownsHttp;
  final http.Client _http;

  static final Random _random = Random();

  /// Sends a JSON request to `https://api.lowco.ai<path>` and returns the
  /// decoded response: `null` for an empty body, the `data` field of a JSON
  /// object that has one (the `{ status, data }` envelope), otherwise the
  /// decoded JSON as-is.
  ///
  /// [body] is JSON-encoded (model classes via `toJson()`); `null` sends no
  /// body. [query] values that are `null` are omitted; booleans become
  /// `true`/`false` and numbers their string form. [headers] are added after
  /// the client-wide headers.
  ///
  /// Throws [DocsException] on failure.
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path, body: body, query: query, headers: headers);
    _ensureOk(resp);
    return _decodeJson(resp);
  }

  /// Like [request] but ignores the response body (`204` and delete-style
  /// endpoints), so a non-JSON success body does not fail.
  Future<void> requestVoid(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    _ensureOk(await _send(method, path, body: body, query: query, headers: headers));
  }

  /// Sends a request and returns the response body as text (e.g. the
  /// `text/plain` health check).
  Future<String> requestText(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path, query: query, headers: headers, accept: '*/*');
    _ensureOk(resp);
    return _text(resp);
  }

  /// Sends a request and returns the raw response bytes with their content
  /// type and file name (`X-File-Name`, else `Content-Disposition`).
  Future<FileDownload> requestBytes(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path, query: query, headers: headers, accept: '*/*');
    _ensureOk(resp);
    return _download(resp);
  }

  /// Sends a request with redirects disabled and returns the `Location` of
  /// the redirect (resolved against the request URL).
  ///
  /// Throws [DocsException] when the response is not a redirect. Browsers
  /// (Flutter web) always follow redirects and never expose the `Location`,
  /// so this fails there with a message saying so.
  Future<String> requestRedirect(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path,
        query: query, headers: headers, accept: '*/*', followRedirects: false);
    final location = _location(resp);
    if (location != null) return location;
    _ensureOk(resp);
    throw DocsException(
      message: 'Expected a redirect from $path but got status ${resp.statusCode}. URL methods '
          'need an HTTP client that can disable redirects; browsers (Flutter web) always follow '
          'them, so call this from a server, the Dart VM or a mobile/desktop app.',
      status: resp.statusCode,
    );
  }

  /// Sends a request with redirects disabled and maps the three answers of
  /// the permalink endpoints: a redirect to [NodeFileResult.url], `202` to
  /// [NodeFileResult.restoring] (with `Retry-After` as
  /// [NodeFileResult.retryAfter]) and any other 2xx to
  /// [NodeFileResult.content].
  Future<NodeFileResult> requestNodeFile(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final resp = await _send(method, path,
        query: query, headers: headers, accept: '*/*', followRedirects: false);
    final location = _location(resp);
    if (location != null) return NodeFileResult(url: location);
    _ensureOk(resp);
    if (resp.statusCode == 202) {
      return NodeFileResult(
        restoring: decodeOne(_decodeJson(resp), ArchiveRestoring.fromJson),
        retryAfter: readInt(resp.headers['retry-after']?.trim()),
      );
    }
    return NodeFileResult(content: _download(resp));
  }

  /// Sends a `multipart/form-data` request and decodes the JSON response like
  /// [request].
  ///
  /// [fields] are text parts and [files] file parts, both as
  /// `(fieldName, value)` pairs so a field name may repeat; parts are written
  /// in order, text parts first.
  Future<Object?> requestMultipart(
    String method,
    String path, {
    List<(String, String)> fields = const [],
    List<(String, UploadFile)> files = const [],
    Map<String, Object?>? query,
    Map<String, String>? headers,
  }) async {
    final boundary = 'lowco-docs-${_randomToken()}';
    final resp = await _send(
      method,
      path,
      query: query,
      headers: headers,
      rawBody: _multipartBody(boundary, fields, files),
      rawContentType: 'multipart/form-data; boundary=$boundary',
    );
    _ensureOk(resp);
    return _decodeJson(resp);
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Uint8List? rawBody,
    String? rawContentType,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    String accept = 'application/json',
    bool followRedirects = true,
  }) async {
    var url = Uri.parse('$lowcoBaseUrl${path.startsWith('/') ? path : '/$path'}');
    final params = query == null ? const <String, String>{} : encodeQuery(query);
    if (params.isNotEmpty) url = url.replace(queryParameters: params);

    final abort = Completer<void>();
    final req = http.AbortableRequest(method, url, abortTrigger: abort.future)
      ..followRedirects = followRedirects;
    // `req.headers` is case-insensitive.
    req.headers['Accept'] = accept;
    req.headers.addAll(_headers);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body, toEncodable: toEncodable);
    } else if (rawBody != null) {
      req.headers['Content-Type'] = rawContentType ?? 'application/octet-stream';
      req.bodyBytes = rawBody;
    }
    if (!req.headers.containsKey('Authorization')) {
      req.headers['Authorization'] = 'Bearer $_token';
    }
    if (!req.headers.containsKey(headerOrgId)) {
      req.headers[headerOrgId] = _orgId;
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
      throw DocsException(message: e.message, status: 0);
    } on TimeoutException catch (e) {
      throw DocsException(message: e.message ?? 'Request timed out', status: 0);
    }
  }

  String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
        List.generate(32, (_) => chars.codeUnitAt(_random.nextInt(chars.length))));
  }
}

String _requireNonBlank(String value, String name, String hint) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '`$name` is required. $hint');
  }
  return value;
}

String _text(http.Response resp) => utf8.decode(resp.bodyBytes, allowMalformed: true);

Object? _decodeJson(http.Response resp) {
  final text = _text(resp);
  if (text.trim().isEmpty) return null;
  final Object? payload;
  try {
    payload = jsonDecode(text);
  } on FormatException catch (e) {
    throw DocsException(
        message: 'Invalid JSON response: ${e.message}', status: resp.statusCode, payload: text);
  }
  if (payload is Map && payload.containsKey('data')) return payload['data'];
  return payload;
}

/// Throws [DocsException] for a non-2xx status.
void _ensureOk(http.Response resp) {
  final status = resp.statusCode;
  if (status >= 200 && status < 300) return;
  final text = _text(resp);
  Object? payload;
  if (text.trim().isNotEmpty) {
    try {
      payload = jsonDecode(text);
    } on FormatException {
      payload = text;
    }
  }
  final info = errorInfoOf(payload);
  throw DocsException(
    message: info.message ?? 'Request failed with status $status',
    status: status,
    payload: payload,
    code: info.code,
  );
}

/// The `Location` of a 3xx response, resolved against the request URL.
String? _location(http.Response resp) {
  final status = resp.statusCode;
  if (status < 300 || status >= 400) return null;
  final location = resp.headers['location'];
  if (location == null || location.trim().isEmpty) return null;
  final base = resp.request?.url;
  return base == null ? location : base.resolve(location.trim()).toString();
}

FileDownload _download(http.Response resp) => FileDownload(
      data: resp.bodyBytes,
      contentType: resp.headers['content-type'] ?? 'application/octet-stream',
      fileName: fileNameOf(resp.headers),
    );

/// The file name of a download: `X-File-Name`, else the `filename*` or
/// `filename` parameter of `Content-Disposition`.
String? fileNameOf(Map<String, String> headers) {
  final explicit = headers['x-file-name'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final disposition = headers['content-disposition'];
  if (disposition == null) return null;
  final extended =
      RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(disposition);
  if (extended != null) {
    try {
      return Uri.decodeComponent(extended.group(1)!.trim());
    } on ArgumentError {
      // Fall through to the plain parameter.
    } on FormatException {
      // Fall through to the plain parameter.
    }
  }
  final quoted =
      RegExp(r'filename\s*=\s*"((?:[^"\\]|\\.)*)"', caseSensitive: false).firstMatch(disposition);
  if (quoted != null) {
    return quoted.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }
  return RegExp(r'filename\s*=\s*([^;\s]+)', caseSensitive: false)
      .firstMatch(disposition)
      ?.group(1);
}

Uint8List _multipartBody(
    String boundary, List<(String, String)> fields, List<(String, UploadFile)> files) {
  final out = BytesBuilder(copy: false);
  const crlf = [13, 10];
  void head(String disposition, String? contentType) {
    out.add(utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; $disposition\r\n'
        '${contentType == null ? '' : 'Content-Type: $contentType\r\n'}'
        '\r\n'));
  }

  for (final (name, value) in fields) {
    head('name="${_quoteParam(name)}"', null);
    out
      ..add(utf8.encode(value))
      ..add(crlf);
  }
  for (final (name, file) in files) {
    head('name="${_quoteParam(name)}"; filename="${_quoteParam(file.fileName)}"',
        file.contentType ?? 'application/octet-stream');
    out
      ..add(file.bytes)
      ..add(crlf);
  }
  out.add(utf8.encode('--$boundary--\r\n'));
  return out.takeBytes();
}

/// Escapes a multipart header parameter the way browsers do.
String _quoteParam(String value) =>
    value.replaceAll(RegExp(r'\r\n|\r|\n'), '%0D%0A').replaceAll('"', '%22');
