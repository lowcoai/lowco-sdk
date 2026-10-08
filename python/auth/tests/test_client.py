from __future__ import annotations

import base64
import hashlib
import json
import re
from collections.abc import Callable
from typing import Any
from urllib.parse import parse_qs, parse_qsl, urlsplit

import httpx
import pytest

from lowcoai.auth import (
    DEFAULT_SCOPE,
    AuthorizationRequest,
    LowcoAuthClient,
    LowcoAuthError,
    TokenSet,
    _tokens,
)

NOW_MS = 1_790_000_000_000
TOKEN_URL = "https://api.lowco.ai/v1/identity/tenants/tenant_1/oauth/token"
B64URL = re.compile(r"^[A-Za-z0-9_-]+$")


@pytest.fixture(autouse=True)
def frozen_clock(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(_tokens, "_now_ms", lambda: NOW_MS)


class Recorder:
    """Captures requests and answers each with a canned response."""

    def __init__(self, respond: Callable[[httpx.Request], httpx.Response] | None = None) -> None:
        self.requests: list[httpx.Request] = []
        self._respond = respond or (lambda _req: token_response())

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self._respond(request)

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]

    def last_form(self) -> list[tuple[str, str]]:
        return parse_qsl(self.last.content.decode("ascii"), keep_blank_values=True)


def token_response(status: int = 200, **overrides: Any) -> httpx.Response:
    body: dict[str, Any] = {
        "access_token": "at_1",
        "token_type": "Bearer",
        "expires_in": 3600,
        "refresh_token": "rt_1",
        "id_token": "idt_1",
        "scope": "openid profile",
    }
    body.update(overrides)
    return httpx.Response(status, json={k: v for k, v in body.items() if v is not None})


def make_client(rec: Recorder | None = None, **kwargs: Any) -> LowcoAuthClient:
    kwargs.setdefault("redirect_uri", "https://app.example/auth/callback")
    return LowcoAuthClient(
        "https://api.lowco.ai/v1/identity/",
        "https://login.lowco.ai/login",
        "tenant_1",
        "client_1",
        http_client=httpx.Client(transport=httpx.MockTransport(rec or Recorder())),
        **kwargs,
    )


def b64url_sha256(value: str) -> str:
    digest = hashlib.sha256(value.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


# --- constructor -----------------------------------------------------------


@pytest.mark.parametrize(
    ("index", "name"), [(0, "domain"), (1, "login_page_url"), (2, "tenant_id"), (3, "client_id")]
)
def test_required_constructor_args(index: int, name: str) -> None:
    args = ["https://auth.example", "https://auth.example/login", "t", "c"]
    args[index] = " "
    with pytest.raises(ValueError, match=name):
        LowcoAuthClient(*args)


def test_token_endpoint_trims_trailing_slashes() -> None:
    client = LowcoAuthClient("https://auth.example/v1/identity///", "https://l", "t 1", "c")
    assert client.token_endpoint == "https://auth.example/v1/identity/tenants/t%201/oauth/token"
    assert make_client().token_endpoint == TOKEN_URL


# --- authorization request -------------------------------------------------


def test_authorization_url_params_and_pkce() -> None:
    client = make_client()
    req = client.create_authorization_request(app_state={"returnTo": "/billing"})
    parts = urlsplit(req.url)
    assert f"{parts.scheme}://{parts.netloc}{parts.path}" == "https://login.lowco.ai/login"
    pairs = parse_qsl(parts.query)
    assert [k for k, _ in pairs] == [
        "tenant_id",
        "client_id",
        "redirect_uri",
        "response_type",
        "scope",
        "state",
        "nonce",
        "code_challenge",
        "code_challenge_method",
    ]
    params = dict(pairs)
    assert params["tenant_id"] == "tenant_1"
    assert params["client_id"] == "client_1"
    assert params["redirect_uri"] == "https://app.example/auth/callback"
    assert params["response_type"] == "code"
    assert params["scope"] == DEFAULT_SCOPE == "openid profile email offline_access"
    assert params["state"] == req.state
    assert params["nonce"] == req.nonce
    assert params["code_challenge"] == b64url_sha256(req.code_verifier)
    assert params["code_challenge_method"] == "S256"
    # Form encoding like URLSearchParams: spaces as "+", reserved chars escaped.
    assert "scope=openid+profile+email+offline_access" in parts.query
    assert "redirect_uri=https%3A%2F%2Fapp.example%2Fauth%2Fcallback" in parts.query
    assert req.redirect_uri == "https://app.example/auth/callback"
    assert req.scope == DEFAULT_SCOPE
    assert req.app_state == {"returnTo": "/billing"}


def test_random_values_lengths_alphabet_and_uniqueness() -> None:
    client = make_client()
    reqs = [client.create_authorization_request() for _ in range(20)]
    for req in reqs:
        # base64url without padding: 24 bytes -> 32 chars, 48 bytes -> 64 chars.
        assert len(req.state) == 32 and B64URL.match(req.state)
        assert len(req.nonce) == 32 and B64URL.match(req.nonce)
        assert len(req.code_verifier) == 64 and B64URL.match(req.code_verifier)
        assert len(base64.urlsafe_b64decode(req.code_verifier)) == 48
        challenge = parse_qs(urlsplit(req.url).query)["code_challenge"][0]
        assert len(challenge) == 43 and "=" not in challenge
        assert req.state != req.nonce
    assert len({r.state for r in reqs}) == 20
    assert len({r.code_verifier for r in reqs}) == 20


def test_existing_login_url_query_is_preserved_and_overridden() -> None:
    client = LowcoAuthClient(
        "https://auth.example",
        "https://auth.example/login?ui=dark&scope=old&x=1&scope=older#frag",
        "t",
        "c",
        redirect_uri="https://app/cb",
    )
    req = client.create_authorization_request()
    parts = urlsplit(req.url)
    pairs = parse_qsl(parts.query)
    keys = [k for k, _ in pairs]
    # Existing "scope" replaced in place (duplicates dropped); others kept first.
    assert keys[:3] == ["ui", "scope", "x"]
    assert keys.count("scope") == 1
    assert dict(pairs)["scope"] == DEFAULT_SCOPE
    assert dict(pairs)["ui"] == "dark"
    assert parts.fragment == "frag"


def test_bare_origin_login_url_gets_a_root_path() -> None:
    client = LowcoAuthClient("https://a", "https://login.example", "t", "c", redirect_uri="r")
    assert client.create_authorization_request().url.startswith("https://login.example/?tenant_id=")


def test_per_call_redirect_and_scope_override_defaults() -> None:
    client = make_client(scope="openid")
    req = client.create_authorization_request()
    assert req.scope == "openid"
    req = client.create_authorization_request(redirect_uri="http://127.0.0.1:8765/cb", scope="x y")
    params = parse_qs(urlsplit(req.url).query)
    assert params["redirect_uri"] == ["http://127.0.0.1:8765/cb"]
    assert params["scope"] == ["x y"]
    assert req.redirect_uri == "http://127.0.0.1:8765/cb"
    assert req.app_state is None


def test_redirect_uri_is_required() -> None:
    client = make_client(redirect_uri=None)
    with pytest.raises(ValueError, match="redirect_uri"):
        client.create_authorization_request()
    assert client.create_authorization_request(redirect_uri="https://a/cb").redirect_uri


def test_authorization_request_roundtrip() -> None:
    req = make_client().create_authorization_request(app_state={"returnTo": "/x", "n": 1})
    data = req.to_dict()
    assert set(data) == {
        "url",
        "state",
        "nonce",
        "code_verifier",
        "redirect_uri",
        "scope",
        "app_state",
    }
    restored = AuthorizationRequest.from_dict(json.loads(json.dumps(data)))
    assert restored == req
    assert req.code_verifier not in repr(req)


def test_authorization_request_from_minimal_dict() -> None:
    restored = AuthorizationRequest.from_dict(
        {"state": "s", "code_verifier": "v", "redirect_uri": "https://a/cb"}
    )
    assert restored == AuthorizationRequest(
        url="", state="s", nonce="", code_verifier="v", redirect_uri="https://a/cb", scope=""
    )
    with pytest.raises(ValueError, match="code_verifier, redirect_uri"):
        AuthorizationRequest.from_dict({"state": "s"})


# --- code exchange -----------------------------------------------------------


def test_exchange_code_request_and_token_set() -> None:
    rec = Recorder()
    client = make_client(rec)
    req = client.create_authorization_request()
    tokens = client.exchange_code("code_1", req)
    sent = rec.last
    assert sent.method == "POST"
    assert str(sent.url) == TOKEN_URL
    assert sent.headers["Content-Type"] == "application/x-www-form-urlencoded"
    assert "Authorization" not in sent.headers
    assert rec.last_form() == [
        ("grant_type", "authorization_code"),
        ("tenant_id", "tenant_1"),
        ("client_id", "client_1"),
        ("code", "code_1"),
        ("code_verifier", req.code_verifier),
        ("redirect_uri", "https://app.example/auth/callback"),
    ]
    assert tokens == {
        "access_token": "at_1",
        "token_type": "Bearer",
        "expires_in": 3600,
        "refresh_token": "rt_1",
        "id_token": "idt_1",
        "scope": "openid profile",
        "expires_at": NOW_MS + 3_600_000,
    }


def test_form_values_are_url_encoded() -> None:
    rec = Recorder()
    client = make_client(rec, redirect_uri="https://app/cb?a=1&b=2")
    req = client.create_authorization_request(scope="a~b*c")
    client.exchange_code("c+/= d~*'()!é", req)
    raw = rec.last.content.decode("ascii")
    # Byte-for-byte what URLSearchParams produces ("~" escaped, "*" kept).
    assert "code=c%2B%2F%3D+d%7E*%27%28%29%21%C3%A9" in raw
    assert "redirect_uri=https%3A%2F%2Fapp%2Fcb%3Fa%3D1%26b%3D2" in raw
    assert "&scope=a%7Eb*c&" in req.url


@pytest.mark.parametrize(
    ("expires_in", "expected_ms"),
    [(3600, 3_600_000), (1.5, 1500), ("120", 120_000), (0, 0), (None, 0), ("soon", 0), (True, 0)],
)
def test_expires_at_math(expires_in: Any, expected_ms: int) -> None:
    rec = Recorder(lambda _r: token_response(expires_in=expires_in))
    client = make_client(rec)
    tokens = client.exchange_code("c", client.create_authorization_request())
    assert tokens["expires_at"] == NOW_MS + expected_ms
    assert isinstance(tokens["expires_at"], int)


def test_exchange_code_http_error() -> None:
    body = {"error": "invalid_grant", "message": "code expired"}
    rec = Recorder(lambda _r: httpx.Response(400, json=body))
    client = make_client(rec)
    with pytest.raises(LowcoAuthError) as info:
        client.exchange_code("c", client.create_authorization_request())
    err = info.value
    assert err.message == str(err) == "Authorization code exchange failed."
    assert err.status_code == 400
    assert err.code == "invalid_grant"
    assert err.body is not None and json.loads(err.body) == body


def test_exchange_code_http_error_with_text_body() -> None:
    rec = Recorder(lambda _r: httpx.Response(503, text="unavailable"))
    client = make_client(rec)
    with pytest.raises(LowcoAuthError) as info:
        client.exchange_code("c", client.create_authorization_request())
    assert info.value.status_code == 503
    assert info.value.body == "unavailable"
    assert info.value.code is None


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, text="not json"),
        httpx.Response(200, json=["x"]),
        httpx.Response(200, json={"expires_in": 60}),
        httpx.Response(200, json={"access_token": ""}),
    ],
)
def test_exchange_code_invalid_success_body(response: httpx.Response) -> None:
    client = make_client(Recorder(lambda _r: response))
    with pytest.raises(LowcoAuthError, match="^Authorization code exchange failed. ") as info:
        client.exchange_code("c", client.create_authorization_request())
    assert info.value.status_code == 200


def test_blank_code_is_rejected() -> None:
    rec = Recorder()
    client = make_client(rec)
    with pytest.raises(ValueError):
        client.exchange_code("", client.create_authorization_request())
    assert rec.requests == []


def test_transport_errors_propagate() -> None:
    def boom(_r: httpx.Request) -> httpx.Response:
        raise httpx.ConnectTimeout("slow")

    client = make_client(Recorder(boom))
    with pytest.raises(httpx.ConnectTimeout):
        client.refresh_tokens("rt")


# --- redirect callback -----------------------------------------------------


def test_handle_redirect_callback_exchanges_code() -> None:
    rec = Recorder()
    client = make_client(rec)
    req = client.create_authorization_request()
    url = f"https://app.example/auth/callback?code=abc%2F1&state={req.state}&session_state=x"
    tokens = client.handle_redirect_callback(url, req)
    assert tokens["access_token"] == "at_1"
    assert dict(rec.last_form())["code"] == "abc/1"


@pytest.mark.parametrize(
    "template",
    ["/auth/callback?code=c1&state={state}", "?state={state}&code=c1", "code=c1&state={state}"],
)
def test_callback_accepts_path_or_query(template: str) -> None:
    rec = Recorder()
    client = make_client(rec)
    req = client.create_authorization_request()
    client.handle_redirect_callback(template.format(state=req.state), req)
    assert dict(rec.last_form())["code"] == "c1"


def test_callback_oauth_error() -> None:
    rec = Recorder()
    client = make_client(rec)
    req = client.create_authorization_request()
    with pytest.raises(LowcoAuthError) as info:
        client.handle_redirect_callback(
            f"https://app/cb?error=access_denied&error_description=User+said+no&state={req.state}",
            req,
        )
    assert info.value.message == "User said no"
    assert info.value.code == "access_denied"
    with pytest.raises(LowcoAuthError) as info:
        client.handle_redirect_callback("https://app/cb?error=server_error", req)
    assert info.value.message == "Authorization failed (server_error)."
    assert rec.requests == []


@pytest.mark.parametrize(
    "query", ["", "?code=c1", "?state=s", "?code=&state=s", "#code=c1&state=s"]
)
def test_callback_missing_code_or_state(query: str) -> None:
    rec = Recorder()
    client = make_client(rec)
    req = AuthorizationRequest.from_dict({"state": "s", "code_verifier": "v", "redirect_uri": "r"})
    with pytest.raises(LowcoAuthError, match="Missing code or state"):
        client.handle_redirect_callback(f"https://app/cb{query}", req)
    assert rec.requests == []


def test_callback_state_mismatch() -> None:
    rec = Recorder()
    client = make_client(rec)
    req = client.create_authorization_request()
    other = client.create_authorization_request()
    with pytest.raises(LowcoAuthError, match="state mismatch"):
        client.handle_redirect_callback(f"https://app/cb?code=c&state={other.state}", req)
    with pytest.raises(LowcoAuthError, match="state mismatch"):
        client.handle_redirect_callback("https://app/cb?code=c&state=%C3%A9", req)
    assert rec.requests == []


# --- refresh ---------------------------------------------------------------


def test_refresh_with_bare_token() -> None:
    rec = Recorder(lambda _r: token_response(refresh_token=None, id_token=None, scope=None))
    tokens = make_client(rec).refresh_tokens("rt_old")
    assert str(rec.last.url) == TOKEN_URL
    assert rec.last.headers["Content-Type"] == "application/x-www-form-urlencoded"
    assert rec.last_form() == [
        ("grant_type", "refresh_token"),
        ("tenant_id", "tenant_1"),
        ("client_id", "client_1"),
        ("refresh_token", "rt_old"),
    ]
    assert tokens == {
        "access_token": "at_1",
        "token_type": "Bearer",
        "expires_in": 3600,
        "expires_at": NOW_MS + 3_600_000,
    }


def test_refresh_merges_over_previous_token_set() -> None:
    previous: TokenSet = {
        "access_token": "at_old",
        "refresh_token": "rt_old",
        "id_token": "idt_old",
        "expires_at": 1,
        "scope": "openid",
    }
    rec = Recorder(
        lambda _r: token_response(access_token="at_new", expires_in=60, refresh_token=None)
    )
    tokens = make_client(rec).refresh_tokens(previous)
    assert dict(rec.last_form())["refresh_token"] == "rt_old"
    assert tokens == {
        "access_token": "at_new",
        "refresh_token": "rt_old",  # not rotated -> kept
        "id_token": "idt_1",
        "expires_at": NOW_MS + 60_000,
        "scope": "openid profile",
        "token_type": "Bearer",
        "expires_in": 60,
    }
    assert previous["access_token"] == "at_old"  # input not mutated


def test_refresh_rotated_token_wins() -> None:
    rec = Recorder(lambda _r: token_response(refresh_token="rt_new"))
    tokens = make_client(rec).refresh_tokens(
        {"access_token": "a", "refresh_token": "rt_old", "expires_at": 0}
    )
    assert tokens["refresh_token"] == "rt_new"


def test_refresh_errors() -> None:
    rec = Recorder(lambda _r: httpx.Response(400, json={"error": "invalid_grant"}))
    client = make_client(rec)
    with pytest.raises(LowcoAuthError) as info:
        client.refresh_tokens("rt")
    assert info.value.message == "Refresh token exchange failed."
    assert info.value.status_code == 400
    assert info.value.code == "invalid_grant"
    with pytest.raises(LowcoAuthError, match="No refresh token"):
        client.refresh_tokens({"access_token": "a", "expires_at": 0})
    with pytest.raises(ValueError):
        client.refresh_tokens(" ")
    assert len(rec.requests) == 1


# --- get_valid_tokens --------------------------------------------------------


def test_get_valid_tokens_returns_valid_tokens_as_is() -> None:
    rec = Recorder()
    tokens: TokenSet = {"access_token": "a", "refresh_token": "r", "expires_at": NOW_MS + 61_000}
    assert make_client(rec).get_valid_tokens(tokens) is tokens
    assert rec.requests == []


def test_get_valid_tokens_refreshes_inside_skew() -> None:
    rec = Recorder(lambda _r: token_response(access_token="fresh", refresh_token=None))
    tokens: TokenSet = {"access_token": "a", "refresh_token": "r", "expires_at": NOW_MS + 60_000}
    result = make_client(rec).get_valid_tokens(tokens)
    assert result["access_token"] == "fresh"
    assert result["refresh_token"] == "r"
    assert result["expires_at"] == NOW_MS + 3_600_000
    assert dict(rec.last_form())["grant_type"] == "refresh_token"


def test_get_valid_tokens_errors() -> None:
    rec = Recorder()
    client = make_client(rec)
    with pytest.raises(LowcoAuthError, match=r"^Not authenticated\.$"):
        client.get_valid_tokens(None)
    with pytest.raises(LowcoAuthError, match=r"^Not authenticated\.$"):
        client.get_valid_tokens({"access_token": "", "expires_at": NOW_MS + 999_999})
    with pytest.raises(LowcoAuthError, match=r"^Session expired\.$"):
        client.get_valid_tokens({"access_token": "a", "expires_at": NOW_MS})
    assert rec.requests == []
    failing = make_client(Recorder(lambda _r: httpx.Response(401)))
    with pytest.raises(LowcoAuthError, match="Refresh token exchange failed"):
        failing.get_valid_tokens({"access_token": "a", "refresh_token": "r", "expires_at": 0})


def test_timeout_and_injected_client() -> None:
    rec = Recorder()
    http = httpx.Client(transport=httpx.MockTransport(rec))
    with LowcoAuthClient("https://a", "https://l", "t", "c", timeout=7.0, http_client=http) as c:
        c.refresh_tokens("rt")
    assert rec.last.extensions["timeout"]["read"] == 7.0
    assert not http.is_closed
    own = LowcoAuthClient("https://a", "https://l", "t", "c")
    own.close()
    assert own._http.is_closed
