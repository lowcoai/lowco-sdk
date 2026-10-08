import 'dart:math';

/// The fixed flux WebSocket endpoint every client connects to.
const wsUrl = 'wss://api.lowco.ai/v1/ws';

/// Builds the connection URL: [wsUrl] with `token`, `orgId`, `cli` and then
/// [queryParams] as query parameters. A key in [queryParams] that repeats one
/// of the first three replaces its value in place.
String buildWebSocketUrl(
  String token,
  String orgId,
  String clientId, [
  Map<String, String>? queryParams,
]) {
  final params = <String, String>{
    'token': token,
    'orgId': orgId,
    'cli': clientId,
    ...?queryParams,
  };
  return Uri.parse(wsUrl).replace(queryParameters: params).toString();
}

/// A random RFC 4122 version 4 UUID, used as the default client id.
String generateClientId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A time-prefixed random id for the `request_id` of an outgoing frame.
String generateRequestId() {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final suffix = String.fromCharCodes(
    List.generate(11, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))),
  );
  return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + suffix;
}

/// Trims a topic or event name; null becomes empty.
String normalizeTopic(String? value) => (value ?? '').trim();

final Random _random = _createRandom();

Random _createRandom() {
  try {
    return Random.secure();
  } on UnsupportedError {
    return Random();
  }
}
