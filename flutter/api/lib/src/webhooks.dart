import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The signature header on every webhook delivery.
const signatureHeader = 'Lowco-Signature';

/// Thrown by [constructEvent] when a delivery does not verify.
class LowcoSignatureError implements Exception {
  @override
  String toString() => 'LowcoSignatureError: the Lowco-Signature does not match this body and secret, or its timestamp is too old';
}

/// Verifies `Lowco-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>`.
///
/// Pass the raw request body (before JSON parsing) and the endpoint's `whsec_…`
/// secret as-is. During a secret rotation the header may carry several v1
/// values; any one matching verifies.
bool verifySignature(String? header, List<int> rawBody, String secret,
    {Duration tolerance = const Duration(minutes: 5), DateTime? now}) {
  if (header == null || header.isEmpty) return false;
  var t = 0;
  final sigs = <String>[];
  for (final piece in header.split(',')) {
    final i = piece.indexOf('=');
    if (i < 0) continue;
    final k = piece.substring(0, i).trim();
    final v = piece.substring(i + 1).trim();
    if (k == 't') t = int.tryParse(v) ?? 0;
    if (k == 'v1' && v.isNotEmpty) sigs.add(v);
  }
  if (t == 0 || sigs.isEmpty) return false;
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if ((current - t).abs() > tolerance.inSeconds) return false;
  final mac = Hmac(sha256, utf8.encode(secret)).convert([...utf8.encode('$t.'), ...rawBody]).toString();
  return sigs.any((s) => _constantTimeEquals(s, mac));
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Verifies a delivery and returns its event (id, type, created_at, environment, data).
Map<String, dynamic> constructEvent(List<int> rawBody, String? header, String secret,
    {Duration tolerance = const Duration(minutes: 5), DateTime? now}) {
  if (!verifySignature(header, rawBody, secret, tolerance: tolerance, now: now)) {
    throw LowcoSignatureError();
  }
  return jsonDecode(utf8.decode(rawBody)) as Map<String, dynamic>;
}
