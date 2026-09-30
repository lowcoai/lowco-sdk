"""Every manager / kb endpoint: verb, path, query, body, envelope handling (sync + async)."""

from __future__ import annotations

import inspect
import json
from dataclasses import dataclass, field
from typing import Any

import httpx
import pytest

from lowcoai.agentx import AgentxClient, AsyncAgentxClient, KBClient, ManagerClient

M = "/v1/agentx/manager"
K = "/v1/agentx/kb"

LIST_KW = {"page_no": 2, "size": 25, "filter": "name eq 'bot'", "sort": "-createdAt"}
LIST_Q = {"pageNo": "2", "size": "25", "filter": "name eq 'bot'", "sort": "-createdAt"}

NO_BODY: Any = object()


@dataclass
class Case:
    sub: str
    name: str
    args: tuple[Any, ...]
    method: str
    path: str
    kwargs: dict[str, Any] = field(default_factory=dict)
    body: Any = NO_BODY
    query: dict[str, str] = field(default_factory=dict)
    reply: Any = None
    """JSON sent back inside the ``{"success": true, "data": ...}`` envelope."""
    raw_reply: Any = NO_BODY
    """JSON sent back as-is (non-enveloped endpoints)."""
    text_reply: str | None = None
    """Non-JSON body sent back (void endpoints must tolerate it)."""
    expected: Any = None

    @property
    def id(self) -> str:
        return f"{self.sub}.{self.name}"

    def response(self) -> httpx.Response:
        if self.text_reply is not None:
            return httpx.Response(200, text=self.text_reply)
        if self.raw_reply is not NO_BODY:
            return httpx.Response(200, json=self.raw_reply)
        return httpx.Response(200, json={"success": True, "data": self.reply})


AGENT = {"id": "a1", "name": "bot", "modelName": "gpt-4o", "tags": ["x"]}
PUBLISH = {"id": "p1", "agentId": "a1", "category": "sales"}
MODEL = {"id": "m1", "name": "gpt-4o", "provider": "openai"}
CONV = {"id": "c1", "chatType": "chat"}
KB = {"id": "k1", "name": "docs", "modelId": "m1"}
DS = {"id": "d1", "knowledgeBaseId": "k1", "content": "hello"}

CASES = [
    # --- manager: health / agents
    Case("manager", "health", (), "GET", "/health", text_reply="OK"),
    Case("manager", "list_agents", (), "GET", f"{M}/agents", kwargs=LIST_KW, query=LIST_Q,
         reply=[AGENT], expected=[AGENT]),
    Case("manager", "get_agent", ("a1",), "GET", f"{M}/agents/a1", reply=AGENT, expected=AGENT),
    Case("manager", "create_agent", ({"name": "bot"},), "POST", f"{M}/agents",
         body={"name": "bot"}, reply=AGENT, expected=AGENT),
    Case("manager", "update_agent", ("a1", {"name": "bot2"}), "PUT", f"{M}/agents/a1",
         body={"name": "bot2"}, reply=AGENT, expected=AGENT),
    Case("manager", "patch_agent", ("a1", {"tags": ["x"]}), "PATCH", f"{M}/agents/a1",
         body={"tags": ["x"]}, reply=AGENT, expected=AGENT),
    Case("manager", "get_agent_count", (), "GET", f"{M}/agents/count", kwargs=LIST_KW,
         query=LIST_Q, raw_reply=42, expected=42),
    Case("manager", "delete_agent", ("a1",), "DELETE", f"{M}/agents/a1", text_reply="deleted"),
    Case("manager", "bulk_delete_agents", (["a1", "a2"],), "POST", f"{M}/agents/bulk-delete",
         body={"ids": ["a1", "a2"]}, raw_reply={"deleted": 2}),
    Case("manager", "get_agent_versions", ("a1",), "GET", f"{M}/agents/a1/versions",
         kwargs={"size": 5}, query={"size": "5"}, reply=[{"id": "h1", "agent": AGENT}],
         expected=[{"id": "h1", "agent": AGENT}]),
    # --- manager: published agents
    Case("manager", "publish_agent", ("a1", {"category": "sales"}), "POST",
         f"{M}/agents/a1/publish", body={"category": "sales"}, reply=PUBLISH, expected=PUBLISH),
    Case("manager", "get_published_agent", ("p1",), "GET", f"{M}/agents/published/p1",
         reply=PUBLISH, expected=PUBLISH),
    Case("manager", "update_published_agent", ("p1", {"longDescription": "x", "agentId": "a1"}),
         "PUT", f"{M}/agents/published/p1", body={"longDescription": "x", "agentId": "a1"},
         reply=PUBLISH, expected=PUBLISH),
    Case("manager", "delete_published_agent", ("p1",), "DELETE", f"{M}/agents/published/p1"),
    Case("manager", "list_published_agents", (), "GET", f"{M}/agents/published",
         reply=[PUBLISH], expected=[PUBLISH]),
    # --- manager: models
    Case("manager", "create_model", (MODEL,), "POST", f"{M}/models", body=MODEL, reply=MODEL,
         expected=MODEL),
    Case("manager", "get_model", ("m1",), "GET", f"{M}/models/m1", reply=MODEL, expected=MODEL),
    Case("manager", "update_model", ("m1", MODEL), "PUT", f"{M}/models/m1", body=MODEL,
         reply=MODEL, expected=MODEL),
    Case("manager", "list_models", (), "GET", f"{M}/models", kwargs={"filter": "embedding"},
         query={"filter": "embedding"}, reply=[MODEL], expected=[MODEL]),
    Case("manager", "delete_model", ("m1",), "DELETE", f"{M}/models/m1"),
    Case("manager", "enable_model", ("m1", {"apiKey": "k", "n": 1}), "PATCH",
         f"{M}/models/m1/enable", body={"properties": {"apiKey": "k", "n": 1}}, reply=MODEL,
         expected=MODEL),
    Case("manager", "disable_model", ("m1",), "PATCH", f"{M}/models/m1/disable",
         reply={**MODEL, "disabled": True}, expected={**MODEL, "disabled": True}),
    # --- manager: conversations
    Case("manager", "list_conversations_by_agent", ("a1",), "GET", f"{M}/conversations/a1",
         kwargs={"page_no": 1}, query={"pageNo": "1"}, reply=[CONV], expected=[CONV]),
    Case("manager", "create_conversation", ("a1",), "POST", f"{M}/conversations",
         body={"agentId": "a1"}, reply=CONV, expected=CONV),
    Case("manager", "delete_conversation", ("c1",), "DELETE", f"{M}/conversations/c1"),
    Case("manager", "get_conversation_messages", ("c1",), "GET",
         f"{M}/conversations/c1/messages",
         reply=[{"id": "m1", "role": "user", "content": [{"type": "text", "text": "hi"}]}],
         expected=[{"id": "m1", "role": "user", "content": [{"type": "text", "text": "hi"}]}]),
    # --- kb: health / knowledge bases
    Case("kb", "health", (), "GET", "/health", raw_reply={"status": "ok"}),
    Case("kb", "list_knowledge_bases", (), "GET", f"{K}/knowledges", kwargs=LIST_KW,
         query=LIST_Q, reply=[KB], expected=[KB]),
    Case("kb", "create_knowledge_base", (KB,), "POST", f"{K}/knowledges", body=KB, reply=KB,
         expected=KB),
    Case("kb", "get_knowledge_base", ("k1",), "GET", f"{K}/knowledges/k1", reply=KB,
         expected=KB),
    Case("kb", "update_knowledge_base", ("k1", KB), "PUT", f"{K}/knowledges/k1", body=KB,
         reply=KB, expected=KB),
    Case("kb", "get_knowledge_base_count", (), "GET", f"{K}/knowledges/count",
         kwargs={"filter": "x"}, query={"filter": "x"}, raw_reply=3, expected=3),
    # --- kb: datasets
    Case("kb", "list_datasets", (), "GET", f"{K}/datasets", kwargs={"sort": "name"},
         query={"sort": "name"}, reply=[DS], expected=[DS]),
    Case("kb", "create_dataset", (DS,), "POST", f"{K}/datasets", body=DS, reply=DS, expected=DS),
    Case("kb", "get_dataset", ("d1",), "GET", f"{K}/datasets/d1", reply=DS, expected=DS),
    Case("kb", "update_dataset", ("d1", DS), "PUT", f"{K}/datasets/d1", body=DS, reply=DS,
         expected=DS),
    Case("kb", "delete_dataset", ("d1",), "DELETE", f"{K}/datasets/d1", text_reply=""),
    Case("kb", "get_dataset_count", (), "GET", f"{K}/datasets/count", raw_reply=0, expected=0),
    # --- kb: embeddings
    Case("kb", "store_embeddings",
         ({"modelId": "m1", "texts": "hello", "collection": "docs", "distance": "Cosine"},),
         "POST", f"{K}/embeddings",
         body={"modelId": "m1", "texts": "hello", "collection": "docs", "distance": "Cosine"},
         reply="embeddings stored", expected="embeddings stored"),
]  # fmt: skip


class Recorder:
    def __init__(self, case: Case) -> None:
        self.case = case
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self.case.response()

    def check(self) -> None:
        assert len(self.requests) == 1
        req, case = self.requests[0], self.case
        assert req.method == case.method
        assert req.url.scheme == "https"
        assert req.url.host == "api.lowco.ai"
        assert req.url.path == case.path
        assert dict(req.url.params) == case.query
        assert req.headers["Authorization"] == "Bearer tok_123"
        assert req.headers["X-Org-Id"] == "org_1"
        assert req.headers["Accept"] == "application/json"
        if case.body is NO_BODY:
            assert req.content == b""
            assert "Content-Type" not in req.headers
        else:
            assert req.headers["Content-Type"] == "application/json"
            assert json.loads(req.content) == case.body


@pytest.mark.parametrize("case", CASES, ids=lambda c: c.id)
def test_sync_endpoint(case: Case) -> None:
    rec = Recorder(case)
    client = AgentxClient(
        "tok_123", org_id="org_1", http_client=httpx.Client(transport=httpx.MockTransport(rec))
    )
    result = getattr(getattr(client, case.sub), case.name)(*case.args, **case.kwargs)
    assert result == case.expected
    rec.check()


@pytest.mark.parametrize("case", CASES, ids=lambda c: c.id)
async def test_async_endpoint(case: Case) -> None:
    rec = Recorder(case)
    client = AsyncAgentxClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(rec)),
    )
    result = await getattr(getattr(client, case.sub), case.name)(*case.args, **case.kwargs)
    assert result == case.expected
    rec.check()


@pytest.mark.parametrize(("sub", "cls"), [("manager", ManagerClient), ("kb", KBClient)])
def test_table_covers_every_public_method(sub: str, cls: type) -> None:
    public = {name for name, _ in inspect.getmembers(cls, inspect.isfunction)}
    public = {name for name in public if not name.startswith("_")}
    assert public == {c.name for c in CASES if c.sub == sub}


def test_list_methods_send_no_query_by_default() -> None:
    rec = Recorder(Case("manager", "list_agents", (), "GET", f"{M}/agents", reply=[]))
    client = AgentxClient(
        "tok_123", org_id="org_1", http_client=httpx.Client(transport=httpx.MockTransport(rec))
    )
    assert client.manager.list_agents() == []
    rec.check()
    assert rec.requests[0].url.query == b""
