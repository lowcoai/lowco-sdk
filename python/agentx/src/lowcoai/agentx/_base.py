"""Transport-independent pieces shared by the sync and async clients."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any
from urllib.parse import quote

from ._errors import AgentxError, build_http_error
from .types import HEADER_ORG_ID, METHOD_MESSAGE_SEND, JSONRPCRequest, MessageSendParams

BASE_URL = "https://api.lowco.ai"
DEFAULT_TIMEOUT = 30.0

ACCEPT_JSON = "application/json"
ACCEPT_EVENT_STREAM = "text/event-stream"


def build_headers(
    token: str, org_id: str | None, default_headers: Mapping[str, str] | None
) -> dict[str, str]:
    """The mutable header bag owned by the top-level client and shared by every sub-client."""
    if not token or not token.strip():
        raise ValueError("AgentxClient: token is required")
    headers = dict(default_headers or {})
    headers["Authorization"] = f"Bearer {token}"
    if org_id:
        headers[HEADER_ORG_ID] = org_id
    return headers


def set_org_id(headers: dict[str, str], org_id: str | None) -> None:
    if org_id:
        headers[HEADER_ORG_ID] = org_id
    else:
        headers.pop(HEADER_ORG_ID, None)


def set_header(headers: dict[str, str], key: str, value: str | None) -> None:
    if value is None:
        headers.pop(key, None)
    else:
        headers[key] = value


def normalize_prefix(prefix: str) -> str:
    return "/" + prefix.strip("/")


def join_path(api_base_path: str, *parts: str) -> str:
    segs = [api_base_path.strip("/")]
    segs.extend(quote(p.strip("/"), safe="") for p in parts)
    return "/" + "/".join(segs)


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


def request_headers(headers: Mapping[str, str], accept: str, has_body: bool) -> dict[str, str]:
    # Same precedence as the TS SDK: default headers may override Accept.
    out = {"Accept": accept, **headers}
    if has_body:
        out["Content-Type"] = "application/json"
    return out


def encode_body(body: Any) -> bytes | None:
    if body is None:
        return None
    return json.dumps(body).encode("utf-8")


def is_success(status: int) -> bool:
    return 200 <= status < 300


def check_status(status: int, text: str) -> None:
    if not is_success(status):
        raise build_http_error(status, text)


def _parse_json(status: int, text: str) -> Any:
    try:
        return json.loads(text)
    except ValueError as exc:
        raise AgentxError(
            status_code=status, message=f"agentx: invalid JSON response: {exc}", body=text
        ) from exc


def decode_response(status: int, text: str, *, enveloped: bool) -> Any:
    check_status(status, text)
    if status == 204 or not text.strip():
        return None
    parsed = _parse_json(status, text)
    if enveloped and isinstance(parsed, dict) and "data" in parsed:
        return parsed["data"]
    return parsed


def rpc_request(agent_id: str, params: MessageSendParams) -> JSONRPCRequest:
    # The JSON-RPC id doubles as the target agent identifier (service convention).
    return {"jsonrpc": "2.0", "method": METHOD_MESSAGE_SEND, "params": params, "id": agent_id}


def decode_rpc_response(status: int, text: str, agent_id: str) -> Any:
    check_status(status, text)
    if status == 204 or not text.strip():
        return {"jsonrpc": "2.0", "id": agent_id}
    return _parse_json(status, text)
