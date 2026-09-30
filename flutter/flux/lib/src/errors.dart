/// Thrown when the flux client cannot operate: invalid input (a blank token,
/// an empty topic) or `FluxClient.sendMessage` while the socket is not open.
///
/// Transient socket problems (parse failures, a pong out of sync, a dropped
/// connection) are not thrown; they are reported through
/// `FluxClient.onError` / `FluxClient.errors` instead.
class FluxException implements Exception {
  const FluxException(this.message);

  final String message;

  @override
  String toString() => 'FluxException: $message';
}
