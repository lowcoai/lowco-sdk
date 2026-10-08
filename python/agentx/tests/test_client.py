from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

import httpx
import pytest

from lowcoai.agentx import (
    A2A_ERROR_CODES,
    BASE_URL,
    DEFAULT_EXECUTOR_API_BASE_PATH,
    DEFAULT_KB_API_BASE_PATH,
    DEFAULT_MANAGER_API_BASE_PATH,
    HEADER_ORG_ID,
    JSONRPC_ERROR_CODES,
    METHOD_MESSAGE_SEND,
    AgentxClient,
    AgentxError,
    MessageSendParams,
)


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

    def last_json(self) -> Any:
        return json.loads(self.last.content)


def envelope(data: Any, status: int = 200) -> httpx.Response:
    return httpx.Response(status, json={"success": True, "data": data})


def make_client(rec: Recorder, **kwargs: Any) -> AgentxClient:
    return AgentxClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
        **kwargs,
    )


PARAMS: MessageSendParams = {
    "message": {
        "role": "user",
        "messageId": "msg_001",
        "kind": "message",
        "parts": [{"kind": "text", "text": "Hello!"}],
    },
    "chatType": "chat",
}


def test_constants() -> None:
    assert BASE_URL == "https://api.lowco.ai"
    assert HEADER_ORG_ID == "X-Org-Id"
    assert DEFAULT_MANAGER_API_BASE_PATH == "/v1/agentx/manager"
    assert DEFAULT_KB_API_BASE_PATH == "/v1/agentx/kb"
    assert DEFAULT_EXECUTOR_API_BASE_PATH == "/v1/agentx/executors"
    assert METHOD_MESSAGE_SEND == "message/send"
    assert JSONRPC_ERROR_CODES["MethodNotFound"] == -32601
    assert A2A_ERROR_CODES["InvalidAgentResponse"] == -32006


@pytest.mark.parametrize("token", ["", "   "])
def test_token_is_required(token: str) -> None:
    with pytest.raises(ValueError, match="token is required"):
        AgentxClient(token)


def test_sends_auth_org_accept_and_default_headers() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec, default_headers={"X-Trace": "t1", "Authorization": "ignored"})
    client.manager.list_agents()
    req = rec.last
    assert str(req.url) == "https://api.lowco.ai/v1/agentx/manager/agents"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers[HEADER_ORG_ID] == "org_1"
    assert req.headers["Accept"] == "application/json"
    assert req.headers["X-Trace"] == "t1"
    assert "Content-Type" not in req.headers


def test_no_org_header_without_org_id() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = AgentxClient("t", http_client=httpx.Client(transport=httpx.MockTransport(rec)))
    client.kb.list_datasets()
    assert HEADER_ORG_ID not in rec.last.headers


def test_headers_are_shared_by_all_sub_clients() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec)

    def call_all() -> list[httpx.Request]:
        start = len(rec.requests)
        client.manager.list_models()
        client.kb.list_knowledge_bases()
        client.executor.health()
        return rec.requests[start:]

    client.set_org_id("org_2")
    client.set_header("X-Extra", "1")
    for req in call_all():
        assert req.headers[HEADER_ORG_ID] == "org_2"
        assert req.headers["X-Extra"] == "1"

    client.set_org_id(None)
    client.set_header("X-Extra", None)
    for req in call_all():
        assert HEADER_ORG_ID not in req.headers
        assert "X-Extra" not in req.headers

    client.set_org_id("")
    assert HEADER_ORG_ID not in call_all()[0].headers


def test_sub_clients_share_one_http_client() -> None:
    client = AgentxClient("t")
    transports = {id(client.manager._t), id(client.kb._t), id(client.executor._t)}
    assert transports == {id(client._transport)}
    client.close()


def test_api_base_path_overrides() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(
        rec,
        manager_api_base_path="/custom/mgr/",
        kb_api_base_path="kb2",
        executor_api_base_path="//x/exec//",
    )
    client.manager.list_agents()
    assert str(rec.last.url) == "https://api.lowco.ai/custom/mgr/agents"
    client.kb.get_dataset_count()
    assert str(rec.last.url) == "https://api.lowco.ai/kb2/datasets/count"
    client.executor.send_message("agent_1", PARAMS)
    assert str(rec.last.url) == "https://api.lowco.ai/x/exec/execute"
    for sub in (client.manager, client.kb, client.executor):
        sub.health()
        assert str(rec.last.url) == "https://api.lowco.ai/health"


def test_path_segments_are_escaped() -> None:
    rec = Recorder(lambda _r: envelope({}))
    client = make_client(rec)
    client.manager.get_agent("a/b c?")
    assert rec.last.url.raw_path == b"/v1/agentx/manager/agents/a%2Fb%20c%3F"
    client.manager.list_conversations_by_agent("x#1")
    assert rec.last.url.raw_path == b"/v1/agentx/manager/conversations/x%231"


def test_null_data_and_empty_body_return_none() -> None:
    client = make_client(Recorder(lambda _r: envelope(None)))
    assert client.manager.get_agent("a1") is None
    client = make_client(Recorder(lambda _r: httpx.Response(204)))
    assert client.kb.get_knowledge_base("k1") is None
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="  ")))
    assert client.manager.get_agent_count() is None


def test_non_enveloped_response_without_data_key_is_returned_whole() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, json={"id": "a1"})))
    assert client.manager.get_agent("a1") == {"id": "a1"}


def test_timeouts() -> None:
    rec = Recorder(lambda _r: envelope([]))
    make_client(rec).manager.list_agents()
    assert rec.last.extensions["timeout"] == {
        "connect": 30.0,
        "read": 30.0,
        "write": 30.0,
        "pool": 30.0,
    }
    make_client(rec, timeout=None).kb.list_datasets()
    assert set(rec.last.extensions["timeout"].values()) == {None}
    make_client(rec, timeout=2.5).executor.health()
    assert rec.last.extensions["timeout"]["read"] == 2.5


# --- executor: send_message ---------------------------------------------------


def test_send_message_posts_jsonrpc_and_returns_raw_response() -> None:
    reply = {
        "jsonrpc": "2.0",
        "id": "agent_1",
        "result": {"kind": "message", "role": "assistant", "data": "not an envelope"},
    }
    rec = Recorder(lambda _r: httpx.Response(200, json=reply))
    client = make_client(rec)
    assert client.executor.send_message("agent_1", PARAMS) == reply
    req = rec.last
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/agentx/executors/execute"
    assert req.headers["Accept"] == "application/json"
    assert req.headers["Content-Type"] == "application/json"
    assert rec.last_json() == {
        "jsonrpc": "2.0",
        "method": "message/send",
        "params": PARAMS,
        "id": "agent_1",
    }


def test_send_message_returns_jsonrpc_errors_instead_of_raising() -> None:
    reply = {"jsonrpc": "2.0", "id": "a", "error": {"code": -32601, "message": "nope"}}
    client = make_client(Recorder(lambda _r: httpx.Response(200, json=reply)))
    resp = client.executor.send_message("a", PARAMS)
    assert resp.get("error", {}).get("code") == JSONRPC_ERROR_CODES["MethodNotFound"]


@pytest.mark.parametrize("response", [httpx.Response(204), httpx.Response(200, text=" \n")])
def test_send_message_empty_body(response: httpx.Response) -> None:
    client = make_client(Recorder(lambda _r: response))
    assert client.executor.send_message("agent_9", PARAMS) == {"jsonrpc": "2.0", "id": "agent_9"}


def test_send_message_http_error_raises() -> None:
    body = {"success": False, "error": {"code": "AGENT_NOT_FOUND", "message": "no agent"}}
    client = make_client(Recorder(lambda _r: httpx.Response(404, json=body)))
    with pytest.raises(AgentxError) as info:
        client.executor.send_message("missing", PARAMS)
    assert info.value.status_code == 404
    assert info.value.code == "AGENT_NOT_FOUND"
    assert info.value.message == "no agent"


def test_send_message_invalid_json_raises_agentx_error() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="<html>")))
    with pytest.raises(AgentxError) as info:
        client.executor.send_message("a", PARAMS)
    assert info.value.status_code == 200
    assert info.value.body == "<html>"


# --- errors ------------------------------------------------------------------


def test_error_uses_envelope_message_and_code() -> None:
    body = {"success": False, "error": {"code": "NOT_FOUND", "message": "agent not found"}}
    client = make_client(Recorder(lambda _r: httpx.Response(404, json=body)))
    with pytest.raises(AgentxError) as info:
        client.manager.get_agent("missing")
    err = info.value
    assert err.status_code == 404
    assert err.message == "agent not found"
    assert str(err) == "agent not found"
    assert err.code == "NOT_FOUND"
    assert json.loads(err.body) == body
    assert "NOT_FOUND" in repr(err)


def test_error_numeric_code_is_kept() -> None:
    body = {"error": {"code": 409, "message": "conflict"}}
    client = make_client(Recorder(lambda _r: httpx.Response(409, json=body)))
    with pytest.raises(AgentxError) as info:
        client.kb.create_dataset({"name": "d"})
    assert info.value.code == 409


def test_error_falls_back_to_top_level_message_then_raw_text() -> None:
    body = {"error": {"code": "X", "message": "  "}, "message": "bad request"}
    client = make_client(Recorder(lambda _r: httpx.Response(400, json=body)))
    with pytest.raises(AgentxError) as info:
        client.manager.list_agents()
    assert info.value.message == "bad request"
    assert info.value.code is None

    client = make_client(Recorder(lambda _r: httpx.Response(502, text=" upstream down ")))
    with pytest.raises(AgentxError) as info:
        client.kb.list_datasets()
    assert info.value.message == "upstream down"
    assert info.value.status_code == 502
    assert info.value.body == " upstream down "

    client = make_client(Recorder(lambda _r: httpx.Response(400, json=["x"])))
    with pytest.raises(AgentxError) as info:
        client.kb.list_datasets()
    assert info.value.message == '["x"]'

    client = make_client(Recorder(lambda _r: httpx.Response(503, text="")))
    with pytest.raises(AgentxError) as info:
        client.manager.delete_agent("a1")
    assert info.value.message == "agentx: status=503"


def test_health_errors_raise() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(500, text="down")))
    for sub in (client.manager, client.kb, client.executor):
        with pytest.raises(AgentxError) as info:
            sub.health()
        assert info.value.message == "down"


def test_invalid_json_success_raises_agentx_error() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="<html>")))
    with pytest.raises(AgentxError) as info:
        client.manager.get_agent("a1")
    assert info.value.status_code == 200
    assert info.value.body == "<html>"


def test_owned_http_client_closes_but_injected_does_not() -> None:
    injected = httpx.Client(transport=httpx.MockTransport(Recorder()))
    with AgentxClient("t", http_client=injected):
        pass
    assert not injected.is_closed

    owned = AgentxClient("t")
    owned.close()
    assert owned._transport.http.is_closed
