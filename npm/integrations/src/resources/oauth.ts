import type { HttpClient } from "../client.js";
import type {
  AuthToken,
  CallbackRequest,
  ConnectionCreateRequest,
  OAuthCallbackResult,
  OAuthLoginUrl,
  RefreshExpiringTokensResult
} from "../types.js";

export class OAuthResource {
  constructor(private readonly http: HttpClient) {}

  login(applicationId: string, payload: ConnectionCreateRequest): Promise<OAuthLoginUrl> {
    return this.http.request("POST", `/v1/integrations/oauth/${applicationId}/login`, payload);
  }

  callback(payload: CallbackRequest): Promise<OAuthCallbackResult> {
    return this.http.request("POST", "/v1/integrations/oauth/callback", payload);
  }

  getTokenByCredentialId(credentialId: string): Promise<AuthToken> {
    return this.http.request("GET", `/v1/integrations/connections/${credentialId}/token`);
  }

  refreshTokenByCredentialId(credentialId: string): Promise<AuthToken> {
    return this.http.request("POST", `/v1/integrations/connections/${credentialId}/token/refresh`);
  }

  refreshExpiringTokens(): Promise<RefreshExpiringTokensResult> {
    return this.http.request("POST", "/v1/integrations/oauth/tokens/refresh-expiring");
  }
}
