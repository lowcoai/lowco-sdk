"""Transport behaviour: headers, envelope unwrapping, query encoding, errors."""

from __future__ import annotations

import json
from collections.abc import Callable
from types import MappingProxyType
from typing import Any

import httpx
import pytest

from lowcoai.integrations import (
    BASE_URL,
    HEADER_ORG_ID,
    AsyncHttpClient,
    AsyncIntegrationsClient,
    HttpClient,
    IntegrationsClient,
    IntegrationsError,
)
from lowcoai.integrations import types as it_types
from lowcoai.integrations._base import encode_query


class Recorder:
    """Captures requests and answers each with a canned response."""

    def __init__(self, respond: Callable[[httpx.Request], httpx.Response] | None = None) -> None:
        self.requests: list[httpx.Request] = []
        self._respond = respond or (lambda _req: envelope(None))

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self._respond(request)

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]


def envelope(data: Any, status: int = 200) -> httpx.Response:
    return httpx.Response(status, json={"success": True, "data": data})


def make_client(rec: Recorder, **kwargs: Any) -> IntegrationsClient:
    kwargs.setdefault("org_id", "org_1")
    return IntegrationsClient(
        "tok_123", http_client=httpx.Client(transport=httpx.MockTransport(rec)), **kwargs
    )


# --- construction -------------------------------------------------------------


@pytest.mark.parametrize("token", ["", "   "])
@pytest.mark.parametrize(
    "cls", [IntegrationsClient, AsyncIntegrationsClient, HttpClient, AsyncHttpClient]
)
def test_token_is_required(cls: Callable[[str], Any], token: str) -> None:
    with pytest.raises(ValueError, match="token"):
        cls(token)


def test_owned_http_client_is_closed_injected_one_is_not() -> None:
    owned = IntegrationsClient("tok")
    with owned:
        pass
    assert owned._http._http.is_closed

    injected = httpx.Client(transport=httpx.MockTransport(Recorder()))
    with IntegrationsClient("tok", http_client=injected):
        pass
    assert not injected.is_closed
    injected.close()


# --- headers ------------------------------------------------------------------


def test_sends_default_headers_and_fixed_host() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec, headers={"X-Trace": "t1"})
    client.applications.list()
    req = rec.last
    assert BASE_URL == "https://api.lowco.ai"
    assert str(req.url) == "https://api.lowco.ai/v1/integrations/applications"
    assert req.headers["Accept"] == "application/json"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers[HEADER_ORG_ID] == "org_1"
    assert req.headers["X-Trace"] == "t1"
    assert "Content-Type" not in req.headers
    assert req.content == b""


def test_org_header_is_omitted_without_org_id() -> None:
    rec = Recorder()
    make_client(rec, org_id=None).configurations.get()
    assert HEADER_ORG_ID not in rec.last.headers
    make_client(rec, org_id="").configurations.get()
    assert HEADER_ORG_ID not in rec.last.headers


def test_content_type_only_when_a_body_is_sent() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.oauth.refresh_expiring_tokens()  # POST without a body
    assert rec.last.method == "POST"
    assert rec.last.content == b""
    assert "Content-Type" not in rec.last.headers
    client.connections.set_as_default("c1", "app_1")
    assert rec.last.headers["Content-Type"] == "application/json"


@pytest.mark.parametrize("key", ["Authorization", "authorization"])
def test_configured_authorization_header_wins_over_token(key: str) -> None:
    rec = Recorder()
    make_client(rec, headers={key: "Basic abc"}).configurations.get()
    assert rec.last.headers.get_list("Authorization") == ["Basic abc"]


@pytest.mark.parametrize("key", [HEADER_ORG_ID, "x-org-id"])
def test_configured_org_header_wins_over_org_id(key: str) -> None:
    rec = Recorder()
    make_client(rec, headers={key: "org_from_headers"}).configurations.get()
    assert rec.last.headers.get_list(HEADER_ORG_ID) == ["org_from_headers"]


def test_empty_configured_authorization_falls_back_to_token() -> None:
    rec = Recorder()
    make_client(rec, headers={"Authorization": ""}).configurations.get()
    assert rec.last.headers.get_list("Authorization") == ["Bearer tok_123"]


def test_extra_headers_override_accept_and_body_forces_json_content_type() -> None:
    rec = Recorder()
    client = make_client(rec, headers={"accept": "text/plain", "Content-Type": "text/plain"})
    client.actions.run("a1", {"inputBody": {}})
    assert rec.last.headers.get_list("Accept") == ["text/plain"]
    assert rec.last.headers.get_list("Content-Type") == ["application/json"]


def test_body_is_compact_utf8_json() -> None:
    rec = Recorder()
    make_client(rec).applications.run("app_1", {"inputBody": {"name": "Zoë", "n": [1, 2]}})
    assert rec.last.content == '{"inputBody":{"name":"Zoë","n":[1,2]}}'.encode()


# --- responses ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("response", "expected"),
    [
        (
            httpx.Response(200, json={"success": True, "data": {"http": ["oauth2"]}}),
            {"http": ["oauth2"]},
        ),
        (httpx.Response(200, json={"success": True, "data": None}), None),
        (httpx.Response(200, json={"data": [1, 2]}), [1, 2]),
        (httpx.Response(200, json={"http": ["http"]}), {"http": ["http"]}),
        (httpx.Response(200, json=[{"id": "a1"}]), [{"id": "a1"}]),
        (httpx.Response(200, json=7), 7),
        (httpx.Response(200, text=""), None),
        (httpx.Response(200, text="  \n"), None),
        (httpx.Response(204), None),
    ],
)
def test_envelope_unwrapping(response: httpx.Response, expected: Any) -> None:
    client = make_client(Recorder(lambda _r: response))
    assert client.configurations.get() == expected


def test_http_error_with_json_payload() -> None:
    body = {"success": False, "message": "application not found", "error": {"code": "IM-404"}}
    client = make_client(Recorder(lambda _r: httpx.Response(404, json=body)))
    with pytest.raises(IntegrationsError) as info:
        client.applications.get_by_id("missing")
    err = info.value
    assert err.message == "Request failed with status 404"
    assert str(err) == "Request failed with status 404"
    assert err.status == 404
    assert err.payload == body
    assert "status=404" in repr(err)


def test_http_error_with_non_json_payload_keeps_raw_text() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(502, text="<html>Bad gateway</html>")))
    with pytest.raises(IntegrationsError) as info:
        client.applications.list()
    assert info.value.status == 502
    assert info.value.message == "Request failed with status 502"
    assert info.value.payload == "<html>Bad gateway</html>"


def test_http_error_with_empty_body_has_no_payload() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(401)))
    with pytest.raises(IntegrationsError) as info:
        client.connections.list()
    assert info.value.status == 401
    assert info.value.payload is None


def test_void_methods_ignore_non_json_success_bodies() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="OK")))
    assert client.connections.delete("c1") is None  # type: ignore[func-returns-value]


def test_void_methods_still_raise_on_errors() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(409, json={"message": "in use"})))
    with pytest.raises(IntegrationsError) as info:
        client.triggers.delete("t1")
    assert info.value.status == 409
    assert info.value.payload == {"message": "in use"}


def test_non_json_success_body_raises_with_status_and_raw_text() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="not json")))
    with pytest.raises(IntegrationsError) as info:
        client.applications.get_by_id("app_1")
    assert info.value.status == 200
    assert info.value.payload == "not json"
    assert isinstance(info.value.__cause__, ValueError)


@pytest.mark.parametrize(
    "exc", [httpx.ConnectError("connection refused"), httpx.ReadTimeout("timed out")]
)
def test_transport_failures_are_wrapped_with_status_0(exc: httpx.HTTPError) -> None:
    def boom(_req: httpx.Request) -> httpx.Response:
        raise exc

    client = make_client(Recorder(boom))
    with pytest.raises(IntegrationsError) as info:
        client.actions.run("a1", {"inputBody": {}})
    assert info.value.status == 0
    assert info.value.payload is None
    assert info.value.message == str(exc)
    assert info.value.__cause__ is exc


def test_transport_failure_without_text_uses_exception_name() -> None:
    def boom(_req: httpx.Request) -> httpx.Response:
        raise httpx.PoolTimeout("")

    with pytest.raises(IntegrationsError) as info:
        make_client(Recorder(boom)).configurations.get()
    assert info.value.message == "PoolTimeout"
    assert info.value.status == 0


@pytest.mark.parametrize(("timeout", "expected"), [(5.0, 5.0), (None, None)])
def test_timeout_is_applied_per_request(timeout: float | None, expected: float | None) -> None:
    rec = Recorder()
    make_client(rec, timeout=timeout).configurations.get()
    assert rec.last.extensions["timeout"] == {
        "connect": expected,
        "read": expected,
        "write": expected,
        "pool": expected,
    }


# --- query encoding -----------------------------------------------------------


def test_encode_query_mirrors_the_ts_client() -> None:
    assert encode_query(None) is None
    assert encode_query({}) is None
    assert encode_query({"skip": None}) is None
    assert encode_query(
        {
            "page": 2,
            "ratio": 2.5,
            "whole": 3.0,
            "active": True,
            "archived": False,
            "tags": "crm,sales",
            "skip": None,
            "ids": ["a", "é"],
            "filter": {"type": "http"},
        }
    ) == {
        "page": "2",
        "ratio": "2.5",
        "whole": "3",
        "active": "true",
        "archived": "false",
        "tags": "crm,sales",
        "ids": '["a","é"]',
        "filter": '{"type":"http"}',
    }


def test_query_values_are_url_encoded() -> None:
    rec = Recorder(lambda _r: envelope([]))
    make_client(rec).applications.list({"filter": "name = 'a&b'", "page": 1})
    assert dict(rec.last.url.params) == {"filter": "name = 'a&b'", "page": "1"}
    assert b"a%26b" in rec.last.url.query


# --- HttpClient escape hatch --------------------------------------------------


def test_http_client_request_with_per_request_headers_and_relative_path() -> None:
    rec = Recorder(lambda _r: envelope({"ok": True}))
    http = HttpClient(
        "tok_123",
        org_id="org_1",
        headers={"X-Trace": "cfg"},
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
    )
    result = http.request(
        "POST",
        "v1/integrations/custom",
        {"a": 1},
        query={"x": 1},
        headers={"X-Trace": "req", "X-Org-Id": "org_req"},
    )
    assert result == {"ok": True}
    req = rec.last
    assert str(req.url) == "https://api.lowco.ai/v1/integrations/custom?x=1"
    assert req.headers["X-Trace"] == "req"
    assert req.headers[HEADER_ORG_ID] == "org_req"
    assert json.loads(req.content) == {"a": 1}
    assert http.request_void("DELETE", "/v1/integrations/custom") is None  # type: ignore[func-returns-value]


# --- types ----------------------------------------------------------------------


def test_types_module_exports_are_sorted_and_resolvable() -> None:
    assert it_types.__all__ == sorted(it_types.__all__)
    for name in it_types.__all__:
        assert hasattr(it_types, name), name
    assert it_types.HEADER_ORG_ID == "X-Org-Id"
    assert it_types.Application.__required_keys__ == frozenset({"name", "type", "subType"})
    assert it_types.Connection.__required_keys__ == frozenset(
        {"name", "connectionType", "applicationId"}
    )
    assert it_types.ConnectionResponse.__required_keys__ == frozenset(
        {"name", "connectionType", "applicationId"}
    )


def test_typed_usage() -> None:
    """Type-checked by mypy: TypedDict bodies, open-ended queries, generic envelope."""
    app_json = {"id": "app_1", "name": "Slack", "type": "http", "subType": "oauth2"}
    rec = Recorder(lambda _r: envelope(app_json))
    client = make_client(rec)
    app: it_types.Application = {"name": "Slack", "type": "http", "subType": "oauth2"}
    created = client.applications.create(app)
    assert created["name"] == "Slack"
    client.applications.update("app_1", created)  # a response goes straight back as a body
    conn = client.connections.get_by_id("c1")
    client.connections.update("c1", conn)
    query: it_types.PaginationQuery = {"page": 1, "tags": "crm,sales", "sortOrder": "asc"}
    client.applications.list(query)
    client.applications.list({"page": 1, "type": "http"})
    folder: it_types.PostmanFolder = {"name": "root", "item": [{"name": "child", "item": []}]}
    client.applications.load_actions("app_1", folder)
    rpc: it_types.JsonRpcRequest = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    client.mcp.call_published("key", rpc)
    env: it_types.ApiEnvelope[list[it_types.Application]] = {"success": True, "data": [app]}
    assert env["data"][0]["subType"] == "oauth2"
    config: it_types.SubApplicationConfig = {"http": ["http", "oauth2"]}
    assert config["http"][1] == "oauth2"


def test_mapping_bodies_are_serialised() -> None:
    rec = Recorder()
    client = make_client(rec)
    params = MappingProxyType({"x": MappingProxyType({"y": (1, 2)})})
    client.mcp.call_published("k", {"jsonrpc": "2.0", "method": "m", "params": params})
    assert json.loads(rec.last.content) == {
        "jsonrpc": "2.0",
        "method": "m",
        "params": {"x": {"y": [1, 2]}},
    }
    with pytest.raises(TypeError):
        client.actions.run("a1", {"inputBody": {"bad": {1, 2}}})
