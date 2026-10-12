// The transport every generated method calls: auth, the envelope, typed
// errors, file inputs (multipart or by reference), job waiting, pagination
// and retries. Hand-written; generated.dart holds the types and methods.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'generated.dart';

/// The API host every request goes to unless `baseUrl` or LOWCO_API_BASE_URL says otherwise.
const defaultBaseUrl = 'https://api.lowco.ai';

/// This SDK's version; its major and minor follow the API document it was generated from.
const sdkVersion = '1.1.0';

/// Thrown for every failed call: an error envelope, a network failure, a timeout or invalid input.
class LowcoApiError implements Exception {
  LowcoApiError(this.message,
      {required this.status,
      required this.reason,
      this.param,
      this.details,
      this.requestId,
      this.docUrl,
      this.retryable,
      this.retryAfter,
      this.payload});

  /// For people; branch on [reason].
  final String message;

  /// The HTTP status, or 0 when no response was received.
  final int status;

  /// The stable error code (see [ErrorReason] and [errorReasons]).
  final String reason;

  /// The parameter at fault.
  final String? param;

  /// Each failing item of a validation error.
  final List<ErrorDetail>? details;

  /// Quote this to support.
  final String? requestId;

  /// The reason's entry on docs.lowco.ai/api/errors.
  final String? docUrl;

  /// Whether the same request may succeed later.
  final bool? retryable;

  /// The API's Retry-After, when it sent one.
  final Duration? retryAfter;

  /// The parsed error body, or null.
  final Object? payload;

  @override
  String toString() => 'LowcoApiError($status $reason: $message${requestId == null ? '' : ' [request $requestId]'})';
}

/// Thrown by `jobs.wait` when a job failed or was cancelled; [job] is its last state.
class LowcoJobError extends LowcoApiError {
  LowcoJobError(super.message, this.job,
      {required super.status, required super.reason, super.param, super.details, super.requestId, super.docUrl, super.retryable});

  final Job job;
}

/// Thrown by `jobs.wait` when the job is still running at the timeout.
class LowcoTimeoutError implements Exception {
  LowcoTimeoutError(this.jobId, this.timeout);
  final String jobId;
  final Duration timeout;

  @override
  String toString() => 'LowcoTimeoutError(job $jobId did not finish within $timeout)';
}

/// One file input. Local inputs (path, bytes, stream) are sent as multipart parts; remote ones by reference.
sealed class FileInput {
  const FileInput({this.password});

  /// A local file by path (read when the call is made).
  factory FileInput.path(String path, {String? filename, String? password}) = _PathFile;

  /// Bytes in memory.
  factory FileInput.bytes(List<int> data, {String? filename, String? password}) = _BytesFile;

  /// A stream of bytes, read to the end when the call is made.
  factory FileInput.stream(Stream<List<int>> stream, {String? filename, String? password}) = _StreamFile;

  /// A public https URL the API fetches (file_url).
  factory FileInput.url(String url, {String? password}) = _UrlFile;

  /// A stored file (file_id from files.upload or an earlier output).
  factory FileInput.id(String fileId, {String? password}) = _IdFile;

  /// Base64 or a data: URL (up to 5 MB decoded).
  factory FileInput.base64(String data, {String? filename, String? password}) = _Base64File;

  /// Opens a protected PDF; never stored.
  final String? password;

  bool get _local;
}

abstract class _LocalFile extends FileInput {
  const _LocalFile({this.filename, super.password});
  final String? filename;
  @override
  bool get _local => true;
  Future<(String, Uint8List)> _read();
}

class _PathFile extends _LocalFile {
  const _PathFile(this.path, {super.filename, super.password});
  final String path;
  @override
  Future<(String, Uint8List)> _read() async =>
      (filename ?? path.split(Platform.pathSeparator).last, await File(path).readAsBytes());
}

class _BytesFile extends _LocalFile {
  const _BytesFile(this.data, {super.filename, super.password});
  final List<int> data;
  @override
  Future<(String, Uint8List)> _read() async => (filename ?? 'file', Uint8List.fromList(data));
}

class _StreamFile extends _LocalFile {
  const _StreamFile(this.stream, {super.filename, super.password});
  final Stream<List<int>> stream;
  @override
  Future<(String, Uint8List)> _read() async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      b.add(chunk);
    }
    return (filename ?? 'file', b.takeBytes());
  }
}

abstract class _RemoteFile extends FileInput {
  const _RemoteFile({super.password});
  @override
  bool get _local => false;
  Map<String, dynamic> _reference();
}

class _UrlFile extends _RemoteFile {
  const _UrlFile(this.url, {super.password});
  final String url;
  @override
  Map<String, dynamic> _reference() => {'file_url': url, if (password != null) 'password': password};
}

class _IdFile extends _RemoteFile {
  const _IdFile(this.fileId, {super.password});
  final String fileId;
  @override
  Map<String, dynamic> _reference() => {'file_id': fileId, if (password != null) 'password': password};
}

class _Base64File extends _RemoteFile {
  const _Base64File(this.data, {this.filename, super.password});
  final String data;
  final String? filename;
  @override
  Map<String, dynamic> _reference() =>
      {'file_base64': data, if (filename != null) 'filename': filename, if (password != null) 'password': password};
}

/// Options of a resource call.
class RequestOptions {
  const RequestOptions({this.requestId, this.idempotencyKey, this.timeout});

  /// Your own request id, echoed in X-Request-Id.
  final String? requestId;

  /// Makes a submission safe to retry for 24 hours (see [newIdempotencyKey]).
  final String? idempotencyKey;

  final Duration? timeout;
}

/// Options of an operation call.
class CallOptions extends RequestOptions {
  const CallOptions({this.mode, this.accept, super.requestId, super.idempotencyKey, super.timeout});

  /// 'async' always answers 202 with a job.
  final String? mode;

  /// The output's own type (application/pdf, image/png, image/svg+xml) to receive the single output file itself in [Answer.bytes].
  final String? accept;
}

/// An operation's answer: the result inline (200), a job (202), or the output file's bytes.
class Answer<T> {
  Answer._(this.status, {this.data, this.job, this.bytes, this.contentType, this.requestId, this.replayed = false, this.creditsUsed});

  final int status;

  /// The result, when the operation finished in the request.
  final T? data;

  /// The job, when the operation was accepted as one (status 202).
  final Job? job;

  /// The output file, when `accept` asked for its type.
  final Uint8List? bytes;
  final String? contentType;
  final String? requestId;

  /// True when an Idempotency-Key replayed an earlier submission.
  final bool replayed;

  /// Credits this call consumed (live, metered calls).
  final String? creditsUsed;
}

class _Raw {
  _Raw(this.status, this.headers, this.body, this.bytes, this.contentType);
  final int status;
  final Map<String, String> headers;
  final Object? body;
  final Uint8List bytes;
  final String contentType;
}

/// A new Idempotency-Key: store it with your record before calling, and reuse it on retries.
String newIdempotencyKey() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

const _terminal = {'succeeded', 'failed', 'cancelled'};

/// Sends requests and decodes answers.
class Core {
  Core({String? apiKey, String? baseUrl, http.Client? httpClient, Duration timeout = const Duration(seconds: 60), int maxRetries = 2})
      : _key = apiKey ?? Platform.environment['LOWCO_API_KEY'] ?? '',
        baseUrl = (baseUrl ?? Platform.environment['LOWCO_API_BASE_URL'] ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _timeout = timeout,
        _maxRetries = maxRetries {
    if (_key.isEmpty) {
      throw LowcoApiError('apiKey is required (lc_live_… or lc_test_…): pass it or set LOWCO_API_KEY', status: 0, reason: ErrorReason.missingKey);
    }
  }

  final String _key;
  final String baseUrl;
  final http.Client _http;
  final Duration _timeout;
  final int _maxRetries;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final u = Uri.parse(path.startsWith('http') ? path : baseUrl + path);
    final q = <String, String>{...u.queryParameters};
    query?.forEach((k, v) {
      if (v != null) q[k] = '$v';
    });
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Future<_Raw> _send(String method, Uri uri,
      {Future<http.BaseRequest> Function()? build, bool auth = true, bool follow = true, RequestOptions? options, String? accept, bool? retrySafe}) async {
    final safe = (retrySafe ?? method == 'GET') || options?.idempotencyKey != null;
    for (var attempt = 0;; attempt++) {
      final http.BaseRequest req = build != null ? await build() : http.Request(method, uri);
      req.followRedirects = follow;
      req.headers['X-Client-User-Agent'] = 'lowcoai-api-dart/$sdkVersion';
      req.headers['Accept'] = accept ?? 'application/json';
      if (auth) req.headers['Authorization'] = 'Bearer $_key';
      if (options?.requestId != null) req.headers['X-Request-Id'] = options!.requestId!;
      if (options?.idempotencyKey != null) req.headers['Idempotency-Key'] = options!.idempotencyKey!;
      http.StreamedResponse res;
      try {
        res = await _http.send(req).timeout(options?.timeout ?? _timeout);
      } on Object catch (e) {
        if (safe && attempt < _maxRetries) {
          await Future<void>.delayed(Duration(milliseconds: 500 << attempt));
          continue;
        }
        throw LowcoApiError('Network error: $e', status: 0, reason: ErrorReason.serviceUnavailable, retryable: true);
      }
      final bytes = await res.stream.toBytes();
      final ctype = res.headers['content-type'] ?? '';
      Object? body;
      if (ctype.contains('json') && bytes.isNotEmpty) {
        try {
          body = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          body = utf8.decode(bytes, allowMalformed: true);
        }
      }
      final raw = _Raw(res.statusCode, res.headers, body, bytes, ctype);
      if (res.statusCode >= 400) {
        final err = _error(raw);
        if (safe && attempt < _maxRetries && (res.statusCode == 429 || res.statusCode == 503)) {
          await Future<void>.delayed(err.retryAfter ?? const Duration(seconds: 1));
          continue;
        }
        throw err;
      }
      return raw;
    }
  }

  LowcoApiError _error(_Raw raw) {
    final ra = int.tryParse(raw.headers['retry-after'] ?? '');
    final retryAfter = ra == null ? null : Duration(seconds: ra);
    final b = raw.body;
    final e = b is Map<String, dynamic> ? b['error'] : null;
    if (e is Map<String, dynamic>) {
      return LowcoApiError('${e['message'] ?? 'Request failed with status ${raw.status}'}',
          status: raw.status,
          reason: '${e['reason'] ?? ErrorReason.internalError}',
          param: e['param'] as String?,
          details: (e['details'] as List?)?.map((d) => ErrorDetail.fromJson(d as Map<String, dynamic>)).toList(),
          requestId: (e['request_id'] as String?) ?? raw.headers['x-request-id'],
          docUrl: e['doc_url'] as String?,
          retryable: e['retryable'] as bool?,
          retryAfter: retryAfter,
          payload: b);
    }
    final text = utf8.decode(raw.bytes, allowMalformed: true);
    return LowcoApiError(text.isEmpty ? 'Request failed with status ${raw.status}' : text,
        status: raw.status,
        reason: raw.status >= 500 ? ErrorReason.internalError : ErrorReason.invalidParam,
        requestId: raw.headers['x-request-id'],
        retryAfter: retryAfter,
        payload: b ?? text);
  }

  Object? _data(_Raw raw) {
    final b = raw.body;
    if (b is! Map<String, dynamic> || b['status'] != 1) {
      throw LowcoApiError('The API answered without a success envelope', status: raw.status, reason: ErrorReason.internalError, payload: b);
    }
    return b['data'];
  }

  /// A resource call: the envelope's data, decoded.
  Future<T> call<T>(String method, String path,
      {Map<String, dynamic>? query, Object? body, required T Function(Object?) decode, RequestOptions? options}) async {
    final uri = _uri(path, query);
    final raw = await _send(method, uri, options: options, build: body == null
        ? null
        : () async => http.Request(method, uri)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(body));
    return decode(_data(raw));
  }

  /// POST /v1/files and the like: one multipart file.
  Future<T> upload<T>(String path, FileInput file, T Function(Object?) decode, [RequestOptions? options]) async {
    if (file is! _LocalFile) {
      throw LowcoApiError('upload takes a local file (path, bytes or stream)', status: 0, reason: ErrorReason.invalidParam, param: 'file');
    }
    final uri = _uri(path);
    final (name, data) = await file._read();
    final raw = await _send('POST', uri, options: options, build: () async {
      final req = http.MultipartRequest('POST', uri)..files.add(http.MultipartFile.fromBytes('file', data, filename: name));
      if (file.password != null) req.fields['password'] = file.password!;
      return req;
    });
    return decode(_data(raw));
  }

  /// A route answering 307: the Location (a signed link).
  Future<String> redirect(String path, [RequestOptions? options]) async {
    final raw = await _send('GET', _uri(path), follow: false, options: options);
    final loc = raw.headers['location'];
    if (loc == null) throw LowcoApiError('The API answered without a Location', status: raw.status, reason: ErrorReason.internalError);
    return loc;
  }

  /// Downloads a signed link (no API key is sent).
  Future<List<int>> download(String url) async => (await _send('GET', Uri.parse(url), auth: false, accept: '*/*')).bytes;

  /// An operation call: multipart when every file input is local, JSON references when none is,
  /// and an upload of the local ones first when they are mixed.
  Future<Answer<T>> operation<T>(String path, Map<String, dynamic> options, Map<String, FileInput?> named, List<FileInput>? many,
      T Function(Map<String, dynamic>) decode, CallOptions? call) async {
    final refs = <String, FileInput>{};
    named.forEach((k, v) {
      if (v != null) refs[k] = v;
    });
    var files = many;
    final all = [...refs.values, ...?files];
    final local = all.where((f) => f._local).length;
    if (local > 0 && local < all.length) {
      Future<FileInput> up(FileInput f) async {
        if (!f._local) return f;
        final stored = await upload('/v1/files', f, (j) => StoredFile.fromJson(j as Map<String, dynamic>));
        return FileInput.id(stored.fileId!, password: f.password);
      }
      for (final k in refs.keys.toList()) {
        refs[k] = await up(refs[k]!);
      }
      if (files != null) files = [for (final f in files) await up(f)];
    }
    final uri = _uri(path, call?.mode == null ? null : {'mode': call!.mode});
    final multipart = local > 0 && local == all.length;
    final raw = await _send('POST', uri, options: call, accept: call?.accept, retrySafe: false, build: () async {
      if (multipart) {
        final req = http.MultipartRequest('POST', uri);
        final rest = Map<String, dynamic>.of(options);
        for (final e in refs.entries) {
          final (name, data) = await (e.value as _LocalFile)._read();
          req.files.add(http.MultipartFile.fromBytes(e.key, data, filename: name));
          if (e.key == 'file' && e.value.password != null) req.fields['password'] = e.value.password!;
        }
        for (final f in files ?? const <FileInput>[]) {
          final (name, data) = await (f as _LocalFile)._read();
          req.files.add(http.MultipartFile.fromBytes('files[]', data, filename: name));
        }
        final cb = rest.remove('callback_url');
        if (cb != null) req.fields['callback_url'] = '$cb';
        req.fields['options'] = jsonEncode(rest);
        return req;
      }
      final payload = Map<String, dynamic>.of(options);
      for (final e in refs.entries) {
        final ref = (e.value as _RemoteFile)._reference();
        if (e.key == 'file') {
          payload.addAll(ref);
        } else {
          payload[e.key] = ref;
        }
      }
      if (files != null) payload['files'] = [for (final f in files) (f as _RemoteFile)._reference()];
      return http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(payload);
    });
    final common = (requestId: raw.headers['x-request-id'], replayed: raw.headers['idempotent-replayed'] == 'true', credits: raw.headers['x-lowco-credits-used']);
    if (!raw.contentType.contains('json')) {
      return Answer._(raw.status, bytes: raw.bytes, contentType: raw.contentType, requestId: common.requestId, replayed: common.replayed, creditsUsed: common.credits);
    }
    if (raw.status == 202) {
      return Answer._(raw.status, job: Job.fromJson(_data(raw) as Map<String, dynamic>), requestId: common.requestId, replayed: common.replayed, creditsUsed: common.credits);
    }
    return Answer._(raw.status, data: decode(_data(raw) as Map<String, dynamic>), requestId: common.requestId, replayed: common.replayed, creditsUsed: common.credits);
  }

  /// Every item of a list route, following next_cursor.
  Stream<T> paginate<T>(String path, Map<String, dynamic>? query, T Function(Object?) decode, [RequestOptions? options]) async* {
    String? cursor;
    do {
      final page = await call('GET', path, query: {...?query, if (cursor != null) 'cursor': cursor}, decode: (j) => j as Map<String, dynamic>, options: options);
      for (final item in (page['items'] as List)) {
        yield decode(item);
      }
      cursor = page['next_cursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);
  }

  /// Polls a job until it is terminal, honouring Retry-After.
  Future<Job> waitForJob(String jobId, {Duration timeout = const Duration(minutes: 5), Duration maxInterval = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    for (;;) {
      final raw = await _send('GET', _uri('/v1/jobs/${Uri.encodeComponent(jobId)}'));
      final job = Job.fromJson(_data(raw) as Map<String, dynamic>);
      if (_terminal.contains(job.status)) {
        if (job.status == 'succeeded') return job;
        final e = job.error;
        throw LowcoJobError(e?.message ?? 'Job $jobId was ${job.status}', job,
            status: e?.code ?? 409,
            reason: e?.reason ?? ErrorReason.invalidState,
            param: e?.param,
            details: e?.details,
            docUrl: e?.docUrl,
            retryable: e?.retryable,
            requestId: raw.headers['x-request-id']);
      }
      final ra = double.tryParse(raw.headers['retry-after'] ?? '') ?? 2;
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw LowcoTimeoutError(jobId, timeout);
      var pause = Duration(milliseconds: (ra * 1000).round());
      if (pause > maxInterval) pause = maxInterval;
      if (pause > left) pause = left;
      await Future<void>.delayed(pause);
    }
  }

  /// Closes the HTTP client.
  void close() => _http.close();
}
