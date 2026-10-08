import 'json.dart';
import 'models.dart';

/// Thrown by every document request that fails.
///
/// * Non-2xx response: [status] is the HTTP status and [payload] the decoded
///   JSON error body, or the raw response text when the body is not JSON
///   (`null` when it is empty). [message] is the best message found in the
///   body. For the `{"status": 0, "error": {"message", "code", "details"}}`
///   envelope, an `error.message` that is a platform code (e.g. `AAS-00106`)
///   goes to [code] and `error.details` becomes [message] (the code is the
///   message when there are no details); a plain `error.message` is used
///   as-is. For a `{"message": "..."}` body it is that message. Otherwise it
///   is `Request failed with status <n>`.
/// * 2xx response the method cannot use (a JSON method whose body is not
///   JSON, or a URL method that got no redirect): [status] is the HTTP status
///   and [message] says what was wrong.
/// * Transport failure (network error, aborted or timed-out request):
///   [status] is `0` and [payload] is `null`.
/// * Invalid argument caught before sending (a `.` or `..` path segment):
///   [status] is `0` and [payload] is `null`.
class DocsException implements Exception {
  /// Creates an exception.
  const DocsException({required this.message, required this.status, this.payload, this.code});

  /// Human-readable reason.
  final String message;

  /// HTTP status code, or `0` when no response was received.
  final int status;

  /// Platform error code from `error.message` of the error envelope (e.g.
  /// `AAS-00106`), or `null`.
  final String? code;

  /// Decoded error body (usually the `{ status, error }` envelope or a
  /// `{ message }` object), the raw text of a non-JSON body, or `null`.
  final Object? payload;

  /// The current state of the file when a conditional save
  /// (`UpdateFileRequest.ifMatch` / `ifNoneMatch`) failed with `412`, read
  /// from the `data` field of the error body; `null` otherwise.
  PreconditionState? get precondition {
    final body = payload;
    if (status != 412 || body is! Map) return null;
    return readObject(body['data'], PreconditionState.fromJson);
  }

  @override
  String toString() => 'DocsException($status): $message';
}

/// A platform error code such as `AAS-00106`.
final _platformCode = RegExp(r'^[A-Z][A-Z0-9]*-\d+$');

/// Extracts the best message and the platform code from one of the
/// service's two error shapes:
/// `{"status": 0, "error": {"message", "code", "details"}}` and
/// `{"message": "..."}`.
({String? message, String? code}) errorInfoOf(Object? payload) {
  if (payload is! Map) return (message: null, code: null);
  final error = payload['error'];
  if (error is Map) {
    final message = _text(error['message']);
    final details = _text(error['details']);
    final code = message != null && _platformCode.hasMatch(message) ? message : null;
    if (code != null && details != null) return (message: details, code: code);
    if (message != null) return (message: message, code: code);
    if (details != null) return (message: details, code: null);
  } else if (_text(error) case final String text) {
    return (message: text, code: null);
  }
  return (message: _text(payload['message']), code: null);
}

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
