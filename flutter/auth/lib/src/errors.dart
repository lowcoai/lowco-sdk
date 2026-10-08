/// Every failure surfaced by [LowcoAuth]: an OAuth error returned to the
/// redirect URI, a state mismatch, a rejected token request, an expired
/// session (`'Session expired.'`) or a missing one (`'Not authenticated.'`).
class LowcoAuthException implements Exception {
  const LowcoAuthException(this.message, {this.code, this.statusCode, this.cause});

  /// Human-readable description (the TS SDK's `Error.message`).
  final String message;

  /// OAuth error code when known: the `error` parameter of the callback
  /// (`access_denied`, ...), the token endpoint's `error` field
  /// (`invalid_grant`, ...), or `invalid_state` for a state mismatch.
  final String? code;

  /// HTTP status of a failed token request.
  final int? statusCode;

  /// The underlying error (network failure, platform exception, ...), if any.
  final Object? cause;

  @override
  String toString() {
    final details = [
      if (code != null) 'code: $code',
      if (statusCode != null) 'status: $statusCode',
      if (cause != null) 'cause: $cause',
    ];
    return 'LowcoAuthException: $message${details.isEmpty ? '' : ' (${details.join(', ')})'}';
  }
}
