from __future__ import annotations

import json
import uuid
from collections.abc import Callable
from datetime import date, datetime, timedelta, timezone
from typing import Any

import httpx
import pytest

from lowcoai.engage import (
    ATTRIBUTION_KEYS,
    DeviceInfo,
    EngageClient,
    EngageError,
    LocationInfo,
    attribution_from_url,
)

FIXED = datetime(2026, 9, 30, 12, 34, 56, 789123, tzinfo=timezone.utc)


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


def make_client(rec: Recorder, **kwargs: Any) -> EngageClient:
    return EngageClient(
        "key_123",
        "org_1",
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
        **kwargs,
    )


@pytest.mark.parametrize(("api_key", "org_id"), [("", "org_1"), ("  ", "org_1"), ("k", " ")])
def test_api_key_and_org_id_are_required(api_key: str, org_id: str) -> None:
    with pytest.raises(ValueError):
        EngageClient(api_key, org_id)


def test_track_sends_one_event_with_headers_and_url() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="dev_1")
    client.track(
        "signup_completed",
        {"plan": "pro", "seats": 3},
        user_id="user_1",
        session_id="sess_1",
        event_time=FIXED,
    )
    assert len(rec.requests) == 1
    req = rec.last
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/engage/track"
    assert req.headers["Authorization"] == "Bearer key_123"
    assert req.headers["X-Org-Id"] == "org_1"
    assert req.headers["Content-Type"] == "application/json"
    body = rec.last_json()
    assert body == {
        "id": "",
        "event_name": "signup_completed",
        "event_data": {"plan": "pro", "seats": 3},
        "user_id": "user_1",
        "device_id": "dev_1",
        "session_id": "sess_1",
        "event_time": "2026-09-30T12:34:56.789Z",
    }
    # Same key order as the browser SDK's object literal.
    assert list(body) == [
        "id",
        "event_name",
        "event_data",
        "user_id",
        "device_id",
        "session_id",
        "event_time",
    ]


def test_none_fields_are_omitted_and_event_data_defaults_to_empty() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="dev_1")
    client.track("ping")
    body = rec.last_json()
    assert set(body) == {"id", "event_name", "event_data", "device_id", "event_time"}
    assert body["event_data"] == {}
    for key in ("user_id", "session_id", "device_info", "location"):
        assert key not in body


def test_device_info_and_location_are_sent_verbatim() -> None:
    rec = Recorder()
    client = make_client(rec)
    device_info: DeviceInfo = {
        "browser": {"name": "Chrome", "version": "126.0.0.0", "major": "126"},
        "os": {"name": "Mac OS", "version": "10.15.7"},
        "device": {"model": "Macintosh", "vendor": "Apple"},
        "cpu": {"architecture": "arm64"},
        "engine": {"name": "Blink", "version": "126.0.0.0"},
        "ua": "Mozilla/5.0",
    }
    location: LocationInfo = {
        "latitude": 12.97,
        "longitude": 77.59,
        "accuracy": 10.0,
        "altitude": None,
        "altitude_accuracy": None,
        "ip_address": "203.0.113.7",
    }
    client.track("checkout", device_info=device_info, location=location)
    body = rec.last_json()
    assert body["device_info"] == device_info
    assert body["location"] == location


def test_properties_are_copied_not_mutated() -> None:
    rec = Recorder()
    client = make_client(rec)
    props = {"a": 1}
    client.track("x", props)
    assert props == {"a": 1}
    assert rec.last_json()["event_data"] == {"a": 1}


def test_body_is_compact_utf8_json() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="d")
    client.track("café", {"n": 1}, event_time=FIXED)
    assert (
        rec.last.content
        == (
            '{"id":"","event_name":"café","event_data":{"n":1},"device_id":"d",'
            '"event_time":"2026-09-30T12:34:56.789Z"}'
        ).encode()
    )
    with pytest.raises(ValueError):
        client.track("x", {"bad": float("nan")})
    assert len(rec.requests) == 1


def test_datetime_and_date_properties_are_serialised() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.track("renewal", {"at": FIXED, "on": date(2026, 10, 1)})
    assert rec.last_json()["event_data"] == {"at": "2026-09-30T12:34:56.789Z", "on": "2026-10-01"}


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (FIXED, "2026-09-30T12:34:56.789Z"),
        # Aware, non-UTC: converted to UTC.
        (
            datetime(2026, 9, 30, 18, 4, 56, 5000, tzinfo=timezone(timedelta(hours=5, minutes=30))),
            "2026-09-30T12:34:56.005Z",
        ),
        # Naive: treated as UTC.
        (datetime(2026, 1, 2, 3, 4, 5), "2026-01-02T03:04:05.000Z"),
        # Sub-millisecond precision is truncated like JS Date.
        (datetime(2026, 1, 2, 3, 4, 5, 999999), "2026-01-02T03:04:05.999Z"),
    ],
)
def test_event_time_formatting(value: datetime, expected: str) -> None:
    rec = Recorder()
    client = make_client(rec)
    client.track("x", event_time=value)
    assert rec.last_json()["event_time"] == expected


def test_event_time_defaults_to_now_in_utc() -> None:
    rec = Recorder()
    client = make_client(rec)
    before = datetime.now(timezone.utc) - timedelta(seconds=1)
    client.track("x")
    after = datetime.now(timezone.utc) + timedelta(seconds=1)
    raw = rec.last_json()["event_time"]
    assert raw.endswith("Z") and len(raw) == len("2026-09-30T12:34:56.789Z")
    parsed = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)
    assert before <= parsed <= after


def test_default_device_id_is_a_uuid4_per_client() -> None:
    rec = Recorder()
    a = make_client(rec)
    b = make_client(rec)
    assert uuid.UUID(a.device_id).version == 4
    assert a.device_id != b.device_id
    a.track("x")
    a.track("y")
    assert [json.loads(r.content)["device_id"] for r in rec.requests] == [a.device_id] * 2


def test_per_call_device_id_overrides_default() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="dev_default")
    assert client.device_id == "dev_default"
    client.track("x", device_id="dev_browser")
    assert rec.last_json()["device_id"] == "dev_browser"
    client.track("x")
    assert rec.last_json()["device_id"] == "dev_default"


def test_page_sends_page_view() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.page({"path": "/pricing", "title": "Pricing"}, user_id="u1", event_time=FIXED)
    body = rec.last_json()
    assert body["event_name"] == "page_view"
    assert body["event_data"] == {"path": "/pricing", "title": "Pricing"}
    assert body["user_id"] == "u1"
    client.page()
    assert rec.last_json()["event_name"] == "page_view"
    assert rec.last_json()["event_data"] == {}


def test_identify_user_sends_identify_event() -> None:
    rec = Recorder()
    client = make_client(rec, device_id="dev_1")
    client.identify_user("user_42", {"email": "ada@example.com"}, session_id="s1")
    body = rec.last_json()
    assert body["event_name"] == "_lowco_identify"
    assert body["user_id"] == "user_42"
    assert body["device_id"] == "dev_1"
    assert body["session_id"] == "s1"
    assert body["event_data"] == {"email": "ada@example.com"}


def test_client_is_stateless_about_users() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.identify_user("user_42")
    client.track("after_identify")
    assert "user_id" not in rec.last_json()


def test_blank_event_name_and_user_id_are_rejected() -> None:
    rec = Recorder()
    client = make_client(rec)
    with pytest.raises(ValueError):
        client.track(" ")
    with pytest.raises(ValueError):
        client.identify_user("")
    assert rec.requests == []


def test_non_json_2xx_body_is_fine() -> None:
    rec = Recorder(lambda _r: httpx.Response(204))
    make_client(rec).track("x")
    rec = Recorder(lambda _r: httpx.Response(200, text="ok"))
    make_client(rec).track("x")


def test_error_envelope_is_mapped() -> None:
    body = {
        "status": 0,
        "error": {"message": "AAS-00400", "code": 400, "details": "bad event_time"},
    }
    rec = Recorder(lambda _r: httpx.Response(400, json=body))
    with pytest.raises(EngageError) as info:
        make_client(rec).track("x")
    err = info.value
    assert err.status_code == 400
    assert err.message == "bad event_time"
    assert err.code == 400
    assert json.loads(err.body) == body
    assert str(err) == "bad event_time"


def test_error_with_plain_text_body() -> None:
    rec = Recorder(lambda _r: httpx.Response(502, text="Bad Gateway"))
    with pytest.raises(EngageError) as info:
        make_client(rec).page()
    assert info.value.status_code == 502
    assert info.value.message == "Bad Gateway"
    assert info.value.code is None


def test_error_with_empty_body_and_message_field() -> None:
    rec = Recorder(lambda _r: httpx.Response(401))
    with pytest.raises(EngageError) as info:
        make_client(rec).track("x")
    assert info.value.message == "engage: status=401"
    rec = Recorder(lambda _r: httpx.Response(403, json={"message": "forbidden"}))
    with pytest.raises(EngageError) as info:
        make_client(rec).track("x")
    assert info.value.message == "forbidden"


def test_transport_errors_propagate() -> None:
    def boom(_r: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    with pytest.raises(httpx.ConnectError):
        make_client(Recorder(boom)).track("x")


def test_timeout_is_applied_per_request() -> None:
    rec = Recorder()
    make_client(rec, timeout=5.0).track("x")
    assert rec.last.extensions["timeout"] == {
        "connect": 5.0,
        "read": 5.0,
        "write": 5.0,
        "pool": 5.0,
    }


def test_injected_client_is_not_closed() -> None:
    http = httpx.Client(transport=httpx.MockTransport(Recorder()))
    with EngageClient("k", "o", http_client=http) as client:
        client.track("x")
    assert not http.is_closed
    own = EngageClient("k", "o")
    own.close()
    assert own._http.is_closed


# --- attribution ------------------------------------------------------------


def test_attribution_from_full_url() -> None:
    url = (
        "https://shop.example/landing?utm_source=google&utm_medium=cpc&utm_campaign=fall+sale"
        "&utm_term=shoes&utm_content=ad%201&utm_id=42&gclid=g1&fbclid=f1&msclkid=m1&other=x"
    )
    assert attribution_from_url(url) == {
        "utm_source": "google",
        "utm_medium": "cpc",
        "utm_campaign": "fall sale",
        "utm_term": "shoes",
        "utm_content": "ad 1",
        "utm_id": "42",
        "gclid": "g1",
        "fbclid": "f1",
        "msclkid": "m1",
    }
    assert tuple(attribution_from_url(url)) == ATTRIBUTION_KEYS


@pytest.mark.parametrize(
    "value",
    [
        "?utm_source=news&gclid=abc",
        "utm_source=news&gclid=abc",
        "/landing?utm_source=news&gclid=abc#top",
        "https://x.example/?gclid=abc&utm_source=news",
    ],
)
def test_attribution_from_query_forms(value: str) -> None:
    assert attribution_from_url(value) == {"utm_source": "news", "gclid": "abc"}


@pytest.mark.parametrize(
    "value",
    ["", "https://x.example/", "https://x.example/#/r?utm_source=a", "?utm_source=&foo=1"],
)
def test_attribution_empty(value: str) -> None:
    assert attribution_from_url(value) == {}


def test_attribution_first_value_wins() -> None:
    assert attribution_from_url("?utm_source=a&utm_source=b") == {"utm_source": "a"}


def test_attribution_merges_into_properties() -> None:
    rec = Recorder()
    client = make_client(rec)
    attribution = attribution_from_url("https://x.example/?utm_source=ads")
    client.track("signup", {**attribution, "plan": "pro"})
    assert rec.last_json()["event_data"] == {"utm_source": "ads", "plan": "pro"}
