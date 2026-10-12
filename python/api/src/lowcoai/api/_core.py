"""The transport every generated method calls: auth, the envelope, typed
errors, file inputs (multipart or by reference), job waiting, pagination and
retries. Standard library only."""

from __future__ import annotations

import json
import mimetypes
import os
import time
import uuid
from dataclasses import dataclass, field
from typing import IO, Any, Dict, Generic, Iterator, List, Mapping, Optional, Tuple, TypeVar, Union
from urllib import error as urlerror
from urllib import parse, request

from ._errors import LowcoApiError, LowcoJobError, LowcoTimeoutError
from ._files import FileRef, Files

DEFAULT_BASE_URL = "https://api.lowco.ai"
SDK_VERSION = "1.1.0"
_TERMINAL = {"succeeded", "failed", "cancelled"}

T = TypeVar("T")

FileInput = Union[FileRef, bytes, bytearray, memoryview, IO[bytes]]
"""A file input: build one with ``Files``, or pass bytes or a binary file object."""


@dataclass
class Answer(Generic[T]):
    """An operation's answer: the result inline (200), a job (202), or the output file's bytes."""

    status: int
    data: Optional[T] = None
    """The result, when the operation finished in the request."""
    job: Optional[Dict[str, Any]] = None
    """The job, when the operation was accepted as one (status 202)."""
    bytes: Optional[bytes] = None
    """The output file, when ``accept`` asked for its type."""
    content_type: Optional[str] = None
    request_id: Optional[str] = None
    replayed: bool = False
    """True when an Idempotency-Key replayed an earlier submission."""
    credits_used: Optional[str] = None


@dataclass
class _Raw:
    status: int
    headers: Mapping[str, str]
    body: Any = None
    content: Optional[bytes] = None
    content_type: str = ""
    location: Optional[str] = None


class _NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


def _normalise(value: Any) -> FileRef:
    if isinstance(value, FileRef):
        return value
    if isinstance(value, (bytes, bytearray, memoryview)):
        return Files.bytes(bytes(value))
    if hasattr(value, "read"):
        return Files.stream(value)
    raise LowcoApiError("A file input must be built with Files (path, bytes, stream, url, id, base64)", status=0, reason="invalid_param")


def _multipart(fields: List[Tuple[str, str]], files: List[Tuple[str, str, str, bytes]]) -> Tuple[bytes, str]:
    boundary = "lowco" + uuid.uuid4().hex
    out = bytearray()
    for name, value in fields:
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n".encode()
        out += value.encode() + b"\r\n"
    for name, filename, mime, data in files:
        safe = filename.replace('"', "_")
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{safe}\"\r\nContent-Type: {mime}\r\n\r\n".encode()
        out += data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


class Core:
    """Sends requests and decodes answers."""

    def __init__(self, api_key: Optional[str] = None, *, base_url: Optional[str] = None, timeout: float = 60.0, max_retries: int = 2) -> None:
        key = api_key or os.environ.get("LOWCO_API_KEY")
        if not key:
            raise LowcoApiError("api_key is required (lc_live_… or lc_test_…): pass it or set LOWCO_API_KEY", status=0, reason="missing_key")
        self._key = key
        self.base_url = (base_url or os.environ.get("LOWCO_API_BASE_URL") or DEFAULT_BASE_URL).rstrip("/")
        self._timeout = timeout
        self._max_retries = max_retries
        self._opener = request.build_opener()
        self._no_redirect = request.build_opener(_NoRedirect)

    def _url(self, path: str, query: Optional[Mapping[str, Any]] = None) -> str:
        url = path if path.startswith("http") else self.base_url + path
        q = {k: ("true" if v is True else "false" if v is False else v) for k, v in (query or {}).items() if v is not None}
        if q:
            url += ("&" if "?" in url else "?") + parse.urlencode(q)
        return url

    def _send(
        self,
        method: str,
        url: str,
        *,
        body: Optional[bytes] = None,
        headers: Optional[Dict[str, str]] = None,
        auth: bool = True,
        follow: bool = True,
        request_id: Optional[str] = None,
        idempotency_key: Optional[str] = None,
        timeout: Optional[float] = None,
        retry_safe: Optional[bool] = None,
    ) -> _Raw:
        h = {"X-Client-User-Agent": f"lowcoai-api-python/{SDK_VERSION}", "Accept": "application/json"}
        h.update(headers or {})
        if auth:
            h["Authorization"] = f"Bearer {self._key}"
        if request_id:
            h["X-Request-Id"] = request_id
        if idempotency_key:
            h["Idempotency-Key"] = idempotency_key
        safe = (method == "GET" if retry_safe is None else retry_safe) or bool(idempotency_key)
        attempt = 0
        while True:
            req = request.Request(url, data=body, method=method, headers=h)
            opener = self._opener if follow else self._no_redirect
            try:
                with opener.open(req, timeout=timeout or self._timeout) as resp:
                    return self._read(resp.status, resp.headers, resp.read())
            except urlerror.HTTPError as e:
                try:
                    raw = self._read(e.code, e.headers, e.read() if e.fp else b"")
                finally:
                    e.close()
                if 300 <= e.code < 400:
                    return raw
                err = self._error(raw)
                if safe and attempt < self._max_retries and e.code in (429, 503):
                    time.sleep(min(err.retry_after if err.retry_after is not None else 1, 30))
                    attempt += 1
                    continue
                raise err from None
            except (urlerror.URLError, TimeoutError, OSError) as e:
                if safe and attempt < self._max_retries:
                    time.sleep(0.5 * 2**attempt)
                    attempt += 1
                    continue
                raise LowcoApiError(f"Network error: {e}", status=0, reason="service_unavailable", retryable=True) from e

    def _read(self, status: int, headers: Any, content: bytes) -> _Raw:
        ctype = headers.get("Content-Type", "") if headers else ""
        hdrs = {k.lower(): v for k, v in headers.items()} if headers else {}
        raw = _Raw(status=status, headers=hdrs, content_type=ctype, location=hdrs.get("location"))
        if "json" in ctype:
            try:
                raw.body = json.loads(content.decode("utf-8")) if content else None
            except ValueError:
                raw.body = content.decode("utf-8", "replace")
        else:
            raw.content = content
        return raw

    def _error(self, raw: _Raw) -> LowcoApiError:
        ra = raw.headers.get("retry-after")
        retry_after = int(ra) if ra and ra.isdigit() else None
        e = raw.body.get("error") if isinstance(raw.body, dict) else None
        rid = (e or {}).get("request_id") or raw.headers.get("x-request-id")
        if isinstance(e, dict):
            return LowcoApiError(
                str(e.get("message") or f"Request failed with status {raw.status}"),
                status=raw.status, reason=str(e.get("reason") or "internal_error"), param=e.get("param"),
                details=e.get("details"), request_id=rid, doc_url=e.get("doc_url"), retryable=e.get("retryable"),
                retry_after=retry_after, payload=raw.body,
            )
        text = raw.body if isinstance(raw.body, str) else (raw.content or b"").decode("utf-8", "replace")
        return LowcoApiError(text or f"Request failed with status {raw.status}", status=raw.status,
                             reason="internal_error" if raw.status >= 500 else "invalid_param", request_id=rid,
                             retry_after=retry_after, payload=raw.body if raw.body is not None else text)

    @staticmethod
    def _data(raw: _Raw) -> Any:
        if not isinstance(raw.body, dict) or raw.body.get("status") != 1:
            raise LowcoApiError("The API answered without a success envelope", status=raw.status, reason="internal_error", payload=raw.body)
        return raw.body.get("data")

    def call(self, method: str, path: str, *, query: Optional[Mapping[str, Any]] = None, json: Any = None,
             idempotency_key: Optional[str] = None, request_id: Optional[str] = None) -> Any:
        body = None
        headers: Dict[str, str] = {}
        if json is not None:
            body = _json_bytes(json)
            headers["Content-Type"] = "application/json"
        raw = self._send(method, self._url(path, query), body=body, headers=headers,
                         idempotency_key=idempotency_key, request_id=request_id)
        return self._data(raw)

    def upload(self, path: str, file: FileInput, *, request_id: Optional[str] = None) -> Any:
        ref = _normalise(file)
        if not ref.is_local:
            raise LowcoApiError("upload takes a local file (path, bytes or stream)", status=0, reason="invalid_param", param="file")
        name, mime, data = ref.read()
        fields = [("password", ref.password)] if ref.password else []
        body, ctype = _multipart(fields, [("file", name, mime, data)])
        return self._data(self._send("POST", self._url(path), body=body, headers={"Content-Type": ctype}, request_id=request_id))

    def redirect(self, path: str, *, request_id: Optional[str] = None) -> str:
        raw = self._send("GET", self._url(path), follow=False, request_id=request_id)
        if not raw.location:
            raise LowcoApiError("The API answered without a Location", status=raw.status, reason="internal_error")
        return raw.location

    def download(self, url: str) -> bytes:
        raw = self._send("GET", url, auth=False, headers={"Accept": "*/*"})
        if raw.content is not None:
            return raw.content
        return _json_bytes(raw.body)

    def operation(self, path: str, params: Dict[str, Any], *, input_kind: str, extra: List[str],
                  mode: Optional[str] = None, idempotency_key: Optional[str] = None, accept: Optional[str] = None,
                  request_id: Optional[str] = None, timeout: Optional[float] = None) -> Answer[Any]:
        rest = {k: v for k, v in params.items() if v is not None}
        named: List[Tuple[str, FileRef]] = []
        many: Optional[List[FileRef]] = None
        if input_kind == "file":
            if "file" not in rest:
                raise LowcoApiError("file is required", status=0, reason="missing_param", param="file")
            named.append(("file", _normalise(rest.pop("file"))))
        elif input_kind == "files":
            files = rest.pop("files", None)
            if not files:
                raise LowcoApiError("files is required", status=0, reason="missing_param", param="files")
            many = [_normalise(f) for f in files]
        for x in extra:
            if x in rest:
                named.append((x, _normalise(rest.pop(x))))
        refs = [r for _, r in named] + (many or [])
        local = sum(1 for r in refs if r.is_local)
        if 0 < local < len(refs):
            def up(r: FileRef) -> FileRef:
                if not r.is_local:
                    return r
                stored = self.upload("/v1/files", r)
                return Files.id(stored["file_id"], password=r.password)
            named = [(f, up(r)) for f, r in named]
            many = [up(r) for r in many] if many is not None else None
        headers: Dict[str, str] = {}
        if accept:
            headers["Accept"] = accept
        if local and local == len(refs):
            fields: List[Tuple[str, str]] = []
            parts: List[Tuple[str, str, str, bytes]] = []
            for fname, r in named:
                name, mime, data = r.read()
                parts.append((fname, name, mime, data))
                if fname == "file" and r.password:
                    fields.append(("password", r.password))
            for r in many or []:
                name, mime, data = r.read()
                parts.append(("files[]", name, mime, data))
            if "callback_url" in rest:
                fields.append(("callback_url", str(rest.pop("callback_url"))))
            fields.append(("options", json.dumps(rest)))
            body, ctype = _multipart(fields, parts)
            headers["Content-Type"] = ctype
        else:
            payload = dict(rest)
            for fname, r in named:
                if fname == "file":
                    payload.update(r.reference())
                else:
                    payload[fname] = r.reference()
            if many is not None:
                payload["files"] = [r.reference() for r in many]
            body = _json_bytes(payload)
            headers["Content-Type"] = "application/json"
        raw = self._send("POST", self._url(path, {"mode": mode} if mode else None), body=body, headers=headers,
                         idempotency_key=idempotency_key, request_id=request_id, timeout=timeout, retry_safe=False)
        answer: Answer[Any] = Answer(status=raw.status, request_id=raw.headers.get("x-request-id"),
                                     replayed=raw.headers.get("idempotent-replayed") == "true",
                                     credits_used=raw.headers.get("x-lowco-credits-used"))
        if raw.content is not None:
            answer.bytes = raw.content
            answer.content_type = raw.content_type
        elif raw.status == 202:
            answer.job = self._data(raw)
        else:
            answer.data = self._data(raw)
        return answer

    def paginate(self, path: str, query: Mapping[str, Any], *, request_id: Optional[str] = None) -> Iterator[Any]:
        cursor: Optional[str] = None
        while True:
            page = self.call("GET", path, query={**query, "cursor": cursor}, request_id=request_id)
            for item in page["items"]:
                yield item
            cursor = page.get("next_cursor")
            if not cursor:
                return

    def wait_for_job(self, job_id: str, *, timeout: float = 300.0, max_interval: float = 10.0) -> Dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            raw = self._send("GET", self._url(f"/v1/jobs/{parse.quote(job_id, safe='')}"))
            job = self._data(raw)
            if job["status"] in _TERMINAL:
                if job["status"] == "succeeded":
                    return job  # type: ignore[no-any-return]
                e = job.get("error") or {}
                raise LowcoJobError(
                    e.get("message") or f"Job {job_id} was {job['status']}", job=job, status=e.get("code") or 409,
                    reason=e.get("reason") or "invalid_state", param=e.get("param"), details=e.get("details"),
                    doc_url=e.get("doc_url"), retryable=e.get("retryable"), request_id=raw.headers.get("x-request-id"),
                )
            ra = raw.headers.get("retry-after", "2")
            interval = float(ra) if ra.replace(".", "", 1).isdigit() else 2.0
            left = deadline - time.monotonic()
            if left <= 0:
                raise LowcoTimeoutError(job_id, timeout)
            time.sleep(max(0.0, min(interval, max_interval, left)))

    def wait_for_result(self, answer: Answer[T], *, timeout: float = 300.0, max_interval: float = 10.0) -> T:
        if answer.data is not None:
            return answer.data
        if answer.job is not None:
            job = self.wait_for_job(answer.job["job_id"], timeout=timeout, max_interval=max_interval)
            return job["result"]  # type: ignore[no-any-return]
        raise LowcoApiError("The answer carries bytes, not a result", status=answer.status, reason="invalid_param")


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def guess_mime(name: str) -> str:
    return mimetypes.guess_type(name)[0] or "application/octet-stream"
