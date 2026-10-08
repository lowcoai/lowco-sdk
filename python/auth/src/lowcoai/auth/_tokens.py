"""Token-set helpers shared by both clients and exported for apps."""

from __future__ import annotations

import base64
import json
import math
import time
from collections.abc import Mapping
from typing import Any, cast

from ._errors import LowcoAuthError, error_code_from_body
from .types import TokenSet, UserProfile

TOKEN_REFRESH_SKEW_SECONDS = 60
"""How long before expiry an access token stops counting as valid (proactive refresh)."""

_PROFILE_CLAIMS = ("sub", "email", "name", "picture")


def _now_ms() -> int:
    """Current time in epoch milliseconds (JavaScript ``Date.now()``)."""
    return int(time.time() * 1000)


def is_access_token_valid(
    tokens: TokenSet | None, skew_seconds: float = TOKEN_REFRESH_SKEW_SECONDS
) -> bool:
    """True when ``tokens`` has an access token that expires more than
    ``skew_seconds`` from now (``expires_at`` is epoch **milliseconds**)."""
    if not tokens or not tokens.get("access_token"):
        return False
    expires_at = tokens.get("expires_at")
    if isinstance(expires_at, bool) or not isinstance(expires_at, (int, float)):
        return False
    return expires_at > _now_ms() + skew_seconds * 1000


def can_recover_session(tokens: TokenSet | None) -> bool:
    """True when the session is still usable: the access token is valid, or a
    refresh token can get a new one."""
    if not tokens or not tokens.get("access_token"):
        return False
    return is_access_token_valid(tokens) or bool(tokens.get("refresh_token"))


def get_user(tokens: TokenSet | None) -> UserProfile | None:
    """Decodes the user's claims from the ID token, else from the access token.

    The JWT signature is **not** verified: use the result for display only,
    never for authorisation decisions (validate the access token server-side
    for that). Returns ``None`` when there is no token or it is not a
    decodable JWT with a JSON-object payload.
    """
    if not tokens:
        return None
    id_token = tokens.get("id_token")
    payload = _decode_jwt_payload(id_token if id_token is not None else tokens.get("access_token"))
    if payload is None:
        return None
    profile: dict[str, Any] = {
        key: payload[key] for key in _PROFILE_CLAIMS if isinstance(payload.get(key), str)
    }
    profile.update(payload)
    return cast(UserProfile, profile)


def _decode_jwt_payload(raw: object) -> dict[str, Any] | None:
    if not isinstance(raw, str) or not raw:
        return None
    segments = raw.split(".")
    if len(segments) < 2 or not segments[1]:
        return None
    segment = segments[1]
    try:
        data = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
        payload = json.loads(data.decode("utf-8"))
    except ValueError:  # binascii.Error, UnicodeDecodeError, JSONDecodeError
        return None
    return payload if isinstance(payload, dict) else None


def tokens_from_response(
    status: int,
    text: str,
    *,
    failure_message: str,
    previous: Mapping[str, Any] | None = None,
) -> TokenSet:
    """Turns a token-endpoint response into a :class:`TokenSet`.

    Mirrors the React SDK: ``{...previous, ...response, expires_at}`` with
    ``expires_at = Date.now() + expires_in * 1000``.
    """
    if status < 200 or status >= 300:
        raise LowcoAuthError(
            failure_message, status_code=status, body=text, code=error_code_from_body(text)
        )
    try:
        parsed: Any = json.loads(text)
    except ValueError:
        parsed = None
    if (
        not isinstance(parsed, dict)
        or not isinstance(parsed.get("access_token"), str)
        or not parsed["access_token"]
    ):
        raise LowcoAuthError(
            f"{failure_message} The token response has no access_token.",
            status_code=status,
            body=text,
        )
    merged: dict[str, Any] = {**(previous or {}), **parsed}
    merged["expires_at"] = _now_ms() + _expires_in_ms(parsed.get("expires_in"))
    return cast(TokenSet, merged)


def _expires_in_ms(value: object) -> int:
    """``expires_in`` (seconds) as milliseconds; missing / invalid counts as 0,
    so the access token is treated as already expired."""
    seconds: float
    if isinstance(value, bool):
        return 0
    if isinstance(value, (int, float)):
        seconds = float(value)
    elif isinstance(value, str):
        try:
            seconds = float(value)
        except ValueError:
            return 0
    else:
        return 0
    if not math.isfinite(seconds):
        return 0
    return round(seconds * 1000)
