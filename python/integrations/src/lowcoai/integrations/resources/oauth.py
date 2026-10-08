"""OAuth login / callback and connection tokens (mirrors ``resources/oauth.ts``)."""

from __future__ import annotations

from .._base import seg
from .._http import AsyncHttpClient, HttpClient
from ..types import (
    AuthToken,
    CallbackRequest,
    ConnectionCreateRequest,
    OAuthCallbackResult,
    OAuthLoginUrl,
    RefreshExpiringTokensResult,
)

__all__ = ["AsyncOAuthResource", "OAuthResource"]


class OAuthResource:
    """OAuth2 connection flow and access tokens of connections."""

    def __init__(self, http: HttpClient) -> None:
        self._http = http

    def login(self, application_id: str, payload: ConnectionCreateRequest) -> OAuthLoginUrl:
        """Returns the provider URL to redirect the user to."""
        return self._http.request(
            "POST", f"/v1/integrations/oauth/{seg(application_id)}/login", payload
        )

    def callback(self, payload: CallbackRequest) -> OAuthCallbackResult:
        """Completes the flow with the ``state`` / ``code`` from the redirect."""
        return self._http.request("POST", "/v1/integrations/oauth/callback", payload)

    def get_token_by_credential_id(self, credential_id: str) -> AuthToken:
        return self._http.request("GET", f"/v1/integrations/connections/{seg(credential_id)}/token")

    def refresh_token_by_credential_id(self, credential_id: str) -> AuthToken:
        return self._http.request(
            "POST", f"/v1/integrations/connections/{seg(credential_id)}/token/refresh"
        )

    def refresh_expiring_tokens(self) -> RefreshExpiringTokensResult:
        return self._http.request("POST", "/v1/integrations/oauth/tokens/refresh-expiring")


class AsyncOAuthResource:
    """Asyncio variant of :class:`OAuthResource` (same methods, as coroutines)."""

    def __init__(self, http: AsyncHttpClient) -> None:
        self._http = http

    async def login(self, application_id: str, payload: ConnectionCreateRequest) -> OAuthLoginUrl:
        """Returns the provider URL to redirect the user to."""
        return await self._http.request(
            "POST", f"/v1/integrations/oauth/{seg(application_id)}/login", payload
        )

    async def callback(self, payload: CallbackRequest) -> OAuthCallbackResult:
        """Completes the flow with the ``state`` / ``code`` from the redirect."""
        return await self._http.request("POST", "/v1/integrations/oauth/callback", payload)

    async def get_token_by_credential_id(self, credential_id: str) -> AuthToken:
        return await self._http.request(
            "GET", f"/v1/integrations/connections/{seg(credential_id)}/token"
        )

    async def refresh_token_by_credential_id(self, credential_id: str) -> AuthToken:
        return await self._http.request(
            "POST", f"/v1/integrations/connections/{seg(credential_id)}/token/refresh"
        )

    async def refresh_expiring_tokens(self) -> RefreshExpiringTokensResult:
        return await self._http.request("POST", "/v1/integrations/oauth/tokens/refresh-expiring")
