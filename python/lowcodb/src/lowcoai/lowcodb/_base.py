"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import json
import time
from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

from ._errors import LowcodbError, build_http_error
from .types import HEADER_ORG_ID

BASE_URL = "https://api.lowco.ai"
DEFAULT_API_BASE_PATH = "/v1/lowcodb"
DEFAULT_TIMEOUT = 30.0

# A base's data — records, view rows, DB functions, transactions — is served only by
# the base's API gateway (https://api.lowco.ai/gateway/<hash>/v1/...); the manager's
# own data routes are cluster-internal. The data methods keep their (schema, table)
# signatures and the client resolves the schema's gateway behind them.

#: Header carrying an ``lc_`` API key; user tokens travel as ``Authorization: Bearer``.
HEADER_API_KEY = "X-Api-Key"
#: How long a resolved gateway is reused before it is looked up again (seconds).
DEFAULT_GATEWAY_CACHE_TTL = 600.0


def is_api_key(token: str) -> bool:
    """Whether ``token`` is a Lowco API key rather than a user token."""
    return token.strip().startswith("lc_")


class BaseClient:
    """Holds configuration and builds / decodes requests for both clients."""

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None,
        base_url: str | None,
        api_base_path: str | None,
        default_headers: Mapping[str, str] | None,
        gateways: Mapping[str, str] | None = None,
        gateway_origin: str = "public",
        gateway_cache_ttl: float = DEFAULT_GATEWAY_CACHE_TTL,
    ) -> None:
        if not token or not token.strip():
            raise ValueError("LowcodbClient: token is required")
        self._base_url = (base_url or BASE_URL).rstrip("/")
        self._api_base_path = "/" + (api_base_path or DEFAULT_API_BASE_PATH).strip("/")
        self._headers: dict[str, str] = dict(default_headers or {})
        if is_api_key(token):
            self._headers[HEADER_API_KEY] = token.strip()
        else:
            self._headers["Authorization"] = f"Bearer {token}"
        if org_id:
            self._headers[HEADER_ORG_ID] = org_id
        self._gateways: dict[str, str] = {k.strip(): v.strip() for k, v in (gateways or {}).items()}
        self._gateway_origin = "internal" if gateway_origin == "internal" else "public"
        self._gateway_cache_ttl = gateway_cache_ttl
        self._gateway_cache: dict[str, tuple[str, float]] = {}

    def set_org_id(self, org_id: str | None) -> None:
        """Sets the ``X-Org-Id`` header for later requests; ``None`` removes it."""
        if org_id:
            self._headers[HEADER_ORG_ID] = org_id
        else:
            self._headers.pop(HEADER_ORG_ID, None)

    def set_header(self, key: str, value: str | None) -> None:
        """Sets / overwrites an arbitrary default header. Pass ``None`` to delete."""
        if value is None:
            self._headers.pop(key, None)
        else:
            self._headers[key] = value

    # --- request building -------------------------------------------------

    def _api(self, *parts: str) -> str:
        segs = [self._api_base_path.strip("/")]
        segs.extend(_seg(p.strip("/")) for p in parts)
        return "/" + "/".join(segs)

    def _data(self, schema: str, object_type: str, object_name: str, *parts: str) -> str:
        segs = [
            self._api_base_path.strip("/"),
            "data",
            _seg(schema),
            object_type,
            _seg(object_name),
        ]
        segs.extend(_seg(p) for p in parts)
        return "/" + "/".join(segs)

    def _url(self, path: str) -> str:
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return self._base_url + path

    # --- gateway resolution ------------------------------------------------

    def _absolute_gateway(self, path_or_url: str) -> str:
        p = path_or_url.strip().rstrip("/")
        if p.startswith("http://") or p.startswith("https://"):
            return p
        return self._base_url + "/" + p.lstrip("/")

    def _pinned_gateway(self, schema: str) -> str | None:
        pinned = self._gateways.get(schema.strip())
        return self._absolute_gateway(pinned) if pinned else None

    def _cached_gateway(self, schema: str) -> str | None:
        entry = self._gateway_cache.get(schema)
        if entry and entry[1] > time.monotonic():
            return entry[0]
        return None

    def _remember_gateway(self, schema: str, base: str) -> None:
        self._gateway_cache[schema] = (base, time.monotonic() + self._gateway_cache_ttl)

    def _forget_gateway(self, schema: str) -> None:
        self._gateway_cache.pop(schema.strip(), None)

    def _pick_gateway_base(self, schema: str, info: Mapping[str, Any] | None) -> str:
        info = info or {}
        internal = str(info.get("internalUrl") or "").strip()
        if self._gateway_origin == "internal" and internal:
            return internal.rstrip("/")
        url = str(info.get("url") or "").strip()
        if url:
            return url.rstrip("/")
        context_path = str(info.get("contextPath") or "").strip()
        if context_path:
            return self._absolute_gateway(context_path)
        raise LowcodbError(
            status_code=404, message=f"lowcodb: base {schema} has no usable gateway yet"
        )

    def _request_headers(self, has_body: bool) -> dict[str, str]:
        headers = {"Accept": "application/json", **self._headers}
        if has_body:
            headers["Content-Type"] = "application/json"
        return headers

    @staticmethod
    def _encode_body(body: Any) -> bytes | None:
        if body is None:
            return None
        return json.dumps(body, default=_json_default).encode("utf-8")


def list_query(
    page_no: int | None, size: int | None, filter: str | None, sort: str | None
) -> dict[str, str]:
    q: dict[str, str] = {}
    if page_no is not None:
        q["pageNo"] = str(page_no)
    if size is not None:
        q["size"] = str(size)
    if filter is not None:
        q["filter"] = filter
    if sort is not None:
        q["sort"] = sort
    return q


def iso(value: datetime) -> str:
    """Formats like JavaScript's ``toISOString``; naive datetimes are treated as UTC."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    value = value.astimezone(timezone.utc)
    return value.strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"


def decode_response(status: int, text: str, *, enveloped: bool) -> Any:
    if status < 200 or status >= 300:
        raise build_http_error(status, text)
    if status == 204 or not text.strip():
        return None
    try:
        parsed = json.loads(text)
    except ValueError as exc:
        raise LowcodbError(
            status_code=status, message=f"lowcodb: invalid JSON response: {exc}", body=text
        ) from exc
    if enveloped and isinstance(parsed, dict) and "data" in parsed:
        return parsed["data"]
    return parsed


def check_status(status: int, text: str) -> None:
    if status < 200 or status >= 300:
        raise build_http_error(status, text)


def _seg(value: str) -> str:
    return quote(value, safe="")


def _json_default(value: Any) -> Any:
    if isinstance(value, datetime):
        return iso(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


# --- gateway routes ----------------------------------------------------------


def table_route(table: str, *parts: str) -> str:
    return "/" + "/".join(["v1", _seg(table), *(_seg(p) for p in parts)])


def view_route(view: str, *parts: str) -> str:
    return "/" + "/".join(["v1", "views", _seg(view), *(_seg(p) for p in parts)])


def function_route(key: str) -> str:
    return "/" + "/".join(["v1", "fn", _seg(key)])


def transactions_route() -> str:
    return "/v1/transactions"
