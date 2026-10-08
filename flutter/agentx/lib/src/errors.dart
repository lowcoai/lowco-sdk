import 'dart:convert';

import 'json.dart';

/// Thrown for HTTP-level non-2xx responses from any agentx service.
///
/// [statusCode] is always set. [message] and [code] are populated when the
/// service returns its standard JSON error envelope; otherwise [message]
/// falls back to the raw response text and [code] is null.
///
/// JSON-RPC level errors from the executor are surfaced in
/// `JSONRPCResponse.error`, not thrown.
class AgentxException implements Exception {
  AgentxException({
    required this.statusCode,
    required String message,
    this.code,
    this.body = '',
  }) : message = message.isEmpty ? 'agentx: status=$statusCode' : message;

  final int statusCode;
  final String message;

  /// `error.code` from the envelope (a non-string code is stringified).
  final String? code;

  /// The raw response body, for debugging.
  final String body;

  @override
  String toString() => 'AgentxException($statusCode): $message';
}

/// Builds the exception for a non-2xx response the same way the TypeScript
/// SDK's `buildHttpError` does: `error.message` (with `error.code`) when the
/// envelope carries a non-blank one, else a top-level `message`, else the
/// trimmed raw text.
AgentxException buildHttpException(int status, String text) {
  var message = text.trim();
  String? code;
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    parsed = null;
  }
  if (parsed is Map) {
    final envelope = parsed['error'];
    final envelopeMessage = envelope is Map ? envelope['message'] : null;
    final topMessage = parsed['message'];
    if (envelopeMessage is String && envelopeMessage.trim().isNotEmpty) {
      message = envelopeMessage;
      code = readString((envelope as Map)['code']);
    } else if (topMessage is String && topMessage.isNotEmpty) {
      message = topMessage;
    }
  }
  return AgentxException(statusCode: status, message: message, code: code, body: text);
}
