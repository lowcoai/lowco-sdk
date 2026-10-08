import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final Random _random = Random.secure();

/// Base64url without padding (RFC 7636 appendix A).
String base64UrlNoPadding(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// [byteLength] cryptographically secure random bytes, base64url-encoded
/// (24 bytes for `state` / `nonce`, 48 for the PKCE verifier, as in the TS SDK).
String randomUrlSafeString(int byteLength) =>
    base64UrlNoPadding(List<int>.generate(byteLength, (_) => _random.nextInt(256)));

/// The S256 PKCE code challenge for [verifier].
String pkceChallenge(String verifier) =>
    base64UrlNoPadding(sha256.convert(ascii.encode(verifier)).bytes);
