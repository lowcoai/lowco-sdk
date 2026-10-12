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
  if (status == 402) {
    final quota = parseQuotaExceeded(status, message, text);
    if (quota != null) return quota;
  }
  return LowcodbException(statusCode: status, message: message, code: code, body: text);
}

/// Body code of a 402 from a base's gateway: the plan cap for the metered resource is reached.
const String codeQuotaExceeded = 'QUOTA_EXCEEDED';

/// Thrown for a 402 `QUOTA_EXCEEDED` from the gateway. Carries the quota plane's body
/// so a caller can explain, wait for [periodEnd], or offer the upgrade. It is a
/// [LowcodbException].
class QuotaExceededException extends LowcodbException {
  QuotaExceededException({
    required super.statusCode,
    required super.message,
    super.body,
    required this.meter,
    required this.consumed,
    required this.included,
    this.hardCap,
    this.periodEnd,
    this.appKey,
    this.upgradeAppKey,
    this.upgradePlans = const [],
  }) : super(code: codeQuotaExceeded);

  /// The metered resource, e.g. `vlbrofrujc_employees_create`.
  final String meter;

  /// The period's usage and the plan's allowance.
  final double consumed;
  final double included;

  /// The ceiling that refused the call; null when the plan has none.
  final double? hardCap;

  /// When the usage window resets (RFC 3339), when known.
  final String? periodEnd;

  /// Product whose plan applies, and what would lift the cap.
  final String? appKey;
  final String? upgradeAppKey;
  final List<String> upgradePlans;

  @override
  String toString() => 'QuotaExceededException($statusCode): $message [$meter]';
}

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

/// Reads a 402 body (the plane's `QuotaError`) leniently: the keeper writes it at the
/// top level, an envelope would nest it under `error`. Null when it is not one.
QuotaExceededException? parseQuotaExceeded(int status, String fallbackMessage, String text) {
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (parsed is! Map) return null;
  final nested = parsed['error'];
  final fields = nested is Map && nested.containsKey('code') ? nested : parsed;
  if ('${fields['code'] ?? ''}'.toUpperCase() != codeQuotaExceeded) return null;
  final upgrade = fields['upgrade'];
  final plans = upgrade is Map && upgrade['plans'] is List
      ? (upgrade['plans'] as List).map((p) => '$p').toList()
      : const <String>[];
  final message = fields['message'] is String ? (fields['message'] as String).trim() : '';
  return QuotaExceededException(
    statusCode: status,
    message: message.isNotEmpty ? message : fallbackMessage,
    body: text,
    meter: '${fields['meter'] ?? ''}',
    consumed: _num(fields['consumed']),
    included: _num(fields['included']),
    hardCap: fields['hard_cap'] == null ? null : _num(fields['hard_cap']),
    periodEnd: fields['period_end'] is String ? fields['period_end'] as String : null,
    appKey: fields['app_key'] is String ? fields['app_key'] as String : null,
    upgradeAppKey: upgrade is Map ? (upgrade['app_key'] ?? upgrade['appKey']) as String? : null,
    upgradePlans: plans,
  );
}
