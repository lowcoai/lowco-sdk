package integrations

import "context"

type OAuthResource struct {
	http *httpClient
}

// Login starts an authorization-code flow for an application and returns the
// provider URL the user should be redirected to. Caller persists the returned
// AuthRequest server-side.
func (r *OAuthResource) Login(ctx context.Context, applicationID string, payload ConnectionCreateRequest) (OAuthLoginURL, error) {
	var result OAuthLoginURL
	err := r.http.Request(ctx, "POST", "/v1/integrations/oauth/"+applicationID+"/login", payload, nil, &result)
	return result, err
}

// Callback finishes the authorization-code exchange, creating the Connection
// and storing tokens.
func (r *OAuthResource) Callback(ctx context.Context, payload CallbackRequest) (OAuthCallbackResult, error) {
	var result OAuthCallbackResult
	err := r.http.Request(ctx, "POST", "/v1/integrations/oauth/callback", payload, nil, &result)
	return result, err
}

// GetTokenByCredentialID returns stored OAuth token metadata for a connection.
func (r *OAuthResource) GetTokenByCredentialID(ctx context.Context, credentialID string) (AuthToken, error) {
	var result AuthToken
	err := r.http.Request(ctx, "GET", "/v1/integrations/connections/"+credentialID+"/token", nil, nil, &result)
	return result, err
}

// RefreshTokenByCredentialID forces a refresh of the stored OAuth token for a
// connection.
func (r *OAuthResource) RefreshTokenByCredentialID(ctx context.Context, credentialID string) (AuthToken, error) {
	var result AuthToken
	err := r.http.Request(ctx, "POST", "/v1/integrations/connections/"+credentialID+"/token/refresh", nil, nil, &result)
	return result, err
}

// RefreshExpiringTokens refreshes all tokens for the caller's org expiring
// within the next 12 hours.
func (r *OAuthResource) RefreshExpiringTokens(ctx context.Context) (RefreshExpiringTokensResult, error) {
	var result RefreshExpiringTokensResult
	err := r.http.Request(ctx, "POST", "/v1/integrations/oauth/tokens/refresh-expiring", nil, nil, &result)
	return result, err
}
