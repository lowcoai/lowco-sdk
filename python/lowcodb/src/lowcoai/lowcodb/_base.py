"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import json
from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

from ._errors import LowcodbError, build_http_error
from .types import HEADER_ORG_ID

BASE_URL = "https://api.lowco.ai"
DEFAULT_API_BASE_PATH = "/v1/lowcodb"
DEFAULT_TIMEOUT = 30.0


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
    ) -> None:
        if not token or not token.strip():
            raise ValueError("LowcodbClient: token is required")
        self._base_url = (base_url or BASE_URL).rstrip("/")
        self._api_base_path = "/" + (api_base_path or DEFAULT_API_BASE_PATH).strip("/")
        self._headers: dict[str, str] = dict(default_headers or {})
        self._headers["Authorization"] = f"Bearer {token}"
        if org_id:
            self._headers[HEADER_ORG_ID] = org_id

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
        return self._base_url + path

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
