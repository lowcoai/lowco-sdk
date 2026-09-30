from __future__ import annotations

import inspect
from typing import Any
from urllib.parse import parse_qsl

import httpx
import pytest

from lowcoai.auth import AsyncLowcoAuthClient, LowcoAuthClient, LowcoAuthError, TokenSet, _tokens

NOW_MS = 1_790_000_000_000
TOKEN_URL = "https://auth.example/v1/identity/tenants/tenant_1/oauth/token"


@pytest.fixture(autouse=True)
def frozen_clock(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_tokens, "_now_ms", lambda: NOW_MS)


def make_client(handler: Any) -> AsyncLowcoAuthClient:
    return AsyncLowcoAuthClient(
        "https://auth.example/v1/identity",
        "https://auth.example/login",
        "tenant_1",
        "client_1",
        redirect_uri="https://app/cb",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


def form(request: httpx.Request) -> dict[str, str]:
    return dict(parse_qsl(request.content.decode("ascii")))


async def test_async_callback_refresh_and_get_valid_tokens() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        grant = form(request)["grant_type"]
        token = "at_code" if grant == "authorization_code" else "at_refresh"
        return httpx.Response(
            200, json={"access_token": token, "expires_in": 10, "refresh_token": "rt"}
        )

    async with make_client(handler) as client:
        req = client.create_authorization_request()  # sync on the async client too
        tokens = await client.handle_redirect_callback(
            f"https://app/cb?code=c1&state={req.state}", req
        )
        assert tokens == {
            "access_token": "at_code",
            "expires_in": 10,
            "refresh_token": "rt",
            "expires_at": NOW_MS + 10_000,
        }
        assert str(seen[0].url) == TOKEN_URL
        assert seen[0].headers["Content-Type"] == "application/x-www-form-urlencoded"
        assert form(seen[0]) == {
            "grant_type": "authorization_code",
            "tenant_id": "tenant_1",
            "client_id": "client_1",
            "code": "c1",
            "code_verifier": req.code_verifier,
            "redirect_uri": "https://app/cb",
        }

        # expires within the 60 s skew -> refreshed and merged
        refreshed = await client.get_valid_tokens(tokens)
        assert refreshed["access_token"] == "at_refresh"
        assert form(seen[1]) == {
            "grant_type": "refresh_token",
            "tenant_id": "tenant_1",
            "client_id": "client_1",
            "refresh_token": "rt",
        }

        valid: TokenSet = {"access_token": "a", "expires_at": NOW_MS + 120_000}
        assert await client.get_valid_tokens(valid) is valid
        assert (await client.refresh_tokens("rt_x"))["access_token"] == "at_refresh"
        assert len(seen) == 3


async def test_async_errors() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "invalid_grant"})

    client = make_client(handler)
    req = client.create_authorization_request()
    with pytest.raises(LowcoAuthError) as info:
        await client.exchange_code("c", req)
    assert info.value.message == "Authorization code exchange failed."
    assert info.value.code == "invalid_grant"
    with pytest.raises(LowcoAuthError, match="Refresh token exchange failed"):
        await client.refresh_tokens("rt")
    with pytest.raises(LowcoAuthError, match="state mismatch"):
        await client.handle_redirect_callback("https://app/cb?code=c&state=nope", req)
    with pytest.raises(LowcoAuthError, match="Session expired"):
        await client.get_valid_tokens({"access_token": "a", "expires_at": 0})
    with pytest.raises(LowcoAuthError, match="Not authenticated"):
        await client.get_valid_tokens(None)
    await client.aclose()


def _public_methods(cls: type) -> dict[str, inspect.Signature]:
    return {
        name: inspect.signature(fn)
        for name, fn in inspect.getmembers(cls, inspect.isfunction)
        if not name.startswith("_")
    }


def test_sync_and_async_clients_expose_the_same_api() -> None:
    sync = _public_methods(LowcoAuthClient)
    async_ = _public_methods(AsyncLowcoAuthClient)
    sync.pop("close")
    async_.pop("aclose")
    assert (
        sync.keys()
        == async_.keys()
        == {
            "create_authorization_request",
            "exchange_code",
            "handle_redirect_callback",
            "refresh_tokens",
            "get_valid_tokens",
        }
    )
    for name, sig in sync.items():
        assert str(sig) == str(async_[name]), name
        is_coro = inspect.iscoroutinefunction(getattr(AsyncLowcoAuthClient, name))
        assert is_coro is (name != "create_authorization_request"), name
    assert str(inspect.signature(LowcoAuthClient.__init__)).replace(
        "httpx.Client", "httpx.AsyncClient"
    ) == str(inspect.signature(AsyncLowcoAuthClient.__init__))
    assert isinstance(AsyncLowcoAuthClient.token_endpoint, property)
