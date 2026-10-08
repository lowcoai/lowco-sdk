"""Transport-independent pieces shared by the sync and async HTTP clients.

Mirrors ``HttpClient`` in the TypeScript SDK's ``client.ts``: header
precedence, query encoding, envelope unwrapping and error mapping.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any
from urllib.parse import quote

import httpx

from ._errors import IntegrationsError
from .types import HEADER_ORG_ID

BASE_URL = "https://api.lowco.ai"
DEFAULT_TIMEOUT = 30.0


class BaseHttpClient:
    """Holds configuration and builds / decodes requests for both clients."""

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None,
        timeout: float | None,
        headers: Mapping[str, str] | None,
    ) -> None:
        if not token or not token.strip():
            raise ValueError(
                "IntegrationsClient: `token` is required. Pass a user token or API key."
            )
        self._token = token
        self._org_id = org_id
        self._timeout = timeout
        self._extra_headers: dict[str, str] = dict(headers or {})

    def _url(self, path: str) -> str:
        return BASE_URL + (path if path.startswith("/") else "/" + path)

    def _headers(self, has_body: bool, headers: Mapping[str, str] | None) -> httpx.Headers:
        # Same order as the TS client: defaults, then configured and per-request
        # headers, then Content-Type (only with a body); Authorization and
        # X-Org-Id are added only when not already supplied (case-insensitive).
        out = httpx.Headers({"Accept": "application/json"})
        for source in (self._extra_headers, headers or {}):
            for key, value in source.items():
                out[key] = value
        if has_body:
            out["Content-Type"] = "application/json"
        if not out.get("Authorization"):
            out["Authorization"] = f"Bearer {self._token}"
        if self._org_id and not out.get(HEADER_ORG_ID):
            out[HEADER_ORG_ID] = self._org_id
        return out


def seg(value: str) -> str:
    """URL-encodes one path segment (``/`` included)."""
    return quote(str(value), safe="")


def encode_query(query: Mapping[str, Any] | None) -> dict[str, str] | None:
    """Encodes query values like the TS client: ``None`` is skipped, booleans
    become ``"true"`` / ``"false"``, strings and numbers are stringified and
    anything else is sent as JSON."""
    if not query:
        return None
    out: dict[str, str] = {}
    for key, value in query.items():
        if value is None:
            continue
        if isinstance(value, bool):
            out[key] = "true" if value else "false"
        elif isinstance(value, str):
            out[key] = value
        elif isinstance(value, int):
            out[key] = str(value)
        elif isinstance(value, float):
            # JavaScript's String(2.0) is "2".
            out[key] = str(int(value)) if value.is_integer() else repr(value)
        else:
            out[key] = _dumps(value)
    return out or None


def encode_body(body: Any) -> bytes | None:
    """``None`` means "no body" (``undefined`` in the TS client)."""
    if body is None:
        return None
    return _dumps(body).encode("utf-8")


def decode_response(status: int, text: str) -> Any:
    """Returns the decoded payload, unwrapping the ``data`` envelope."""
    if not 200 <= status < 300:
        raise http_error(status, text)
    if not text.strip():
        return None
    try:
        payload = json.loads(text)
    except ValueError as exc:
        raise IntegrationsError(
            f"Invalid JSON in response body (status {status})", status, text
        ) from exc
    if isinstance(payload, dict) and "data" in payload:
        return payload["data"]
    return payload


def check_response(status: int, text: str) -> None:
    """Status check for void methods: a 2xx body is ignored, JSON or not."""
    if not 200 <= status < 300:
        raise http_error(status, text)


def http_error(status: int, text: str) -> IntegrationsError:
    payload: Any = None
    if text.strip():
        try:
            payload = json.loads(text)
        except ValueError:
            payload = text
    return IntegrationsError(f"Request failed with status {status}", status, payload)


def transport_error(exc: httpx.HTTPError) -> IntegrationsError:
    return IntegrationsError(str(exc) or type(exc).__name__, 0, None)


def _dumps(value: Any) -> str:
    # Compact, non-ASCII-escaping output like JavaScript's JSON.stringify.
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False, default=_json_default)


def _json_default(value: Any) -> Any:
    # Methods accept ``Mapping`` bodies; ``json`` only serialises real dicts.
    if isinstance(value, Mapping):
        return dict(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")
