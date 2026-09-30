/// Thrown by every integrations request that fails (the TS SDK's `IntegrationsError`).
///
/// * Non-2xx response: [message] is `Request failed with status <n>`,
///   [status] the HTTP status and [payload] the decoded JSON error body — or
///   the raw response text when the body is not JSON, `null` when it is empty.
/// * 2xx response whose body is not JSON: [message] starts with
///   `Invalid JSON response`, [status] is the HTTP status and [payload] the
///   raw text.
/// * Transport failure (network error, aborted or timed-out request):
///   [status] is `0` and [payload] is `null`.
class IntegrationsException implements Exception {
  const IntegrationsException({required this.message, required this.status, this.payload});

  final String message;

  /// HTTP status code, or `0` when no response was received.
  final int status;

  /// Decoded error body (usually the `{ success, error, message }` envelope).
  final Object? payload;

  @override
  String toString() => 'IntegrationsException($status): $message';
}
