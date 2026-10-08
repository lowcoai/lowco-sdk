"""Data shapes for the lowco OAuth 2.0 Authorization Code + PKCE flow.

``TokenSet`` and ``UserProfile`` are ``TypedDict``s with the same keys the React
SDK (``@lowcoai/auth``) persists, so a token set can be stored as JSON and
shared between a browser app and a Python backend. Fields are optional unless
marked ``Required``.
"""

from collections.abc import Mapping
from dataclasses import asdict, dataclass, field
from typing import Any

from typing_extensions import Required, Self, TypedDict

__all__ = [
    "AppState",
    "AuthorizationRequest",
    "TokenSet",
    "UserProfile",
]

AppState = dict[str, Any]
"""Arbitrary JSON-serialisable state carried through the login round trip."""


class TokenSet(TypedDict, total=False):
    """Tokens returned by the token endpoint, plus ``expires_at``.

    ``expires_at`` is the access-token expiry as **epoch milliseconds**
    (JavaScript ``Date.now()`` units, not seconds): ``now_ms + expires_in * 1000``
    at the time the tokens were received.

    Like the React SDK, every other field of the token response (for example
    ``token_type`` and ``expires_in``) is kept in the dict as well.
    """

    access_token: Required[str]
    refresh_token: str
    id_token: str
    expires_at: Required[int]
    scope: str


class UserProfile(TypedDict, total=False):
    """Claims decoded from the ID token (or the access token when there is none).

    The four standard claims are typed here; **every** claim of the token
    payload is present in the dict at runtime (read them with ``dict(user)``).
    """

    sub: str
    email: str
    name: str
    picture: str


@dataclass(frozen=True)
class AuthorizationRequest:
    """One login attempt: the URL to redirect to and the secrets to finish it.

    Keep it server-side (for example in the user's session) between
    :meth:`~lowcoai.auth.LowcoAuthClient.create_authorization_request` and the
    redirect callback; :meth:`to_dict` / :meth:`from_dict` convert it to and
    from a JSON-serialisable dict. ``code_verifier`` must only travel back to
    your own server (it is left out of ``repr``).
    """

    url: str
    """Login page URL with the OAuth + PKCE query parameters; redirect the user here."""
    state: str
    nonce: str
    code_verifier: str = field(repr=False)
    redirect_uri: str
    scope: str
    app_state: AppState | None = None

    def to_dict(self) -> dict[str, Any]:
        """Returns a JSON-serialisable dict with the field names as keys."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> Self:
        """Rebuilds a request saved with :meth:`to_dict`.

        ``state``, ``code_verifier`` and ``redirect_uri`` are required (they
        are needed to finish the flow); ``url``, ``nonce`` and ``scope`` may be
        dropped before storing to save space and default to ``""``.
        """
        missing = [
            key
            for key in ("state", "code_verifier", "redirect_uri")
            if not isinstance(data.get(key), str) or not data[key]
        ]
        if missing:
            raise ValueError(f"AuthorizationRequest: missing {', '.join(missing)}")
        app_state = data.get("app_state")
        return cls(
            url=str(data.get("url") or ""),
            state=data["state"],
            nonce=str(data.get("nonce") or ""),
            code_verifier=data["code_verifier"],
            redirect_uri=data["redirect_uri"],
            scope=str(data.get("scope") or ""),
            app_state=dict(app_state) if isinstance(app_state, dict) else None,
        )
