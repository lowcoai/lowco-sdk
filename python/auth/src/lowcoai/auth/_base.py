"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from collections.abc import Mapping
from typing import Any
from urllib.parse import parse_qsl, quote, quote_plus, urlsplit, urlunsplit

from ._errors import LowcoAuthError
from .types import AuthorizationRequest, TokenSet

DEFAULT_SCOPE = "openid profile email offline_access"
DEFAULT_TIMEOUT = 30.0
CODE_EXCHANGE_FAILED = "Authorization code exchange failed."
REFRESH_FAILED = "Refresh token exchange failed."
SESSION_EXPIRED = "Session expired."

FORM_HEADERS = {"Content-Type": "application/x-www-form-urlencoded"}


class BaseAuthClient:
    """Holds configuration and builds requests / URLs for both clients.

    The client keeps no per-user state, so one instance can serve every user
    of a server app.
    """

    def __init__(
        self,
        domain: str,
        login_page_url: str,
        tenant_id: str,
        client_id: str,
        *,
        redirect_uri: str | None,
        scope: str,
    ) -> None:
        for name, value in (
            ("domain", domain),
            ("login_page_url", login_page_url),
            ("tenant_id", tenant_id),
            ("client_id", client_id),
        ):
            if not value or not value.strip():
                raise ValueError(f"LowcoAuthClient: {name} is required")
        self._domain = domain.rstrip("/")
        self._login_page_url = login_page_url
        self._tenant_id = tenant_id
        self._client_id = client_id
        self._redirect_uri = redirect_uri
        self._scope = scope or DEFAULT_SCOPE
        self._token_url = f"{self._domain}/tenants/{quote(tenant_id, safe='')}/oauth/token"

    @property
    def token_endpoint(self) -> str:
        """``{domain}/tenants/{tenant_id}/oauth/token``."""
        return self._token_url

    def create_authorization_request(
        self,
        *,
        redirect_uri: str | None = None,
        scope: str | None = None,
        app_state: Mapping[str, Any] | None = None,
    ) -> AuthorizationRequest:
        """Starts a login: generates ``state``, ``nonce`` and the PKCE pair and
        builds the login page URL.

        Redirect the user to ``request.url`` and keep the returned request
        (e.g. ``session["lowco_auth"] = request.to_dict()``) until the
        callback. No network I/O.

        Args:
            redirect_uri: Overrides the client's ``redirect_uri`` for this login.
                One of the two is required.
            scope: Overrides the client's scope for this login.
            app_state: Anything to get back after login (e.g. ``{"returnTo": "/billing"}``).
                It is stored in the request only, never sent to the server.
        """
        resolved_redirect = redirect_uri or self._redirect_uri
        if not resolved_redirect:
            raise ValueError(
                "redirect_uri is required: pass it to the client or to create_authorization_request"
            )
        resolved_scope = scope or self._scope
        state = random_string(24)
        nonce = random_string(24)
        code_verifier = random_string(48)
        url = _set_query_params(
            self._login_page_url,
            [
                ("tenant_id", self._tenant_id),
                ("client_id", self._client_id),
                ("redirect_uri", resolved_redirect),
                ("response_type", "code"),
                ("scope", resolved_scope),
                ("state", state),
                ("nonce", nonce),
                ("code_challenge", pkce_challenge(code_verifier)),
                ("code_challenge_method", "S256"),
            ],
        )
        return AuthorizationRequest(
            url=url,
            state=state,
            nonce=nonce,
            code_verifier=code_verifier,
            redirect_uri=resolved_redirect,
            scope=resolved_scope,
            app_state=dict(app_state) if app_state is not None else None,
        )

    # --- request building -------------------------------------------------

    def _code_form(self, code: str, request: AuthorizationRequest) -> bytes:
        if not code:
            raise ValueError("code is required")
        return _form(
            [
                ("grant_type", "authorization_code"),
                ("tenant_id", self._tenant_id),
                ("client_id", self._client_id),
                ("code", code),
                ("code_verifier", request.code_verifier),
                ("redirect_uri", request.redirect_uri),
            ]
        )

    def _refresh_form(self, refresh_token: str) -> bytes:
        return _form(
            [
                ("grant_type", "refresh_token"),
                ("tenant_id", self._tenant_id),
                ("client_id", self._client_id),
                ("refresh_token", refresh_token),
            ]
        )


def code_from_callback(callback_url: str, request: AuthorizationRequest) -> str:
    """Validates the redirect callback and returns the authorization code."""
    params = _query_params(callback_url)
    error = params.get("error")
    if error:
        description = params.get("error_description")
        raise LowcoAuthError(description or f"Authorization failed ({error}).", code=error)
    code = params.get("code")
    state = params.get("state")
    if not code or not state:
        raise LowcoAuthError("Missing code or state in the OAuth callback URL.")
    if not hmac.compare_digest(state.encode("utf-8"), request.state.encode("utf-8")):
        raise LowcoAuthError("OAuth state mismatch.")
    return code


def refresh_input(tokens_or_refresh_token: TokenSet | str) -> tuple[TokenSet | None, str]:
    """Splits the ``refresh_tokens`` argument into (previous token set, refresh token)."""
    if isinstance(tokens_or_refresh_token, str):
        if not tokens_or_refresh_token.strip():
            raise ValueError("refresh_token is required")
        return None, tokens_or_refresh_token
    refresh_token = tokens_or_refresh_token.get("refresh_token")
    if not refresh_token:
        raise LowcoAuthError("No refresh token available.")
    return tokens_or_refresh_token, refresh_token


def require_tokens(tokens: TokenSet | None) -> TokenSet:
    """``get_valid_tokens`` pre-check: raises ``"Not authenticated."`` without an access token."""
    if not tokens or not tokens.get("access_token"):
        raise LowcoAuthError("Not authenticated.")
    return tokens


def random_string(size: int) -> str:
    """base64url (no padding) of ``size`` cryptographically random bytes."""
    return b64url(secrets.token_bytes(size))


def pkce_challenge(verifier: str) -> str:
    """S256 PKCE code challenge: ``base64url(sha256(verifier))`` without padding."""
    return b64url(hashlib.sha256(verifier.encode("ascii")).digest())


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _form(pairs: list[tuple[str, str]]) -> bytes:
    return _urlencode(pairs).encode("ascii")


def _urlencode(pairs: list[tuple[str, str]]) -> str:
    """``application/x-www-form-urlencoded`` byte-for-byte like ``URLSearchParams``
    (space as ``+``; only ``*-._`` and alphanumerics left as is)."""
    return "&".join(f"{_form_escape(key)}={_form_escape(value)}" for key, value in pairs)


def _form_escape(value: str) -> str:
    return quote_plus(value, safe="*").replace("~", "%7E")


def _query_params(url_or_query: str) -> dict[str, str]:
    """First value of each query parameter of a URL, ``/path?query`` or bare query."""
    query = url_or_query.strip().split("#", 1)[0]
    if "?" in query:
        query = query.split("?", 1)[1]
    elif "=" not in query:
        return {}
    params: dict[str, str] = {}
    for key, value in parse_qsl(query, keep_blank_values=True):
        params.setdefault(key, value)
    return params


def _set_query_params(url: str, params: list[tuple[str, str]]) -> str:
    """Like ``URL.searchParams.set`` for each param: an existing key is replaced
    in place (later duplicates dropped), new keys are appended in order, and any
    other query parameters on ``url`` are kept."""
    parts = urlsplit(url)
    ours = dict(params)
    merged: list[tuple[str, str]] = []
    seen: set[str] = set()
    for key, value in parse_qsl(parts.query, keep_blank_values=True):
        if key in ours:
            if key not in seen:
                merged.append((key, ours[key]))
                seen.add(key)
        else:
            merged.append((key, value))
    merged.extend((key, value) for key, value in params if key not in seen)
    path = parts.path or ("/" if parts.netloc else "")
    return urlunsplit((parts.scheme, parts.netloc, path, _urlencode(merged), parts.fragment))
