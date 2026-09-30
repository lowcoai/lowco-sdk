"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import json
import uuid
from collections.abc import Mapping
from datetime import date, datetime, timezone
from typing import Any, cast
from urllib.parse import parse_qsl

from ._errors import build_http_error
from .types import DeviceInfo, Event, LocationInfo

BASE_URL = "https://api.lowco.ai"
TRACK_PATH = "/v1/engage/track"
HEADER_ORG_ID = "X-Org-Id"
PAGE_VIEW_EVENT = "page_view"
IDENTIFY_EVENT = "_lowco_identify"
DEFAULT_TIMEOUT = 30.0

ATTRIBUTION_KEYS: tuple[str, ...] = (
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "utm_id",
    "gclid",
    "fbclid",
    "msclkid",
)
"""Query parameters the browser SDK captures as attribution (same order)."""


class BaseClient:
    """Holds configuration and builds / encodes events for both clients."""

    def __init__(self, api_key: str, org_id: str, *, device_id: str | None) -> None:
        if not api_key or not api_key.strip():
            raise ValueError("EngageClient: api_key is required")
        if not org_id or not org_id.strip():
            raise ValueError("EngageClient: org_id is required")
        self._device_id = device_id or str(uuid.uuid4())
        self._track_url = BASE_URL + TRACK_PATH
        self._headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            HEADER_ORG_ID: org_id,
        }

    @property
    def device_id(self) -> str:
        """Default ``device_id`` for events that don't pass one (uuid4 unless configured)."""
        return self._device_id

    def _build_event(
        self,
        event_name: str,
        properties: Mapping[str, Any] | None,
        *,
        user_id: str | None,
        device_id: str | None,
        session_id: str | None,
        device_info: DeviceInfo | None,
        location: LocationInfo | None,
        event_time: datetime | None,
    ) -> Event:
        if not event_name or not event_name.strip():
            raise ValueError("event_name is required")
        event: dict[str, Any] = {
            "id": "",
            "event_name": event_name,
            "event_data": dict(properties) if properties else {},
            "user_id": user_id,
            "device_id": device_id or self._device_id,
            "session_id": session_id,
            "device_info": device_info,
            "location": location,
            "event_time": iso(event_time if event_time is not None else _utcnow()),
        }
        return cast(Event, {k: v for k, v in event.items() if v is not None})


def encode_event(event: Event) -> bytes:
    """Compact UTF-8 JSON like ``JSON.stringify``; NaN / infinity raise ``ValueError``."""
    return json.dumps(
        event,
        default=_json_default,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def check_status(status: int, text: str) -> None:
    if status < 200 or status >= 300:
        raise build_http_error(status, text)


def iso(value: datetime) -> str:
    """Formats like JavaScript's ``toISOString``; naive datetimes are treated as UTC."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    value = value.astimezone(timezone.utc)
    return value.strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"


def attribution_from_url(url_or_query: str) -> dict[str, str]:
    """Extracts the attribution parameters (UTM tags, ``gclid``, ``fbclid``, ``msclkid``).

    Accepts a full URL (``"https://shop.example/?utm_source=x"``), a path with a
    query (``"/landing?utm_source=x"``) or a bare query string (``"?utm_source=x"``
    / ``"utm_source=x"``). Like the browser SDK (``location.search`` +
    ``URLSearchParams``), anything after ``#`` is ignored, the first value of a
    repeated key wins and empty values are skipped. Keys come back in
    :data:`ATTRIBUTION_KEYS` order.
    """
    query = url_or_query.strip().split("#", 1)[0]
    if "?" in query:
        query = query.split("?", 1)[1]
    elif "=" not in query:
        return {}
    found: dict[str, str] = {}
    for key, value in parse_qsl(query, keep_blank_values=True):
        if key not in found:
            found[key] = value
    return {key: found[key] for key in ATTRIBUTION_KEYS if found.get(key)}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _json_default(value: Any) -> Any:
    if isinstance(value, datetime):
        return iso(value)
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")
