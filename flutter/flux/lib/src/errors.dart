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

/// Reported through `FluxClient.onError` / `FluxClient.errors` (never thrown)
/// when the server rejects the connection's token: it sends a `flux:error`
/// frame whose event is `Unauthorized`, or closes the socket with code 1008.
///
/// The client then reconnects only if a different token is available (from
/// its `tokenProvider` or `FluxClient.setToken`); otherwise it stops until
/// one is supplied or `FluxClient.connect` is called.
class FluxUnauthorizedException extends FluxException {
  const FluxUnauthorizedException([super.message = 'token rejected by the server']);

  @override
  String toString() => 'FluxUnauthorizedException: $message';
}
