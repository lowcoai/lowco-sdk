from __future__ import annotations

import json
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

import httpx
import pytest

from lowcoai.lowcodb import HEADER_ORG_ID, LowcodbClient, LowcodbError


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


def make_client(rec: Recorder, **kwargs: Any) -> LowcodbClient:
    return LowcodbClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
        **kwargs,
    )


def test_token_is_required() -> None:
    with pytest.raises(ValueError):
        LowcodbClient("  ")


def test_sends_auth_org_and_default_headers() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec, default_headers={"X-Trace": "t1"})
    client.list_bases()
    req = rec.last
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers[HEADER_ORG_ID] == "org_1"
    assert req.headers["Accept"] == "application/json"
    assert req.headers["X-Trace"] == "t1"
    assert "Content-Type" not in req.headers
    assert str(req.url) == "https://api.lowco.ai/v1/lowcodb/bases"


def test_set_org_id_and_header() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec)
    client.set_org_id(None)
    client.set_header("X-Extra", "1")
    client.list_tables()
    assert HEADER_ORG_ID not in rec.last.headers
    assert rec.last.headers["X-Extra"] == "1"
    client.set_org_id("org_2")
    client.set_header("X-Extra", None)
    client.list_tables()
    assert rec.last.headers[HEADER_ORG_ID] == "org_2"
    assert "X-Extra" not in rec.last.headers


def test_unwraps_envelope_and_sends_json_body() -> None:
    rec = Recorder(lambda _r: envelope({"id": "b1", "name": "crm"}))
    client = make_client(rec)
    base = client.create_base({"name": "crm", "baseType": "internal"})
    assert base == {"id": "b1", "name": "crm"}
    assert rec.last.method == "POST"
    assert rec.last.headers["Content-Type"] == "application/json"
    assert rec.last_json() == {"name": "crm", "baseType": "internal"}


def test_null_data_and_empty_body_return_none() -> None:
    client = make_client(Recorder(lambda _r: envelope(None)))
    assert client.get_base("b1") is None
    client = make_client(Recorder(lambda _r: httpx.Response(204)))
    assert client.get_base("b1") is None


def test_list_params_are_sent_as_query() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec)
    client.list_records(
        "app_crm", "leads", page_no=2, size=50, filter="status='open'", sort="-createdAt"
    )
    url = rec.last.url
    assert url.path == "/v1/lowcodb/data/app_crm/tables/leads/records"
    assert dict(url.params) == {
        "pageNo": "2",
        "size": "50",
        "filter": "status='open'",
        "sort": "-createdAt",
    }


def test_path_segments_are_escaped() -> None:
    rec = Recorder(lambda _r: envelope({}))
    client = make_client(rec)
    client.get_record("my schema", "a/b", "id?1")
    assert rec.last.url.raw_path == b"/v1/lowcodb/data/my%20schema/tables/a%2Fb/records/id%3F1"


def test_base_url_and_api_base_path_overrides() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec, base_url="http://lowcodb-service:8080/", api_base_path="/api/")
    client.list_views()
    assert str(rec.last.url) == "http://lowcodb-service:8080/api/views"


def test_health_hits_root_and_accepts_plain_text() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, text="OK"))
    client = make_client(rec)
    client.health()
    assert str(rec.last.url) == "https://api.lowco.ai/health"


def test_delete_ignores_non_json_success_body() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, text="deleted"))
    client = make_client(rec)
    client.delete_trigger("t1")
    assert rec.last.method == "DELETE"
    assert rec.last.url.path == "/v1/lowcodb/triggers/t1"


def test_delete_bulk_records_sends_body() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.delete_bulk_records("app_crm", "leads", ["r1", "r2"])
    assert rec.last.method == "DELETE"
    assert rec.last_json() == ["r1", "r2"]


def test_export_returns_bytes() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, content=b"\x00collection"))
    client = make_client(rec)
    assert client.export_base_collection("b1") == b"\x00collection"
    assert rec.last.url.path == "/v1/lowcodb/bases/b1/export"


def test_validate_field_is_not_enveloped() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, json={"value": 1, "errors": []}))
    client = make_client(rec)
    assert client.validate_field({"value": 1, "dataType": "number"}) == {"value": 1, "errors": []}


def test_transaction_and_event_bodies() -> None:
    rec = Recorder(lambda _r: envelope({"results": []}))
    client = make_client(rec)
    client.execute_transaction(
        "app_crm", [{"type": "create", "table": "leads", "record": {"a": 1}}]
    )
    assert rec.last.url.path == "/v1/lowcodb/data/app_crm/transactions"
    assert rec.last_json() == {
        "operations": [{"type": "create", "table": "leads", "record": {"a": 1}}]
    }

    client.publish_event("app_crm", {"eventType": "lead.qualified", "tableName": "leads"})
    assert rec.last.url.path == "/v1/lowcodb/events/publish"
    assert rec.last_json() == {
        "schema": "app_crm",
        "eventType": "lead.qualified",
        "tableName": "leads",
    }


def test_functions_execute_and_invoke() -> None:
    rec = Recorder(lambda _r: envelope({"ok": True}))
    client = make_client(rec)
    client.execute_function("f1")
    assert rec.last_json() == {}
    assert rec.last.url.path == "/v1/lowcodb/functions/f1/execute"

    assert client.invoke_function("app_crm", "score-lead", method="GET") == {"ok": True}
    assert rec.last.method == "GET"
    assert rec.last.content == b""
    assert rec.last.url.path == "/v1/lowcodb/fn/app_crm/score-lead"

    client.invoke_function("app_crm", "score-lead", {"leadId": "l1"})
    assert rec.last.method == "POST"
    assert rec.last_json() == {"leadId": "l1"}


def test_dashboard_dates_are_iso_utc() -> None:
    rec = Recorder(lambda _r: envelope({}))
    client = make_client(rec)
    client.get_metrics_dashboard(
        range="24h",
        from_=datetime(2026, 1, 2, 3, 4, 5, 678000, tzinfo=timezone.utc),
        to=datetime(2026, 1, 3),
        base_id="b1",
    )
    assert dict(rec.last.url.params) == {
        "range": "24h",
        "from": "2026-01-02T03:04:05.678Z",
        "to": "2026-01-03T00:00:00.000Z",
        "baseId": "b1",
    }


def test_refresh_view_body() -> None:
    rec = Recorder(lambda _r: envelope({"status": "ok"}))
    client = make_client(rec)
    assert client.refresh_view("v1", concurrent=True) == {"status": "ok"}
    assert rec.last_json() == {"concurrent": True}


# --- errors ------------------------------------------------------------------


def test_error_prefers_details_over_opaque_platform_code() -> None:
    body = {"error": {"code": 500, "message": "AAS-00105", "details": "lead score must be > 0"}}
    client = make_client(Recorder(lambda _r: httpx.Response(500, json=body)))
    with pytest.raises(LowcodbError) as info:
        client.invoke_function("app_crm", "score-lead", {})
    err = info.value
    assert err.status_code == 500
    assert err.message == "lead score must be > 0"
    assert err.code == 500
    assert "AAS-00105" in err.body


def test_error_keeps_human_message() -> None:
    body = {"error": {"code": "NOT_FOUND", "message": "base not found", "details": "x"}}
    client = make_client(Recorder(lambda _r: httpx.Response(404, json=body)))
    with pytest.raises(LowcodbError) as info:
        client.get_base("missing")
    assert info.value.message == "base not found"
    assert info.value.code == "NOT_FOUND"


def test_error_falls_back_to_top_level_message_and_raw_text() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(400, json={"message": "bad"})))
    with pytest.raises(LowcodbError) as info:
        client.list_bases()
    assert info.value.message == "bad"
    assert info.value.code is None

    client = make_client(Recorder(lambda _r: httpx.Response(502, text=" upstream down ")))
    with pytest.raises(LowcodbError) as info:
        client.list_bases()
    assert info.value.message == "upstream down"
    assert info.value.status_code == 502

    client = make_client(Recorder(lambda _r: httpx.Response(503, text="")))
    with pytest.raises(LowcodbError) as info:
        client.delete_base("b1")
    assert info.value.message == "lowcodb: status=503"


def test_invalid_json_success_raises_lowcodb_error() -> None:
    client = make_client(Recorder(lambda _r: httpx.Response(200, text="<html>")))
    with pytest.raises(LowcodbError) as info:
        client.get_base("b1")
    assert info.value.status_code == 200
    assert info.value.body == "<html>"


def test_owned_http_client_closes_but_injected_does_not() -> None:
    injected = httpx.Client(transport=httpx.MockTransport(Recorder()))
    with LowcodbClient("t", http_client=injected):
        pass
    assert not injected.is_closed

    owned = LowcodbClient("t")
    owned.close()
    assert owned._http.is_closed
