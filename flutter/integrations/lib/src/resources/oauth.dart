import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// OAuth 2 connection flow and token management.
class OAuthResource {
  OAuthResource(this._http);

  final IntegrationsHttpClient _http;

  /// Starts the OAuth flow; redirect the user to the returned `url`.
  Future<OAuthLoginUrl> login(
          String applicationId, ConnectionCreateRequest payload) async =>
      decodeOne(
          await _http.request('POST', '/v1/integrations/oauth/${seg(applicationId)}/login',
              body: payload),
          OAuthLoginUrl.fromJson);

  /// Completes the flow with the `state` and `code` of the redirect.
  Future<OAuthCallbackResult> callback(CallbackRequest payload) async => decodeOne(
      await _http.request('POST', '/v1/integrations/oauth/callback', body: payload),
      OAuthCallbackResult.fromJson);

  Future<AuthToken> getTokenByCredentialId(String credentialId) async => decodeOne(
      await _http.request('GET', '/v1/integrations/connections/${seg(credentialId)}/token'),
      AuthToken.fromJson);

  /// `POST` with no body.
  Future<AuthToken> refreshTokenByCredentialId(String credentialId) async => decodeOne(
      await _http.request(
          'POST', '/v1/integrations/connections/${seg(credentialId)}/token/refresh'),
      AuthToken.fromJson);

  /// `POST` with no body.
  Future<RefreshExpiringTokensResult> refreshExpiringTokens() async => decodeOne(
      await _http.request('POST', '/v1/integrations/oauth/tokens/refresh-expiring'),
      RefreshExpiringTokensResult.fromJson);
}
