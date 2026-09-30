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

from lowcoai.workflow import AsyncWorkflowClient, WorkflowClient

NO_BODY = object()
ID = "a/b c"  # every path id is URL-encoded
E = "a%2Fb%20c"
DATA = {"id": "x1", "ok": True}

WF: dict[str, Any] = {"name": "Onboarding", "ui": {"nodes": [], "edges": []}}
ENV: dict[str, Any] = {"name": "prod", "variables": [{"name": "K", "value": "V"}]}
FN: dict[str, Any] = {"name": "double", "body": "return x * 2"}
PUB: dict[str, Any] = {"category": "sales", "longDescription": "Lead routing"}
DRY: dict[str, Any] = {
    "executionId": "exe_1",
    "expression": "{{ $.input.a }}",
    "typeOfExpression": "string",
    "activityId": "act_1",
}


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
    # workflows
    Case("workflows.list", lambda c: c.workflows.list(), "GET", "/v1/wf/workflows"),
    Case(
        "workflows.list[query]",
        lambda c: c.workflows.list(
            {"page": 2, "limit": 20, "sortBy": "name", "sortOrder": "desc", "where": "x"}
        ),
        "GET",
        "/v1/wf/workflows",
        query={"page": "2", "limit": "20", "sortBy": "name", "sortOrder": "desc", "where": "x"},
    ),
    Case(
        "workflows.list[open-ended]",
        lambda c: c.workflows.list({"page": 1, "published": False, "tags": ["a"], "q": None}),
        "GET",
        "/v1/wf/workflows",
        query={"page": "1", "published": "false", "tags": '["a"]'},
    ),
    Case(
        "workflows.count",
        lambda c: c.workflows.count({"where": "w"}),
        "GET",
        "/v1/wf/workflows/count",
        query={"where": "w"},
    ),
    Case(
        "workflows.get_by_id", lambda c: c.workflows.get_by_id(ID), "GET", f"/v1/wf/workflows/{E}"
    ),
    Case("workflows.create", lambda c: c.workflows.create(WF), "POST", "/v1/wf/workflows", WF),
    Case(
        "workflows.update",
        lambda c: c.workflows.update(ID, {**WF, "comment": "v2"}),
        "PUT",
        f"/v1/wf/workflows/{E}",
        {**WF, "comment": "v2"},
    ),
    Case(
        "workflows.delete",
        lambda c: c.workflows.delete(ID),
        "DELETE",
        f"/v1/wf/workflows/{E}",
        void=True,
    ),
    Case(
        "workflows.run",
        lambda c: c.workflows.run({"workflowId": "wf_1", "inputData": {"a": 1}}),
        "POST",
        "/v1/wf/workflows/run",
        {"workflowId": "wf_1", "inputData": {"a": 1}},
    ),
    Case(
        "workflows.versions",
        lambda c: c.workflows.versions(ID, {"page": 1}),
        "GET",
        f"/v1/wf/workflows/{E}/versions",
        query={"page": "1"},
    ),
    Case(
        "workflows.publish",
        lambda c: c.workflows.publish(ID, PUB),
        "POST",
        f"/v1/wf/workflows/{E}/publish",
        PUB,
    ),
    Case(
        "workflows.published",
        lambda c: c.workflows.published({"limit": 5}),
        "GET",
        "/v1/wf/workflows/published",
        query={"limit": "5"},
    ),
    Case(
        "workflows.published_count",
        lambda c: c.workflows.published_count(),
        "GET",
        "/v1/wf/workflows/published/count",
    ),
    Case(
        "workflows.get_published_by_id",
        lambda c: c.workflows.get_published_by_id(ID),
        "GET",
        f"/v1/wf/workflows/published/{E}",
    ),
    Case(
        "workflows.update_published",
        lambda c: c.workflows.update_published(ID, PUB),
        "PUT",
        f"/v1/wf/workflows/published/{E}",
        PUB,
    ),
    Case(
        "workflows.delete_published",
        lambda c: c.workflows.delete_published(ID),
        "DELETE",
        f"/v1/wf/workflows/published/{E}",
        void=True,
    ),
    Case(
        "workflows.web_published",
        lambda c: c.workflows.web_published({"page": 1}),
        "GET",
        "/v1/wf/workflows/published/web",
        query={"page": "1"},
    ),
    Case(
        "workflows.web_published_by_id",
        lambda c: c.workflows.web_published_by_id(ID),
        "GET",
        f"/v1/wf/workflows/published/web/{E}",
    ),
    Case(
        "workflows.search_published_templates",
        lambda c: c.workflows.search_published_templates(q="crm", category="sales", limit=5),
        "GET",
        "/v1/wf/workflows/published/web/search",
        query={"q": "crm", "category": "sales", "limit": "5"},
    ),
    Case(
        "workflows.search_published_templates[partial]",
        lambda c: c.workflows.search_published_templates(q="crm"),
        "GET",
        "/v1/wf/workflows/published/web/search",
        query={"q": "crm"},
    ),
    # environments
    Case(
        "environments.list",
        lambda c: c.environments.list({"page": 1}),
        "GET",
        "/v1/wf/environments",
        query={"page": "1"},
    ),
    Case(
        "environments.get_by_id",
        lambda c: c.environments.get_by_id(ID),
        "GET",
        f"/v1/wf/environments/{E}",
    ),
    Case(
        "environments.create",
        lambda c: c.environments.create(ENV),
        "POST",
        "/v1/wf/environments",
        ENV,
    ),
    Case(
        "environments.update",
        lambda c: c.environments.update(ID, ENV),
        "PUT",
        f"/v1/wf/environments/{E}",
        ENV,
    ),
    Case(
        "environments.delete",
        lambda c: c.environments.delete(ID),
        "DELETE",
        f"/v1/wf/environments/{E}",
        void=True,
    ),
    Case(
        "environments.set_default",
        lambda c: c.environments.set_default(ID),
        "PATCH",
        f"/v1/wf/environments/{E}/default",
    ),
    # functions
    Case("functions.list", lambda c: c.functions.list(), "GET", "/v1/wf/functions"),
    Case(
        "functions.get_by_id", lambda c: c.functions.get_by_id(ID), "GET", f"/v1/wf/functions/{E}"
    ),
    Case("functions.create", lambda c: c.functions.create(FN), "POST", "/v1/wf/functions", FN),
    Case(
        "functions.update",
        lambda c: c.functions.update(ID, {"function": FN, "comment": "faster"}),
        "PUT",
        f"/v1/wf/functions/{E}",
        {"function": FN, "comment": "faster"},
    ),
    Case(
        "functions.delete",
        lambda c: c.functions.delete(ID),
        "DELETE",
        f"/v1/wf/functions/{E}",
        void=True,
    ),
    Case(
        "functions.versions",
        lambda c: c.functions.versions(ID, {"limit": 3}),
        "GET",
        f"/v1/wf/functions/{E}/versions",
        query={"limit": "3"},
    ),
    Case(
        "functions.execute",
        lambda c: c.functions.execute(ID),
        "POST",
        f"/v1/wf/functions/{E}/execute",
        {},
    ),
    Case(
        "functions.execute[params]",
        lambda c: c.functions.execute(ID, {"x": 21}),
        "POST",
        f"/v1/wf/functions/{E}/execute",
        {"x": 21},
    ),
    # executions
    Case(
        "executions.list",
        lambda c: c.executions.list({"page": 1, "full": True}),
        "GET",
        "/v1/wf/executions",
        query={"page": "1", "full": "true"},
    ),
    Case(
        "executions.count",
        lambda c: c.executions.count({"where": "s"}),
        "GET",
        "/v1/wf/executions/count",
        query={"where": "s"},
    ),
    Case(
        "executions.get_by_id",
        lambda c: c.executions.get_by_id(ID),
        "GET",
        f"/v1/wf/executions/{E}",
    ),
    Case("executions.logs", lambda c: c.executions.logs(ID), "GET", f"/v1/wf/executions/{E}/logs"),
    # activities
    Case("activities.list", lambda c: c.activities.list(), "GET", "/v1/wf/activities"),
    Case(
        "activities.count",
        lambda c: c.activities.count({"page": 1}),
        "GET",
        "/v1/wf/activities/count",
        query={"page": "1"},
    ),
    Case(
        "activities.get_by_id",
        lambda c: c.activities.get_by_id(ID),
        "GET",
        f"/v1/wf/activities/{E}",
    ),
    Case("activities.logs", lambda c: c.activities.logs(ID), "GET", f"/v1/wf/activities/{E}/logs"),
    # human tasks
    Case(
        "human_tasks.list",
        lambda c: c.human_tasks.list({"page": 1, "limit": 10}),
        "GET",
        "/v1/wf/human-tasks",
        query={"page": "1", "limit": "10"},
    ),
    Case(
        "human_tasks.get_by_id",
        lambda c: c.human_tasks.get_by_id(ID),
        "GET",
        f"/v1/wf/human-tasks/{E}",
    ),
    Case(
        "human_tasks.complete",
        lambda c: c.human_tasks.complete(ID, "approve"),
        "PATCH",
        f"/v1/wf/human-tasks/{E}/complete",
        {"action": "approve"},
    ),
    # analytics
    Case("analytics.default", lambda c: c.analytics.default(), "GET", "/v1/wf/analytics"),
    Case(
        "analytics.get_by_id", lambda c: c.analytics.get_by_id(ID), "GET", f"/v1/wf/analytics/{E}"
    ),
    # dry run
    Case("dry_run.execute", lambda c: c.dry_run.execute(DRY), "POST", "/v1/wf/dryrun", DRY),
    # webhooks
    Case(
        "webhooks.trigger",
        lambda c: c.webhooks.trigger(ID),
        "POST",
        f"/v1/wf/webhook/{E}",
        {},
    ),
    Case(
        "webhooks.trigger[query]",
        lambda c: c.webhooks.trigger(
            ID, {"orderId": "o_1"}, env="prod", triggered_by="crm", async_=True
        ),
        "POST",
        f"/v1/wf/webhook/{E}",
        {"orderId": "o_1"},
        query={"env": "prod", "triggeredBy": "crm", "async": "true"},
    ),
    Case(
        "webhooks.trigger[sync]",
        lambda c: c.webhooks.trigger(ID, {"a": 1}, async_=False),
        "POST",
        f"/v1/wf/webhook/{E}",
        {"a": 1},
        query={"async": "false"},
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
    with WorkflowClient("tok_123", org_id="org_1", http_client=http) as client:
        result = case.call(client)
    _check(case, seen, result)


@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
async def test_async_resource_call(case: Case) -> None:
    seen: list[httpx.Request] = []
    http = httpx.AsyncClient(transport=httpx.MockTransport(_handler(seen)))
    async with AsyncWorkflowClient("tok_123", org_id="org_1", http_client=http) as client:
        pending = case.call(client)
        assert inspect.iscoroutine(pending)
        result = await pending
    _check(case, seen, result)


def test_table_covers_every_resource_method() -> None:
    client = WorkflowClient("tok")
    expected = {
        f"{attr}.{name}"
        for attr, resource in vars(client).items()
        if not attr.startswith("_")
        for name, _ in inspect.getmembers(resource, inspect.ismethod)
        if not name.startswith("_")
    }
    covered = {case.name.split("[")[0] for case in CASES}
    assert covered == expected
    assert len(expected) == 45


def test_webhooks_expose_only_the_trigger() -> None:
    # The orchestrator serves only POST /v1/wf/webhook/{id}, which runs the
    # workflow; a register/list/update/delete method there would misfire.
    for client in (WorkflowClient("tok"), AsyncWorkflowClient("tok")):
        public = {n for n in dir(client.webhooks) if not n.startswith("_")}
        assert public == {"trigger"}
