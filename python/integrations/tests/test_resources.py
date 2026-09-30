"""Every resource method: verb, path (with encoded ids), JSON body and query.

The same table drives the sync client and the asyncio client.
"""

from __future__ import annotations

import inspect
import json
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

import httpx
import pytest

from lowcoai.integrations import AsyncIntegrationsClient, IntegrationsClient

NO_BODY = object()
ID = "a/b c"  # every path id is URL-encoded
E = "a%2Fb%20c"
DATA = {"id": "x1", "ok": True}
P = "/v1/integrations"

APP: dict[str, Any] = {"name": "Slack", "type": "http", "subType": "oauth2", "tags": ["chat"]}
ACTION: dict[str, Any] = {
    "applicationId": "app_1",
    "name": "Send message",
    "action": {"type": "http", "metadata": {"method": "POST"}},
}
RUN: dict[str, Any] = {"credentialId": "conn_1", "inputBody": {"to": "#general"}}
CONN: dict[str, Any] = {"name": "Sales", "connectionType": "oauth2", "applicationId": "app_1"}
TRIGGER: dict[str, Any] = {"name": "New row", "applicationId": "app_1", "operationConfig": {}}
FOLDER: dict[str, Any] = {"name": "root", "item": [{"name": "Send", "request": {"method": "POST"}}]}
RPC: dict[str, Any] = {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}


@dataclass(frozen=True)
class Case:
    name: str  # "<resource attr>.<method>[variant]"
    call: Callable[[Any], Any]
    method: str
    path: str
    body: Any = NO_BODY
    query: dict[str, str] = field(default_factory=dict)
    void: bool = False


CASES: list[Case] = [
    # applications
    Case("applications.list", lambda c: c.applications.list(), "GET", f"{P}/applications"),
    Case(
        "applications.list[query]",
        lambda c: c.applications.list(
            {
                "page": 1,
                "limit": 20,
                "sortBy": "name",
                "sortOrder": "asc",
                "filter": "f",
                "tags": "crm,sales",
            }
        ),
        "GET",
        f"{P}/applications",
        query={
            "page": "1",
            "limit": "20",
            "sortBy": "name",
            "sortOrder": "asc",
            "filter": "f",
            "tags": "crm,sales",
        },
    ),
    Case(
        "applications.list[open-ended]",
        lambda c: c.applications.list({"type": "http", "active": True, "skip": None}),
        "GET",
        f"{P}/applications",
        query={"type": "http", "active": "true"},
    ),
    Case(
        "applications.get_by_id",
        lambda c: c.applications.get_by_id(ID),
        "GET",
        f"{P}/applications/{E}",
    ),
    Case(
        "applications.create",
        lambda c: c.applications.create(APP),
        "POST",
        f"{P}/applications",
        APP,
    ),
    Case(
        "applications.update",
        lambda c: c.applications.update(ID, APP),
        "PUT",
        f"{P}/applications/{E}",
        APP,
    ),
    Case(
        "applications.delete",
        lambda c: c.applications.delete(ID),
        "DELETE",
        f"{P}/applications/{E}",
        void=True,
    ),
    Case(
        "applications.patch_tags",
        lambda c: c.applications.patch_tags(ID, ["crm", "sales"]),
        "PATCH",
        f"{P}/applications/{E}/tags",
        {"tags": ["crm", "sales"]},
    ),
    Case(
        "applications.run",
        lambda c: c.applications.run(ID, RUN),
        "POST",
        f"{P}/applications/{E}/run",
        RUN,
    ),
    Case(
        "applications.load_actions",
        lambda c: c.applications.load_actions(ID, FOLDER),
        "POST",
        f"{P}/applications/{E}/load-actions",
        FOLDER,
    ),
    Case(
        "applications.versions",
        lambda c: c.applications.versions(ID, {"page": 2}),
        "GET",
        f"{P}/applications/{E}/versions",
        query={"page": "2"},
    ),
    Case(
        "applications.regenerate_mcp_key",
        lambda c: c.applications.regenerate_mcp_key(ID),
        "GET",
        f"{P}/applications/{E}/regenerate-mcp-key",
    ),
    Case(
        "applications.get_mcp_tools",
        lambda c: c.applications.get_mcp_tools(ID),
        "GET",
        f"{P}/applications/{E}/mcp/tools",
    ),
    Case(
        "applications.get_sub_applications",
        lambda c: c.applications.get_sub_applications(),
        "GET",
        f"{P}/applications/types",
    ),
    Case(
        "applications.get_applications_with_triggers",
        lambda c: c.applications.get_applications_with_triggers(),
        "GET",
        f"{P}/applications/by-trigger",
    ),
    # actions
    Case(
        "actions.list",
        lambda c: c.actions.list({"limit": 50}),
        "GET",
        f"{P}/actions",
        query={"limit": "50"},
    ),
    Case("actions.get_by_id", lambda c: c.actions.get_by_id(ID), "GET", f"{P}/actions/{E}"),
    Case(
        "actions.create",
        lambda c: c.actions.create(ID, ACTION),
        "POST",
        f"{P}/applications/{E}/action",
        ACTION,
    ),
    Case(
        "actions.update", lambda c: c.actions.update(ID, ACTION), "PUT", f"{P}/actions/{E}", ACTION
    ),
    Case(
        "actions.delete",
        lambda c: c.actions.delete(ID),
        "DELETE",
        f"{P}/actions/{E}",
        void=True,
    ),
    Case(
        "actions.list_by_application",
        lambda c: c.actions.list_by_application(ID),
        "GET",
        f"{P}/applications/{E}/actions",
    ),
    Case("actions.run", lambda c: c.actions.run(ID, RUN), "POST", f"{P}/actions/{E}/run", RUN),
    Case(
        "actions.resolve_credentials",
        lambda c: c.actions.resolve_credentials(["a1", "a2"]),
        "POST",
        f"{P}/actions/allCredential",
        ["a1", "a2"],
    ),
    # connections
    Case("connections.list", lambda c: c.connections.list(), "GET", f"{P}/connections"),
    Case(
        "connections.get_by_id",
        lambda c: c.connections.get_by_id(ID),
        "GET",
        f"{P}/connections/{E}",
    ),
    Case(
        "connections.create", lambda c: c.connections.create(CONN), "POST", f"{P}/connections", CONN
    ),
    Case(
        "connections.update",
        lambda c: c.connections.update(ID, CONN),
        "PUT",
        f"{P}/connections/{E}",
        CONN,
    ),
    Case(
        "connections.delete",
        lambda c: c.connections.delete(ID),
        "DELETE",
        f"{P}/connections/{E}",
        void=True,
    ),
    Case(
        "connections.list_by_application",
        lambda c: c.connections.list_by_application(ID),
        "GET",
        f"{P}/applications/{E}/connections",
    ),
    Case(
        "connections.set_as_default",
        lambda c: c.connections.set_as_default(ID, "app_1"),
        "PATCH",
        f"{P}/connections/{E}/setDefault",
        {"applicationId": "app_1"},
    ),
    # triggers
    Case(
        "triggers.list_by_application",
        lambda c: c.triggers.list_by_application(ID),
        "GET",
        f"{P}/applications/{E}/triggers",
    ),
    Case(
        "triggers.list_by_application[query]",
        lambda c: c.triggers.list_by_application(ID, {"page": 1, "limit": 5}),
        "GET",
        f"{P}/applications/{E}/triggers",
        query={"page": "1", "limit": "5"},
    ),
    Case("triggers.get_by_id", lambda c: c.triggers.get_by_id(ID), "GET", f"{P}/triggers/{E}"),
    Case("triggers.create", lambda c: c.triggers.create(TRIGGER), "POST", f"{P}/triggers", TRIGGER),
    Case(
        "triggers.update",
        lambda c: c.triggers.update(ID, TRIGGER),
        "PUT",
        f"{P}/triggers/{E}",
        TRIGGER,
    ),
    Case(
        "triggers.delete",
        lambda c: c.triggers.delete(ID),
        "DELETE",
        f"{P}/triggers/{E}",
        void=True,
    ),
    Case(
        "triggers.get_state", lambda c: c.triggers.get_state(ID), "GET", f"{P}/triggers/{E}/state"
    ),
    # oauth
    Case(
        "oauth.login",
        lambda c: c.oauth.login(ID, {"applicationId": "app_1", "name": "Sales"}),
        "POST",
        f"{P}/oauth/{E}/login",
        {"applicationId": "app_1", "name": "Sales"},
    ),
    Case(
        "oauth.callback",
        lambda c: c.oauth.callback({"state": "s", "code": "c"}),
        "POST",
        f"{P}/oauth/callback",
        {"state": "s", "code": "c"},
    ),
    Case(
        "oauth.get_token_by_credential_id",
        lambda c: c.oauth.get_token_by_credential_id(ID),
        "GET",
        f"{P}/connections/{E}/token",
    ),
    Case(
        "oauth.refresh_token_by_credential_id",
        lambda c: c.oauth.refresh_token_by_credential_id(ID),
        "POST",
        f"{P}/connections/{E}/token/refresh",
    ),
    Case(
        "oauth.refresh_expiring_tokens",
        lambda c: c.oauth.refresh_expiring_tokens(),
        "POST",
        f"{P}/oauth/tokens/refresh-expiring",
    ),
    # configurations
    Case("configurations.get", lambda c: c.configurations.get(), "GET", f"{P}/configurations"),
    # mcp
    Case(
        "mcp.call_published",
        lambda c: c.mcp.call_published(ID, RPC),
        "POST",
        f"{P}/applications/published/{E}",
        RPC,
    ),
    Case(
        "mcp.info_published",
        lambda c: c.mcp.info_published(ID),
        "GET",
        f"{P}/applications/published/{E}",
    ),
]


def _handler(seen: list[httpx.Request]) -> Callable[[httpx.Request], httpx.Response]:
    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"success": True, "data": DATA})

    return handle


def _check(case: Case, seen: list[httpx.Request], result: Any) -> None:
    assert len(seen) == 1
    req = seen[0]
    assert req.method == case.method
    assert req.url.host == "api.lowco.ai"
    assert req.url.raw_path.decode().split("?")[0] == case.path
    assert dict(req.url.params) == case.query
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    if case.body is NO_BODY:
        assert req.content == b""
        assert "Content-Type" not in req.headers
    else:
        assert req.headers["Content-Type"] == "application/json"
        assert json.loads(req.content) == case.body
    assert result == (None if case.void else DATA)


@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
def test_sync_resource_call(case: Case) -> None:
    seen: list[httpx.Request] = []
    http = httpx.Client(transport=httpx.MockTransport(_handler(seen)))
    with IntegrationsClient("tok_123", org_id="org_1", http_client=http) as client:
        result = case.call(client)
    _check(case, seen, result)


@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
async def test_async_resource_call(case: Case) -> None:
    seen: list[httpx.Request] = []
    http = httpx.AsyncClient(transport=httpx.MockTransport(_handler(seen)))
    async with AsyncIntegrationsClient("tok_123", org_id="org_1", http_client=http) as client:
        pending = case.call(client)
        assert inspect.iscoroutine(pending)
        result = await pending
    _check(case, seen, result)


def test_table_covers_every_resource_method() -> None:
    client = IntegrationsClient("tok")
    expected = {
        f"{attr}.{name}"
        for attr, resource in vars(client).items()
        if not attr.startswith("_")
        for name, _ in inspect.getmembers(resource, inspect.ismethod)
        if not name.startswith("_")
    }
    covered = {case.name.split("[")[0] for case in CASES}
    assert covered == expected
    assert len(expected) == 42
