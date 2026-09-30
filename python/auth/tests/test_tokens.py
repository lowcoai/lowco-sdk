from __future__ import annotations

import base64
import json
import time
from typing import Any

import pytest

from lowcoai.auth import (
    TOKEN_REFRESH_SKEW_SECONDS,
    TokenSet,
    _tokens,
    can_recover_session,
    get_user,
    is_access_token_valid,
)

NOW_MS = 1_790_000_000_000


@pytest.fixture
def frozen_clock(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_tokens, "_now_ms", lambda: NOW_MS)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def jwt(payload: Any, *, header: dict[str, Any] | None = None) -> str:
    head = b64url(json.dumps(header or {"alg": "RS256", "typ": "JWT"}).encode())
    body = b64url(json.dumps(payload).encode("utf-8"))
    return f"{head}.{body}.c2lnbmF0dXJl"


# --- clock -------------------------------------------------------------------


def test_now_ms_is_epoch_milliseconds() -> None:
    before = int(time.time() * 1000)
    now = _tokens._now_ms()
    after = int(time.time() * 1000)
    assert isinstance(now, int)
    assert before <= now <= after


def test_now_ms_follows_time_time(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(time, "time", lambda: 1_700_000_000.1234)
    assert _tokens._now_ms() == 1_700_000_000_123


# --- validity helpers --------------------------------------------------------


@pytest.mark.usefixtures("frozen_clock")
@pytest.mark.parametrize(
    ("expires_at", "skew", "valid"),
    [
        (NOW_MS + 60_001, TOKEN_REFRESH_SKEW_SECONDS, True),
        (NOW_MS + 60_000, TOKEN_REFRESH_SKEW_SECONDS, False),  # strictly greater, like TS
        (NOW_MS + 1, 0, True),
        (NOW_MS, 0, False),
        (NOW_MS + 5_000, 4.999, True),
        (NOW_MS - 1, 0, False),
    ],
)
def test_is_access_token_valid(expires_at: int, skew: float, valid: bool) -> None:
    tokens: TokenSet = {"access_token": "a", "expires_at": expires_at}
    assert is_access_token_valid(tokens, skew) is valid


@pytest.mark.usefixtures("frozen_clock")
def test_is_access_token_valid_rejects_incomplete_tokens() -> None:
    assert is_access_token_valid(None) is False
    assert is_access_token_valid({"access_token": "", "expires_at": NOW_MS * 2}) is False
    broken: Any = {"access_token": "a"}
    assert is_access_token_valid(broken) is False
    broken = {"access_token": "a", "expires_at": str(NOW_MS * 2)}
    assert is_access_token_valid(broken) is False
    broken = {"access_token": "a", "expires_at": True}
    assert is_access_token_valid(broken) is False
    as_float: Any = {"access_token": "a", "expires_at": float(NOW_MS * 2)}
    assert is_access_token_valid(as_float) is True


@pytest.mark.usefixtures("frozen_clock")
def test_can_recover_session() -> None:
    assert can_recover_session(None) is False
    assert can_recover_session({"access_token": "", "refresh_token": "r", "expires_at": 0}) is False
    assert can_recover_session({"access_token": "a", "expires_at": NOW_MS + 120_000}) is True
    assert can_recover_session({"access_token": "a", "expires_at": NOW_MS}) is False
    assert can_recover_session({"access_token": "a", "refresh_token": "r", "expires_at": 0}) is True
    assert can_recover_session({"access_token": "a", "refresh_token": "", "expires_at": 0}) is False


# --- get_user ------------------------------------------------------------------


def test_get_user_prefers_id_token_and_keeps_all_claims() -> None:
    claims = {
        "sub": "user_1",
        "email": "ada@example.com",
        "name": "Ada",
        "picture": "https://img/ada.png",
        "org_id": "org_1",
        "roles": ["admin"],
    }
    tokens: TokenSet = {
        "access_token": jwt({"sub": "from_access"}),
        "id_token": jwt(claims),
        "expires_at": 0,
    }
    user = get_user(tokens)
    assert user == claims
    assert user is not None and user["sub"] == "user_1"
    assert list(user)[:4] == ["sub", "email", "name", "picture"]


def test_get_user_falls_back_to_access_token() -> None:
    tokens: TokenSet = {"access_token": jwt({"sub": "svc", "scope": "x"}), "expires_at": 0}
    assert get_user(tokens) == {"sub": "svc", "scope": "x"}


def test_get_user_non_string_standard_claims_pass_through() -> None:
    tokens: TokenSet = {"access_token": jwt({"sub": 42, "name": None}), "expires_at": 0}
    expected: Any = {"sub": 42, "name": None}
    assert get_user(tokens) == expected


def test_get_user_decodes_urlsafe_chars_utf8_and_missing_padding() -> None:
    # Values chosen so the base64 payload contains "-" and "_" and needs padding.
    payload = {"sub": "u", "name": "Zoë ~~~ ???>>>", "k": "ÿþý"}
    token = jwt(payload)
    segment = token.split(".")[1]
    assert "-" in segment or "_" in segment
    assert len(segment) % 4 != 0
    assert get_user({"access_token": token, "expires_at": 0}) == payload


def test_get_user_accepts_standard_alphabet_and_padding() -> None:
    body = base64.b64encode(json.dumps({"sub": "p", "x": "???>>>"}).encode()).decode()
    assert "=" in body or "+" in body or "/" in body
    token = f"h.{body}.s"
    assert get_user({"access_token": token, "expires_at": 0}) == {"sub": "p", "x": "???>>>"}


@pytest.mark.parametrize(
    "raw",
    [
        "",
        "not-a-jwt",
        "a..c",
        "a.!!!.c",  # invalid base64 alphabet
        "a.abcde.c",  # length % 4 == 1 -> invalid base64
        f"a.{b64url(b'not json')}.c",
        f"a.{b64url(b'[1, 2]')}.c",  # not an object
        "a." + b64url(b'"str"') + ".c",
        f"a.{b64url(bytes([0xFF, 0xFE]))}.c",  # not UTF-8
        "a.eyé.c",  # non-ASCII
    ],
)
def test_get_user_malformed_tokens_return_none(raw: str) -> None:
    assert get_user({"access_token": raw, "expires_at": 0}) is None


def test_get_user_empty_id_token_does_not_fall_back() -> None:
    # Mirrors ``tokens.id_token ?? tokens.access_token``: only a missing id_token falls back.
    tokens: TokenSet = {"access_token": jwt({"sub": "a"}), "id_token": "", "expires_at": 0}
    assert get_user(tokens) is None


def test_get_user_without_tokens() -> None:
    assert get_user(None) is None
