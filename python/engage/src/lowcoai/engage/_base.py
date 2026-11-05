"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import json
import uuid
from collections.abc import Mapping, Sequence
from datetime import date, datetime, timezone
from typing import Any, cast
from urllib.parse import parse_qsl, quote

from ._errors import build_http_error
from .types import DeviceInfo, Event, LocationInfo

BASE_URL = "https://api.lowco.ai"
TRACK_PATH = "/v1/engage/track"
TRACK_BATCH_PATH = "/v1/engage/track/batch"
"""Batch ingestion: up to :data:`MAX_BATCH` events, each taken or refused on its own."""
ALIAS_PATH = "/v1/engage/users/alias"
MERGE_PATH = "/v1/engage/users/merge"
MAX_BATCH = 1000
"""The most events one ``track_batch`` call takes."""
HEADER_ORG_ID = "X-Org-Id"
HEADER_API_KEY = "X-Api-Key"
"""Carries an ``lc_`` API key; any other token travels as ``Authorization: Bearer``."""
HEADER_ENGAGE_APP_ID = "X-Engage-App-Id"
"""Selects the engage app; without it the service uses the org's default app."""
PAGE_VIEW_EVENT = "page_view"
IDENTIFY_EVENT = "_lowco_identify"
DEFAULT_TIMEOUT = 30.0

ALIAS_ANONYMOUS = "anonymous"
"""An SDK device / anonymous id: the person's earlier anonymous events become theirs."""
ALIAS_EMAIL = "email"
ALIAS_PHONE = "phone"
ALIAS_EXTERNAL = "external"
"""An id in another system (a CRM lead id, say)."""

CONSENT_OPTED_IN = "opted_in"
CONSENT_OPTED_OUT = "opted_out"
CONSENT_PENDING = "pending"
CONSENT_CHANNELS: tuple[str, ...] = ("email", "sms", "whatsapp", "push", "webpush", "inapp", "all")

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


def is_api_key(api_key: str) -> bool:
    """Whether ``api_key`` is a Lowco API key (``lc_…``) rather than an access token."""
    return api_key.strip().startswith("lc_")


class BaseClient:
    """Holds configuration and builds / encodes events for both clients."""

    def __init__(
        self,
        api_key: str,
        org_id: str,
        *,
        app_id: str | None,
        device_id: str | None,
        base_url: str | None = None,
    ) -> None:
        if not api_key or not api_key.strip():
            raise ValueError("EngageClient: api_key is required")
        if not org_id or not org_id.strip():
            raise ValueError("EngageClient: org_id is required")
        self._device_id = device_id or str(uuid.uuid4())
        self._app_id = app_id.strip() if app_id and app_id.strip() else None
        self._base_url = (base_url or "").strip().rstrip("/") or BASE_URL
        self._track_url = self._base_url + TRACK_PATH
        api_key = api_key.strip()
        self._headers = {"Content-Type": "application/json"}
        if is_api_key(api_key):
            self._headers[HEADER_API_KEY] = api_key
        else:
            self._headers["Authorization"] = f"Bearer {api_key}"
        self._headers[HEADER_ORG_ID] = org_id
        if self._app_id is not None:
            self._headers[HEADER_ENGAGE_APP_ID] = self._app_id

    @property
    def device_id(self) -> str:
        """Default ``device_id`` for events that don't pass one (uuid4 unless configured)."""
        return self._device_id

    @property
    def app_id(self) -> str | None:
        """The engage app events go to, or ``None`` for the org's default app."""
        return self._app_id

    @property
    def base_url(self) -> str:
        """The API host calls go to (``https://api.lowco.ai`` unless configured)."""
        return self._base_url

    def build_event(
        self,
        event_name: str,
        properties: Mapping[str, Any] | None = None,
        *,
        user_id: str | None = None,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> Event:
        """The event ``track`` would send, without sending it (to collect for ``track_batch``).

        ``properties`` are copied into ``event_data``; ``device_id`` defaults to
        :attr:`device_id` and ``event_time`` to now. Raises ``ValueError`` for a
        blank ``event_name``.
        """
        return self._build_event(
            event_name,
            properties,
            user_id=user_id,
            device_id=device_id,
            session_id=session_id,
            device_info=device_info,
            location=location,
            event_time=event_time,
        )

    # --- request builders shared by the sync and async clients -------------

    def _batch_request(self, events: Sequence[Event]) -> tuple[str, str, bytes]:
        if not events:
            raise ValueError("track_batch: events are required")
        if len(events) > MAX_BATCH:
            raise ValueError(f"track_batch: at most {MAX_BATCH} events a batch")
        return "POST", self._base_url + TRACK_BATCH_PATH, encode_json({"events": list(events)})

    def _alias_request(
        self, user_id: str, alias_type: str, alias_value: str
    ) -> tuple[str, str, bytes]:
        _require(user_id, "user_id")
        _require(alias_type, "alias_type")
        _require(alias_value, "alias_value")
        body = {"userId": user_id, "aliasType": alias_type, "aliasValue": alias_value}
        return "POST", self._base_url + ALIAS_PATH, encode_json(body)

    def _merge_request(self, keep_user_id: str, merge_user_id: str) -> tuple[str, str, bytes]:
        _require(keep_user_id, "keep_user_id")
        _require(merge_user_id, "merge_user_id")
        body = {"keepUserId": keep_user_id, "mergeUserId": merge_user_id}
        return "POST", self._base_url + MERGE_PATH, encode_json(body)

    def _consent_request(
        self,
        user_id: str,
        channel: str,
        status: str,
        source: str | None,
        evidence: Mapping[str, Any] | None,
    ) -> tuple[str, str, bytes]:
        _require(user_id, "user_id")
        _require(channel, "channel")
        _require(status, "status")
        body: dict[str, Any] = {"channel": channel, "status": status}
        if source:
            body["source"] = source
        if evidence:
            body["evidence"] = dict(evidence)
        user = quote(user_id, safe="")
        url = f"{self._base_url}/v1/engage/users/userId/{user}/consents"
        return "PUT", url, encode_json(body)

    def _journey_request(self, journey_id: str, user_id: str) -> tuple[str, str, bytes]:
        _require(journey_id, "journey_id")
        _require(user_id, "user_id")
        journey = quote(journey_id, safe="")
        url = f"{self._base_url}/v1/engage/configurations/journeys/{journey}/enter"
        return "POST", url, encode_json({"userId": user_id})

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
    return encode_json(event)


def encode_json(value: Any) -> bytes:
    """Compact UTF-8 JSON like ``JSON.stringify``; NaN / infinity raise ``ValueError``."""
    return json.dumps(
        value,
        default=_json_default,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def check_status(status: int, text: str) -> None:
    if status < 200 or status >= 300:
        raise build_http_error(status, text)


def decode_data(status: int, text: str) -> Any:
    """The ``data`` of a 2xx ``{"status", "data"}`` answer (``None`` when absent).

    Raises :class:`EngageError` for a non-2xx status and ``ValueError`` when a
    2xx body isn't JSON.
    """
    check_status(status, text)
    if not text.strip():
        return None
    try:
        parsed = json.loads(text)
    except ValueError as exc:
        raise ValueError(f"engage: response is not JSON: {text[:200]!r}") from exc
    return parsed.get("data") if isinstance(parsed, dict) else None


def _require(value: str, name: str) -> None:
    if not value or not value.strip():
        raise ValueError(f"{name} is required")


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
