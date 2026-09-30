from __future__ import annotations

import httpx
from typing_extensions import Self

from ._base import (
    CODE_EXCHANGE_FAILED,
    DEFAULT_SCOPE,
    DEFAULT_TIMEOUT,
    FORM_HEADERS,
    REFRESH_FAILED,
    SESSION_EXPIRED,
    BaseAuthClient,
    code_from_callback,
    refresh_input,
    require_tokens,
)
from ._errors import LowcoAuthError
from ._tokens import is_access_token_valid, tokens_from_response
from .types import AuthorizationRequest, TokenSet

__all__ = ["AsyncLowcoAuthClient", "LowcoAuthClient"]


class LowcoAuthClient(BaseAuthClient):
    """OAuth 2.0 Authorization Code + PKCE helper for the lowco identity service.

    The server-side / framework-agnostic counterpart of the React
    ``LowcoAuthProvider``, with the same wire behaviour. It stores nothing:
    your app keeps the :class:`AuthorizationRequest` between the redirect and
    the callback, and the :class:`TokenSet` afterwards (session, cookie,
    database...).

    Typical flow::

        request = auth.create_authorization_request()   # no I/O
        session["lowco_auth"] = request.to_dict()
        redirect(request.url)
        ...
        # on the redirect_uri route
        request = AuthorizationRequest.from_dict(session.pop("lowco_auth"))
        tokens = auth.handle_redirect_callback(current_url, request)
        ...
        tokens = auth.get_valid_tokens(tokens)            # refreshes when needed

    Use it as a context manager, or call :meth:`close`, to release the
    underlying connection pool.
    """

    def __init__(
        self,
        domain: str,
        login_page_url: str,
        tenant_id: str,
        client_id: str,
        *,
        redirect_uri: str | None = None,
        scope: str = DEFAULT_SCOPE,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            domain: Auth server base URL, e.g. ``"https://api.lowco.ai/v1/identity"``.
                The token endpoint is ``{domain}/tenants/{tenant_id}/oauth/token``.
            login_page_url: Hosted login page the user is redirected to.
            tenant_id: Tenant identifier.
            client_id: OAuth client identifier.
            redirect_uri: Default callback URL registered for the client. Can be
                given per login instead.
            scope: Default scope (``"openid profile email offline_access"``).
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
        """
        super().__init__(
            domain,
            login_page_url,
            tenant_id,
            client_id,
            redirect_uri=redirect_uri,
            scope=scope,
        )
        self._timeout = timeout
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.Client()

    def close(self) -> None:
        if self._owns_http:
            self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def exchange_code(self, code: str, request: AuthorizationRequest) -> TokenSet:
        """Exchanges an authorization code for tokens (``grant_type=authorization_code``)
        using the request's ``code_verifier`` and ``redirect_uri``.

        Raises :class:`LowcoAuthError` (``"Authorization code exchange failed."``)
        on a non-2xx response.
        """
        resp = self._post_token(self._code_form(code, request))
        return tokens_from_response(
            resp.status_code, resp.text, failure_message=CODE_EXCHANGE_FAILED
        )

    def handle_redirect_callback(
        self, callback_url: str, request: AuthorizationRequest
    ) -> TokenSet:
        """Finishes a login from the URL the user was redirected back to.

        ``callback_url`` may be the full URL, ``/path?query`` or the query
        string. Raises :class:`LowcoAuthError` when the callback carries an
        OAuth ``error``, lacks ``code`` / ``state``, or its ``state`` does not
        match ``request.state``; otherwise exchanges the code.
        """
        code = code_from_callback(callback_url, request)
        return self.exchange_code(code, request)

    def refresh_tokens(self, tokens_or_refresh_token: TokenSet | str) -> TokenSet:
        """Gets a fresh token set with ``grant_type=refresh_token``.

        Given a :class:`TokenSet`, the result is merged over it (like
        ``{...current, ...refreshed}``), so a refresh token the server does not
        rotate is kept. Given a bare refresh token, only the response is
        returned. Raises :class:`LowcoAuthError` (``"Refresh token exchange
        failed."``) on a non-2xx response.
        """
        previous, refresh_token = refresh_input(tokens_or_refresh_token)
        resp = self._post_token(self._refresh_form(refresh_token))
        return tokens_from_response(
            resp.status_code, resp.text, failure_message=REFRESH_FAILED, previous=previous
        )

    def get_valid_tokens(self, tokens: TokenSet | None) -> TokenSet:
        """Returns ``tokens`` unchanged while the access token is valid (with a
        60 s skew), otherwise refreshes them.

        Raises :class:`LowcoAuthError`: ``"Not authenticated."`` without an
        access token, ``"Session expired."`` when it expired and there is no
        refresh token, or the refresh error. Compare the result with the input
        (``is not``) to know whether to persist it.
        """
        current = require_tokens(tokens)
        if is_access_token_valid(current):
            return current
        if not current.get("refresh_token"):
            raise LowcoAuthError(SESSION_EXPIRED)
        return self.refresh_tokens(current)

    def _post_token(self, form: bytes) -> httpx.Response:
        return self._http.post(
            self._token_url, content=form, headers=FORM_HEADERS, timeout=self._timeout
        )


class AsyncLowcoAuthClient(BaseAuthClient):
    """Asyncio version of :class:`LowcoAuthClient` (same surface; the network
    methods are coroutines, :meth:`create_authorization_request` stays sync).

    Use it as an async context manager, or call :meth:`aclose`, to release the
    underlying connection pool.
    """

    def __init__(
        self,
        domain: str,
        login_page_url: str,
        tenant_id: str,
        client_id: str,
        *,
        redirect_uri: str | None = None,
        scope: str = DEFAULT_SCOPE,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            domain: Auth server base URL, e.g. ``"https://api.lowco.ai/v1/identity"``.
                The token endpoint is ``{domain}/tenants/{tenant_id}/oauth/token``.
            login_page_url: Hosted login page the user is redirected to.
            tenant_id: Tenant identifier.
            client_id: OAuth client identifier.
            redirect_uri: Default callback URL registered for the client. Can be
                given per login instead.
            scope: Default scope (``"openid profile email offline_access"``).
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It is
                not closed by :meth:`aclose`.
        """
        super().__init__(
            domain,
            login_page_url,
            tenant_id,
            client_id,
            redirect_uri=redirect_uri,
            scope=scope,
        )
        self._timeout = timeout
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.AsyncClient()

    async def aclose(self) -> None:
        if self._owns_http:
            await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()

    async def exchange_code(self, code: str, request: AuthorizationRequest) -> TokenSet:
        """See :meth:`LowcoAuthClient.exchange_code`."""
        resp = await self._post_token(self._code_form(code, request))
        return tokens_from_response(
            resp.status_code, resp.text, failure_message=CODE_EXCHANGE_FAILED
        )

    async def handle_redirect_callback(
        self, callback_url: str, request: AuthorizationRequest
    ) -> TokenSet:
        """See :meth:`LowcoAuthClient.handle_redirect_callback`."""
        code = code_from_callback(callback_url, request)
        return await self.exchange_code(code, request)

    async def refresh_tokens(self, tokens_or_refresh_token: TokenSet | str) -> TokenSet:
        """See :meth:`LowcoAuthClient.refresh_tokens`."""
        previous, refresh_token = refresh_input(tokens_or_refresh_token)
        resp = await self._post_token(self._refresh_form(refresh_token))
        return tokens_from_response(
            resp.status_code, resp.text, failure_message=REFRESH_FAILED, previous=previous
        )

    async def get_valid_tokens(self, tokens: TokenSet | None) -> TokenSet:
        """See :meth:`LowcoAuthClient.get_valid_tokens`."""
        current = require_tokens(tokens)
        if is_access_token_valid(current):
            return current
        if not current.get("refresh_token"):
            raise LowcoAuthError(SESSION_EXPIRED)
        return await self.refresh_tokens(current)

    async def _post_token(self, form: bytes) -> httpx.Response:
        return await self._http.post(
            self._token_url, content=form, headers=FORM_HEADERS, timeout=self._timeout
        )
