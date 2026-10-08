import 'dart:convert';

/// Thrown for every non-2xx response from the lowcodb manager.
///
/// [statusCode] is always set. [message] and [code] are populated when the
/// manager returns its standard JSON error envelope; otherwise [message]
/// falls back to the raw response text and [code] is null. The manager sends
/// the numeric HTTP status in `error.code`, so [code] may be an [int].
class LowcodbException implements Exception {
  LowcodbException({
    required this.statusCode,
    required String message,
    this.code,
    this.body = '',
  }) : message = message.isEmpty ? 'lowcodb: status=$statusCode' : message;

  final int statusCode;
  final String message;

  /// A [String] or an [int] (the manager puts the HTTP status here).
  final Object? code;

  /// The raw response body, for debugging.
  final String body;

  @override
  String toString() => 'LowcodbException($statusCode): $message';
}

/// The manager's error envelope puts the *opaque platform code* in
/// `error.message` ("AAS-00105" and friends) and the **real** text in
/// `error.details`. Reading `message` alone would surface every DB-function
/// failure as a bare "AAS-00105" with the cause discarded.
final _opaquePlatformCode = RegExp(r'^AAS-\d+$');

LowcodbException buildHttpException(int status, String text) {
  var message = text.trim();
  Object? code;
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    parsed = null;
  }
  if (parsed is Map) {
    final envelope = parsed['error'];
    final envelopeMessage = envelope is Map && envelope['message'] is String
        ? (envelope['message'] as String).trim()
        : '';
    if (envelope is Map && envelopeMessage.isNotEmpty) {
      message = envelopeMessage;
      code = envelope['code'];
      // Prefer the detail text whenever `message` is nothing but the platform
      // code. `code` is left alone (the manager sends the numeric HTTP status
      // there) and the platform code stays recoverable from `body`.
      final details = envelope['details'];
      final detailText = details is String ? details.trim() : '';
      if (detailText.isNotEmpty && _opaquePlatformCode.hasMatch(envelopeMessage)) {
        message = detailText;
      }
    } else if (parsed['message'] is String && (parsed['message'] as String).isNotEmpty) {
      message = parsed['message'] as String;
    }
  }
  return LowcodbException(statusCode: status, message: message, code: code, body: text);
}
