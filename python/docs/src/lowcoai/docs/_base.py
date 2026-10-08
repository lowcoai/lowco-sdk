"""Transport-independent pieces shared by the sync and async HTTP clients.

Header precedence, path / query / multipart encoding, envelope unwrapping,
redirect / binary / 202-restoring decoding and error mapping.
"""

from __future__ import annotations

import json
import re
from collections.abc import Mapping, Sequence
from typing import IO, Any, Literal
from urllib.parse import quote

import httpx

from ._errors import DocsError
from .types import HEADER_ORG_ID, Binary, FileInput, NodeFileResult, UploadFile

BASE_URL = "https://api.lowco.ai"
API_PREFIX = "/v1/documents"
DEFAULT_TIMEOUT = 30.0

ACCEPT_JSON = "application/json"
ACCEPT_ANY = "*/*"

BodyKind = Literal["none", "json", "multipart"]
MultipartFields = Mapping[str, str | Sequence[str] | None]
# httpx ``files=`` entries: (field, (filename, content, content type or None)).
MultipartFile = tuple[str, tuple[str, bytes | IO[bytes], str | None]]


class BaseHttpClient:
    """Holds configuration and builds / decodes requests for both clients."""

    def __init__(
        self,
        token: str,
        *,
        org_id: str,
        timeout: float | None,
        headers: Mapping[str, str] | None,
    ) -> None:
        if not token or not token.strip():
            raise ValueError("DocsClient: `token` is required. Pass a user token or API key.")
        if not org_id or not org_id.strip():
            raise ValueError(
                "DocsClient: `org_id` is required. The document service rejects every "
                "request without an X-Org-Id header."
            )
        self._token = token
        self._org_id = org_id
        self._timeout = timeout
        self._extra_headers: dict[str, str] = dict(headers or {})

    def _url(self, path: str) -> str:
        return BASE_URL + (path if path.startswith("/") else "/" + path)

    def _headers(
        self, body: BodyKind, accept: str, headers: Mapping[str, str] | None
    ) -> httpx.Headers:
        # Defaults, then configured and per-request headers, then the body's
        # Content-Type; Authorization and X-Org-Id are added only when not
        # already supplied (case-insensitive).
        out = httpx.Headers({"Accept": accept})
        for source in (self._extra_headers, headers or {}):
            for key, value in source.items():
                out[key] = value
        if body == "json":
            out["Content-Type"] = "application/json"
        elif body == "multipart" and "Content-Type" in out:
            # httpx sets multipart/form-data with the boundary only when absent.
            del out["Content-Type"]
        if not out.get("Authorization"):
            out["Authorization"] = f"Bearer {self._token}"
        if not out.get(HEADER_ORG_ID):
            out[HEADER_ORG_ID] = self._org_id
        return out


# --- paths, queries, bodies ---------------------------------------------------

# encodeURIComponent leaves A-Z a-z 0-9 - _ . ! ~ * ' ( ) unescaped.
_URI_COMPONENT_SAFE = "-_.!~*'()"


def seg(value: str) -> str:
    """Percent-encodes one path segment like ``encodeURIComponent`` (``/`` included).

    Raises :class:`DocsError` for ``.`` / ``..``: URL normalisation would remove
    the segment and silently hit a different route.
    """
    text = str(value)
    if text in (".", ".."):
        raise DocsError(
            f"Invalid path segment {text!r}: '.' and '..' cannot be sent as path segments",
            0,
            None,
        )
    return quote(text, safe=_URI_COMPONENT_SAFE)


def wildcard(path: str) -> str:
    """Encodes a multi-segment path for a ``/*`` route: a leading ``/`` is
    stripped and each segment is encoded like :func:`seg`, keeping ``/``."""
    return "/".join(seg(part) for part in str(path).lstrip("/").split("/"))


def flag(value: bool | None) -> str | None:
    """``True`` → ``"1"``; ``False`` / ``None`` → omitted (for presence-only flags)."""
    return "1" if value else None


def encode_query(query: Mapping[str, Any] | None) -> dict[str, str] | None:
    """Encodes query values: ``None`` is skipped, booleans become ``"true"`` /
    ``"false"``, strings and numbers are stringified and anything else is
    sent as JSON."""
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
            out[key] = str(int(value)) if value.is_integer() else repr(value)
        else:
            out[key] = _dumps(value)
    return out or None


def encode_body(body: Any) -> bytes | None:
    """``None`` means "no body"."""
    if body is None:
        return None
    return _dumps(body).encode("utf-8")


def to_upload_file(file: FileInput) -> UploadFile:
    """Normalises an upload argument to an :class:`UploadFile`."""
    if isinstance(file, UploadFile):
        return file
    if isinstance(file, tuple) and len(file) == 2:
        return UploadFile(file[0], file[1])
    if isinstance(file, tuple) and len(file) == 3:
        return UploadFile(file[0], file[1], file[2])
    raise TypeError(
        "Upload files must be UploadFile instances or (name, data[, content_type]) tuples, "
        f"not {type(file).__name__}"
    )


def encode_multipart(
    files: Sequence[tuple[str, FileInput]], fields: MultipartFields | None
) -> tuple[list[MultipartFile], dict[str, str | list[str]]]:
    """Builds httpx ``files=`` / ``data=`` arguments. ``None`` fields are skipped;
    a sequence value repeats the field (in order)."""
    parts: list[MultipartFile] = []
    for field_name, file in files:
        upload = to_upload_file(file)
        parts.append((field_name, (upload.name, upload.data, upload.content_type)))
    data: dict[str, str | list[str]] = {}
    for key, value in (fields or {}).items():
        if value is None:
            continue
        data[key] = value if isinstance(value, str) else [str(v) for v in value]
    return parts, data


# --- responses ----------------------------------------------------------------


def decode_response(status: int, text: str) -> Any:
    """Returns the decoded payload, unwrapping the ``data`` envelope."""
    if not 200 <= status < 300:
        raise http_error(status, text)
    if not text.strip():
        return None
    try:
        payload = json.loads(text)
    except ValueError as exc:
        raise DocsError(f"Invalid JSON in response body (status {status})", status, text) from exc
    if isinstance(payload, dict) and "data" in payload:
        return payload["data"]
    return payload


def check_response(status: int, text: str) -> None:
    """Status check for void methods: a 2xx body is ignored, JSON or not."""
    if not 200 <= status < 300:
        raise http_error(status, text)


def decode_text(status: int, text: str) -> str:
    """Returns a 2xx body as text (``text/plain`` endpoints)."""
    check_response(status, text)
    return text


def decode_redirect(resp: httpx.Response) -> str:
    """Returns the ``Location`` of a 3xx response (the redirect is not followed).

    Absolute URLs (presigned or CDN) come back untouched so their signature
    survives; a relative one is resolved against the request URL.
    """
    status = resp.status_code
    location = resp.headers.get("location")
    if 300 <= status < 400 and location:
        if _ABSOLUTE_URL.match(location):
            return location
        return str(resp.request.url.join(location))
    if not 200 <= status < 400:
        raise http_error(status, resp.text)
    raise DocsError(
        f"Expected a redirect with a Location header, got status {status}",
        status,
        parse_payload(resp.text),
    )


def decode_binary(resp: httpx.Response) -> Binary:
    """Returns a 2xx body as :class:`Binary`."""
    if not 200 <= resp.status_code < 300:
        raise http_error(resp.status_code, resp.text)
    return _binary(resp)


def decode_node_file(resp: httpx.Response) -> NodeFileResult:
    """307 → ``url``, 202 → ``restoring`` (+ ``retry_after``), other 2xx → ``content``."""
    status = resp.status_code
    if 300 <= status < 400:
        return NodeFileResult(url=decode_redirect(resp))
    if status == 202:
        return NodeFileResult(
            restoring=decode_response(status, resp.text),
            retry_after=_retry_after(resp.headers.get("retry-after")),
        )
    return NodeFileResult(content=decode_binary(resp))


def parse_payload(text: str) -> Any:
    """Parsed JSON body; the raw text when it is not JSON; ``None`` when empty."""
    if not text.strip():
        return None
    try:
        return json.loads(text)
    except ValueError:
        return text


def http_error(status: int, text: str) -> DocsError:
    payload = parse_payload(text)
    message, code = error_details(status, payload)
    return DocsError(message, status, payload, code=code)


# Platform error codes sent as ``error.message``, e.g. ``AAS-00106``.
_PLATFORM_CODE = re.compile(r"^[A-Z][A-Z0-9]*-\d+$")
_ABSOLUTE_URL = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def error_details(status: int, payload: Any) -> tuple[str, str | None]:
    """Best ``(message, platform code)`` from ``{"status":0,"error":{"message",
    "code","details"}}`` or ``{"message": "..."}``; a generic message otherwise.

    When ``error.message`` is a platform code (``AAS-00106``) it becomes the
    code and a non-empty ``details`` the message.
    """
    code: str | None = None
    candidates: list[Any] = []
    if isinstance(payload, dict):
        error = payload.get("error")
        if isinstance(error, dict):
            message, details = error.get("message"), error.get("details")
            if isinstance(message, str) and _PLATFORM_CODE.match(message.strip()):
                code = message.strip()
                candidates += [details, message]
            else:
                candidates += [message, details]
        else:
            candidates.append(error)
        candidates.append(payload.get("message"))
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return candidate, code
    return f"Request failed with status {status}", code


def transport_error(exc: httpx.HTTPError) -> DocsError:
    return DocsError(str(exc) or type(exc).__name__, 0, None)


_QUOTED_FILENAME = re.compile(r'filename\s*=\s*"((?:\\.|[^"\\])*)"', re.IGNORECASE)
_TOKEN_FILENAME = re.compile(r"filename\s*=\s*([^;\s\"]+)", re.IGNORECASE)


def file_name_from(headers: httpx.Headers) -> str | None:
    """``X-File-Name``, else the ``Content-Disposition`` ``filename``."""
    name = headers.get("x-file-name")
    if name:
        return name
    disposition = headers.get("content-disposition") or ""
    match = _QUOTED_FILENAME.search(disposition)
    if match:
        return re.sub(r"\\(.)", r"\1", match.group(1))
    match = _TOKEN_FILENAME.search(disposition)
    return match.group(1) if match else None


def _binary(resp: httpx.Response) -> Binary:
    return Binary(
        data=resp.content,
        content_type=resp.headers.get("content-type") or "application/octet-stream",
        file_name=file_name_from(resp.headers),
    )


def _retry_after(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value.strip())
    except ValueError:
        return None


def _dumps(value: Any) -> str:
    # Compact, non-ASCII-escaping output like JavaScript's JSON.stringify.
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False, default=_json_default)


def _json_default(value: Any) -> Any:
    # Methods accept ``Mapping`` bodies; ``json`` only serialises real dicts.
    if isinstance(value, Mapping):
        return dict(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")
