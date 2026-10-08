import 'dart:convert';

import 'json.dart';

/// How long before expiry an access token stops counting as valid and is
/// proactively refreshed (the TS SDK's `TOKEN_REFRESH_SKEW_MS`).
const Duration tokenRefreshSkew = Duration(seconds: 60);

/// The persisted token set. [toJson] produces exactly the JSON the React SDK
/// stores under `lowco:tokens:<tenantId>:<clientId>`.
class TokenSet {
  const TokenSet({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    required this.expiresAt,
    this.scope,
  });

  factory TokenSet.fromJson(Map<String, dynamic> json) => TokenSet(
        accessToken: readString(json['access_token']) ?? '',
        refreshToken: _nonEmpty(readString(json['refresh_token'])),
        idToken: _nonEmpty(readString(json['id_token'])),
        expiresAt: readInt(json['expires_at']) ?? 0,
        scope: _nonEmpty(readString(json['scope'])),
      );

  /// `access_token`.
  final String accessToken;

  /// `refresh_token` (present when the `offline_access` scope was granted).
  final String? refreshToken;

  /// `id_token`.
  final String? idToken;

  /// `expires_at`: access-token expiry in epoch **milliseconds**.
  final int expiresAt;

  /// `scope`.
  final String? scope;

  /// [expiresAt] as a UTC [DateTime].
  DateTime get expiresAtTime => DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true);

  /// True while the access token is still valid for at least [skew].
  bool isAccessTokenValid({DateTime? now, Duration skew = tokenRefreshSkew}) =>
      expiresAt > (now ?? DateTime.now()).millisecondsSinceEpoch + skew.inMilliseconds;

  /// True when the session is usable: a valid access token, or a refresh
  /// token to recover one.
  bool canRecoverSession({DateTime? now}) =>
      accessToken.isNotEmpty && (isAccessTokenValid(now: now) || refreshToken != null);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        if (idToken != null) 'id_token': idToken,
        'expires_at': expiresAt,
        if (scope != null) 'scope': scope,
      };

  @override
  String toString() =>
      'TokenSet(expiresAt: $expiresAtTime, scope: $scope, refreshToken: ${refreshToken != null})';
}

/// The signed-in user, decoded from the `id_token` (or, without one, the
/// `access_token`) JWT payload.
///
/// The signature is **not** verified: use the profile for display only and
/// let your API validate the access token.
class UserProfile {
  const UserProfile({this.sub, this.email, this.name, this.picture, this.claims = const {}});

  /// Builds a profile from a decoded JWT payload.
  factory UserProfile.fromClaims(Map<String, dynamic> claims) => UserProfile(
        sub: claims['sub'] is String ? claims['sub'] as String : null,
        email: claims['email'] is String ? claims['email'] as String : null,
        name: claims['name'] is String ? claims['name'] as String : null,
        picture: claims['picture'] is String ? claims['picture'] as String : null,
        claims: Map.unmodifiable(claims),
      );

  /// Decodes the user from [tokens]; `null` when the JWT cannot be decoded.
  static UserProfile? fromTokens(TokenSet tokens) {
    final payload = decodeJwtPayload(tokens.idToken ?? tokens.accessToken);
    return payload == null ? null : UserProfile.fromClaims(payload);
  }

  final String? sub;
  final String? email;
  final String? name;
  final String? picture;

  /// Every claim of the JWT payload.
  final Map<String, dynamic> claims;

  /// A raw claim, e.g. `user['tenant_id']`.
  Object? operator [](String claim) => claims[claim];

  Map<String, dynamic> toJson() => {
        ...claims,
        if (sub != null) 'sub': sub,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (picture != null) 'picture': picture,
      };

  @override
  String toString() => 'UserProfile(sub: $sub, email: $email, name: $name)';
}

/// Decodes the payload (second segment) of a JWT **without verifying its
/// signature**. Returns `null` for anything that is not a JWT with a JSON
/// object payload.
Map<String, dynamic>? decodeJwtPayload(String? jwt) {
  if (jwt == null) return null;
  final segments = jwt.split('.');
  if (segments.length < 2 || segments[1].isEmpty) return null;
  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
    return readMap(jsonDecode(json));
  } on FormatException {
    return null;
  }
}

String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;
