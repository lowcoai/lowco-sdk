"""track_batch, alias, merge, set_consent and enter_journey (sync and async)."""

from __future__ import annotations

import json
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

import httpx
import pytest

from lowcoai.engage import (
    ALIAS_ANONYMOUS,
    ALIAS_EMAIL,
    CONSENT_OPTED_IN,
    CONSENT_OPTED_OUT,
    MAX_BATCH,
    AsyncEngageClient,
    EngageClient,
    EngageError,
)

FIXED = datetime(2026, 9, 30, 12, 34, 56, 789123, tzinfo=timezone.utc)

BATCH_ANSWER = {
    "status": 1,
    "data": {
        "accepted": 2,
        "rejected": 1,
        "results": [
            {"index": 0, "eventName": "a", "ok": True},
            {"index": 1, "eventName": "b", "ok": True},
            {
                "index": 2,
                "eventName": "order",
                "ok": False,
                "error": "breaks its strict event definition",
                "issues": [
                    {"property": "total", "kind": "type", "expected": "number", "got": "string"}
                ],
            },
        ],
    },
}


class Recorder:
    """Captures requests and answers each with a canned response."""

    def __init__(self, respond: Callable[[httpx.Request], httpx.Response] | None = None) -> None:
        self.requests: list[httpx.Request] = []
        self._respond = respond or (lambda _req: httpx.Response(200, json={"status": 1}))

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self._respond(request)

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]

    def last_json(self) -> Any:
        return json.loads(self.last.content)


def answer(status: int, data: Any) -> Callable[[httpx.Request], httpx.Response]:
    return lambda _req: httpx.Response(status, json={"status": 1, "data": data})


def make_client(rec: Recorder, api_key: str = "lc_admin", **kwargs: Any) -> EngageClient:
    return EngageClient(
        api_key,
        "org_1",
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
        **kwargs,
    )


def test_base_url_defaults_and_trailing_slash() -> None:
    assert EngageClient("k", "o").base_url == "https://api.lowco.ai"
    rec = Recorder()
    client = make_client(rec, base_url=" https://staging.example/ ")
    assert client.base_url == "https://staging.example"
    client.track("x")
    assert str(rec.last.url) == "https://staging.example/v1/engage/track"


def test_build_event_matches_track() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="dev_1")
    event = client.build_event("checkout", {"total": 12.5}, user_id="u1", event_time=FIXED)
    client.track("checkout", {"total": 12.5}, user_id="u1", event_time=FIXED)
    assert event == rec.last_json()
    with pytest.raises(ValueError):
        client.build_event(" ")


def test_track_batch_posts_events_and_returns_rows() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, json=BATCH_ANSWER))
    client = make_client(rec, device_id="dev_1", app_id="app_9")
    events = [
        client.build_event("a", {"q": "<b>"}, event_time=FIXED),
        client.build_event("b", event_time=FIXED),
        client.build_event("order", {"total": "12"}, user_id="u1", event_time=FIXED),
    ]
    result = client.track_batch(events)
    req = rec.last
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/engage/track/batch"
    assert req.headers["X-Api-Key"] == "lc_admin"
    assert "Authorization" not in req.headers
    assert req.headers["X-Org-Id"] == "org_1"
    assert req.headers["X-Engage-App-Id"] == "app_9"
    assert req.headers["Content-Type"] == "application/json"
    assert req.content == (
        '{"events":['
        '{"id":"","event_name":"a","event_data":{"q":"<b>"},"device_id":"dev_1",'
        '"event_time":"2026-09-30T12:34:56.789Z"},'
        '{"id":"","event_name":"b","event_data":{},"device_id":"dev_1",'
        '"event_time":"2026-09-30T12:34:56.789Z"},'
        '{"id":"","event_name":"order","event_data":{"total":"12"},"user_id":"u1",'
        '"device_id":"dev_1","event_time":"2026-09-30T12:34:56.789Z"}]}'
    ).encode()
    assert result["accepted"] == 2
    assert result["rejected"] == 1
    assert [row["ok"] for row in result["results"]] == [True, True, False]
    assert result["results"][2]["issues"][0]["property"] == "total"


def test_track_batch_limits_send_nothing() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, json=BATCH_ANSWER))
    client = make_client(rec)
    with pytest.raises(ValueError):
        client.track_batch([])
    too_many = [client.build_event("x") for _ in range(MAX_BATCH + 1)]
    with pytest.raises(ValueError):
        client.track_batch(too_many)
    with pytest.raises(ValueError):
        client.track_batch([client.build_event("x", {"bad": float("nan")})])
    assert rec.requests == []
    client.track_batch(too_many[:MAX_BATCH])
    assert len(json.loads(rec.last.content)["events"]) == MAX_BATCH


def test_track_batch_refused_whole() -> None:
    body = {"status": 0, "error": {"message": "AAS-00413", "code": 413, "details": "too many"}}
    rec = Recorder(lambda _r: httpx.Response(413, json=body))
    with pytest.raises(EngageError) as info:
        make_client(rec).track_batch([{"event_name": "x", "device_id": "d", "event_time": "t"}])
    assert info.value.status_code == 413
    assert info.value.message == "too many"


def test_alias() -> None:
    rec = Recorder(answer(200, {"claimed": True}))
    client = make_client(rec, api_key="eyJ.token")
    assert client.alias("u_1", ALIAS_EMAIL, "ana@example.in") == {"claimed": True}
    req = rec.last
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/engage/users/alias"
    assert req.headers["Authorization"] == "Bearer eyJ.token"
    assert "X-Engage-App-Id" not in req.headers
    assert rec.last_json() == {
        "userId": "u_1",
        "aliasType": "email",
        "aliasValue": "ana@example.in",
    }

    rec = Recorder(answer(200, {"claimed": False, "heldBy": "u_2"}))
    held = make_client(rec).alias("u_1", ALIAS_ANONYMOUS, "dev_9")
    assert held == {"claimed": False, "heldBy": "u_2"}


@pytest.mark.parametrize("status", [200, 202])
def test_merge_accepts_ok_and_accepted(status: int) -> None:
    profile = {"id": "p1", "appId": "app_1", "userId": "u_keep", "userMetadata": {"plan": "pro"}}
    rec = Recorder(answer(status, profile))
    kept = make_client(rec, app_id="app_1").merge("u_keep", "ana@example.in")
    assert kept == profile
    assert str(rec.last.url) == "https://api.lowco.ai/v1/engage/users/merge"
    assert rec.last.headers["X-Engage-App-Id"] == "app_1"
    assert rec.last_json() == {"keepUserId": "u_keep", "mergeUserId": "ana@example.in"}


def test_merge_missing_profile_is_404() -> None:
    body = {"status": 0, "error": {"message": "profile not found", "code": 404}}
    rec = Recorder(lambda _r: httpx.Response(404, json=body))
    with pytest.raises(EngageError) as info:
        make_client(rec).merge("a", "b")
    assert info.value.status_code == 404


def test_set_consent() -> None:
    result = {"channel": "whatsapp", "status": "opted_in", "previous": "pending"}
    rec = Recorder(answer(200, result))
    client = make_client(rec)
    got = client.set_consent(
        "u/1 ana", "whatsapp", CONSENT_OPTED_IN, source="form", evidence={"formId": "f1"}
    )
    assert got == result
    req = rec.last
    assert req.method == "PUT"
    assert req.url.raw_path == b"/v1/engage/users/userId/u%2F1%20ana/consents"
    assert rec.last_json() == {
        "channel": "whatsapp",
        "status": "opted_in",
        "source": "form",
        "evidence": {"formId": "f1"},
    }
    client.set_consent("u1", "email", CONSENT_OPTED_OUT)
    assert rec.last_json() == {"channel": "email", "status": "opted_out"}


def test_enter_journey() -> None:
    participant = {"id": "jp1", "journeyId": "j 1", "userId": "u1", "status": "active"}
    rec = Recorder(answer(201, participant))
    assert make_client(rec).enter_journey("j 1", "u1") == participant
    assert rec.last.method == "POST"
    assert rec.last.url.raw_path == b"/v1/engage/configurations/journeys/j%201/enter"
    assert rec.last_json() == {"userId": "u1"}


def test_enter_journey_conflict_is_409() -> None:
    body = {"status": 0, "error": {"message": "AAS-00409", "code": 409, "details": "already in"}}
    rec = Recorder(lambda _r: httpx.Response(409, json=body))
    with pytest.raises(EngageError) as info:
        make_client(rec).enter_journey("j1", "u1")
    assert info.value.status_code == 409
    assert info.value.message == "already in"


def test_blank_arguments_send_nothing() -> None:
    rec = Recorder()
    client = make_client(rec)
    calls: list[Callable[[], object]] = [
        lambda: client.alias(" ", ALIAS_EMAIL, "a@b.c"),
        lambda: client.alias("u1", "", "a@b.c"),
        lambda: client.alias("u1", ALIAS_EMAIL, " "),
        lambda: client.merge("u1", ""),
        lambda: client.set_consent("", "email", CONSENT_OPTED_IN),
        lambda: client.set_consent("u1", "email", ""),
        lambda: client.enter_journey("", "u1"),
        lambda: client.enter_journey("j1", " "),
    ]
    for call in calls:
        with pytest.raises(ValueError):
            call()
    assert rec.requests == []


def test_non_json_2xx_answer_raises_value_error() -> None:
    rec = Recorder(lambda _r: httpx.Response(200, text="not json"))
    with pytest.raises(ValueError):
        make_client(rec).alias("u1", ALIAS_EMAIL, "a@b.c")


# --- async -------------------------------------------------------------------


def make_async(handler: Any, **kwargs: Any) -> AsyncEngageClient:
    return AsyncEngageClient(
        "lc_admin",
        "org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        **kwargs,
    )


async def test_async_batch_and_profile_calls() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path = request.url.path
        if path.endswith("/track/batch"):
            return httpx.Response(200, json=BATCH_ANSWER)
        if path.endswith("/alias"):
            return httpx.Response(200, json={"status": 1, "data": {"claimed": True}})
        if path.endswith("/merge"):
            return httpx.Response(202, json={"status": 1, "data": {"userId": "u1"}})
        if path.endswith("/consents"):
            return httpx.Response(
                200, json={"status": 1, "data": {"channel": "email", "status": "opted_in"}}
            )
        return httpx.Response(201, json={"status": 1, "data": {"id": "jp1", "userId": "u1"}})

    async with make_async(handler, device_id="dev_1", base_url="https://staging.example/") as c:
        batch = await c.track_batch([c.build_event("a", event_time=FIXED)])
        claimed = await c.alias("u1", ALIAS_EMAIL, "a@b.c")
        kept = await c.merge("u1", "u2")
        consent = await c.set_consent("u1", "email", CONSENT_OPTED_IN, source="form")
        participant = await c.enter_journey("j1", "u1")

    assert batch["accepted"] == 2
    assert claimed == {"claimed": True}
    assert kept == {"userId": "u1"}
    assert consent == {"channel": "email", "status": "opted_in"}
    assert participant == {"id": "jp1", "userId": "u1"}
    assert [(r.method, str(r.url)) for r in seen] == [
        ("POST", "https://staging.example/v1/engage/track/batch"),
        ("POST", "https://staging.example/v1/engage/users/alias"),
        ("POST", "https://staging.example/v1/engage/users/merge"),
        ("PUT", "https://staging.example/v1/engage/users/userId/u1/consents"),
        ("POST", "https://staging.example/v1/engage/configurations/journeys/j1/enter"),
    ]
    assert all(r.headers["X-Api-Key"] == "lc_admin" for r in seen)
    assert json.loads(seen[0].content)["events"][0]["device_id"] == "dev_1"


async def test_async_errors_and_arguments() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(409, json={"error": {"message": "already in", "code": 409}})

    client = make_async(handler)
    with pytest.raises(EngageError) as info:
        await client.enter_journey("j1", "u1")
    assert info.value.status_code == 409
    with pytest.raises(ValueError):
        await client.track_batch([])
    with pytest.raises(ValueError):
        await client.set_consent("u1", "", CONSENT_OPTED_IN)
    assert len(seen) == 1
    await client.aclose()
