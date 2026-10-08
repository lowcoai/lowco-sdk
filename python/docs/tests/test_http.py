"""Transport behaviour: config, headers, encoding, envelope unwrapping, errors,
redirects, binary downloads, 202 restoring results and multipart uploads."""

from __future__ import annotations

import io
import json
from collections.abc import Callable
from types import MappingProxyType
from typing import Any

import httpx
import pytest

from lowcoai.docs import (
    API_PREFIX,
    BASE_URL,
    HEADER_ORG_ID,
    AsyncDocsClient,
    AsyncHttpClient,
    Binary,
    DocsClient,
    DocsError,
    HttpClient,
    NodeFileResult,
    UploadFile,
)
from lowcoai.docs import types as docs_types
from lowcoai.docs._base import encode_query, file_name_from, seg, wildcard

from .test_resources import parse_multipart


class Recorder:
    """Captures requests and answers each with a canned response."""

    def __init__(self, respond: Callable[[httpx.Request], httpx.Response] | None = None) -> None:
        self.requests: list[httpx.Request] = []
        self._respond = respond or (lambda _req: envelope(None))

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self._respond(request)

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]


def envelope(data: Any, status: int = 200) -> httpx.Response:
    return httpx.Response(status, json={"status": 1, "data": data})


def reply(response: httpx.Response) -> Recorder:
    return Recorder(lambda _r: response)


def make_client(rec: Recorder, **kwargs: Any) -> DocsClient:
    kwargs.setdefault("org_id", "org_1")
    return DocsClient(
        "tok_123", http_client=httpx.Client(transport=httpx.MockTransport(rec)), **kwargs
    )


# --- construction -------------------------------------------------------------

CLASSES = [DocsClient, AsyncDocsClient, HttpClient, AsyncHttpClient]


@pytest.mark.parametrize("token", ["", "   "])
@pytest.mark.parametrize("cls", CLASSES)
def test_token_is_required(cls: Callable[..., Any], token: str) -> None:
    with pytest.raises(ValueError, match="token"):
        cls(token, org_id="org_1")


@pytest.mark.parametrize("org_id", ["", "   "])
@pytest.mark.parametrize("cls", CLASSES)
def test_org_id_is_required(cls: Callable[..., Any], org_id: str) -> None:
    with pytest.raises(ValueError, match="org_id"):
        cls("tok", org_id=org_id)


@pytest.mark.parametrize("cls", CLASSES)
def test_org_id_has_no_default(cls: Callable[..., Any]) -> None:
    with pytest.raises(TypeError, match="org_id"):
        cls("tok")


def test_owned_http_client_is_closed_injected_one_is_not() -> None:
    owned = DocsClient("tok", org_id="org")
    with owned:
        pass
    assert owned._http._http.is_closed

    injected = httpx.Client(transport=httpx.MockTransport(Recorder()))
    with DocsClient("tok", org_id="org", http_client=injected):
        pass
    assert not injected.is_closed
    injected.close()


# --- headers ------------------------------------------------------------------


def test_sends_default_headers_and_fixed_host() -> None:
    rec = Recorder(lambda _r: envelope({"name": "bkt"}))
    make_client(rec, headers={"X-Trace": "t1"}).buckets.get()
    req = rec.last
    assert BASE_URL == "https://api.lowco.ai"
    assert API_PREFIX == "/v1/documents"
    assert str(req.url) == "https://api.lowco.ai/v1/documents"
    assert req.headers["Accept"] == "application/json"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers[HEADER_ORG_ID] == "org_1"
    assert req.headers["X-Trace"] == "t1"
    assert "Content-Type" not in req.headers
    assert "X-User-Id" not in req.headers  # identity comes from the token
    assert req.content == b""


def test_content_type_only_when_a_json_body_is_sent() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.library.star("b", "n1")  # POST without a body
    assert "Content-Type" not in rec.last.headers
    client.folders.create("b", {"folderName": "x"})
    assert rec.last.headers["Content-Type"] == "application/json"


@pytest.mark.parametrize("key", ["Authorization", "authorization"])
def test_configured_authorization_header_wins_over_token(key: str) -> None:
    rec = Recorder()
    make_client(rec, headers={key: "Basic abc"}).buckets.get()
    assert rec.last.headers.get_list("Authorization") == ["Basic abc"]


@pytest.mark.parametrize("key", [HEADER_ORG_ID, "x-org-id"])
def test_configured_org_header_wins_over_org_id(key: str) -> None:
    rec = Recorder()
    make_client(rec, headers={key: "org_from_headers"}).buckets.get()
    assert rec.last.headers.get_list(HEADER_ORG_ID) == ["org_from_headers"]


def test_empty_configured_auth_headers_fall_back_to_config() -> None:
    rec = Recorder()
    make_client(rec, headers={"Authorization": "", "X-Org-Id": ""}).buckets.get()
    assert rec.last.headers.get_list("Authorization") == ["Bearer tok_123"]
    assert rec.last.headers.get_list(HEADER_ORG_ID) == ["org_1"]


def test_body_is_compact_utf8_json() -> None:
    rec = Recorder()
    make_client(rec).files.update("b", {"fileName": "Zoë.md", "content": "a\nb"})
    assert rec.last.content == '{"fileName":"Zoë.md","content":"a\\nb"}'.encode()


def test_mapping_bodies_are_serialised() -> None:
    rec = Recorder()
    client = make_client(rec)
    rule = MappingProxyType({"prefix": "in/", "config": MappingProxyType({"k": (1, 2)})})
    client.automation.create("b", rule)  # type: ignore[arg-type]
    assert json.loads(rec.last.content) == {"prefix": "in/", "config": {"k": [1, 2]}}
    with pytest.raises(TypeError):
        client.automation.create("b", {"config": {"bad": {1, 2}}})


# --- path and query encoding --------------------------------------------------


def test_seg_matches_encode_uri_component() -> None:
    assert seg("a b/c?d#e&f=g+h%") == "a%20b%2Fc%3Fd%23e%26f%3Dg%2Bh%25"
    assert seg("A-z_0.9!~*'()") == "A-z_0.9!~*'()"
    assert seg("ä€") == "%C3%A4%E2%82%AC"


def test_wildcard_encodes_each_segment_and_strips_leading_slash() -> None:
    assert wildcard("a b/c.txt") == "a%20b/c.txt"
    assert wildcard("/a b/c.txt") == "a%20b/c.txt"
    assert wildcard(".users/u-1/r&d #1/x?.md") == ".users/u-1/r%26d%20%231/x%3F.md"
    assert wildcard("folder/") == "folder/"


def test_single_segment_vs_wildcard_on_the_wire() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.folders.get("b", "a b/c")  # one segment: "/" encoded
    assert rec.last.url.raw_path == b"/v1/documents/b/folder/a%20b%2Fc"
    client.files.get("b", "/a b/c(1)!.txt")  # wildcard: "/" kept
    assert rec.last.url.raw_path == b"/v1/documents/b/file/a%20b/c(1)!.txt"


@pytest.mark.parametrize(
    "call",
    [
        lambda c: c.files.get("b", "a/../secret.txt"),
        lambda c: c.files.download_url("b", "./a.txt"),
        lambda c: c.folders.download_zip("b", "a/."),
        lambda c: c.app_files.delete("notes", ".."),
        lambda c: c.nodes.get(".."),
        lambda c: c.folders.get("b", "."),
        lambda c: c.buckets.stats(".."),
        lambda c: c.sharing.resolve_link("."),
    ],
)
def test_dot_segments_are_rejected_before_sending(call: Callable[[DocsClient], Any]) -> None:
    rec = Recorder()
    with pytest.raises(DocsError, match="path segment") as info:
        call(make_client(rec))
    assert (info.value.status, info.value.payload) == (0, None)
    assert rec.requests == []


def test_dots_inside_segments_and_queries_are_fine() -> None:
    rec = Recorder()
    client = make_client(rec)
    client.files.get("b", ".users/u-1/..notes/a..b.txt")
    assert rec.last.url.raw_path == b"/v1/documents/b/file/.users/u-1/..notes/a..b.txt"
    client.files.delete_by_path("b", "a/../b")  # query values are not normalised
    assert rec.last.url.params["path"] == "a/../b"


def test_none_query_values_are_omitted() -> None:
    rec = Recorder(lambda _r: envelope([]))
    client = make_client(rec)
    client.folders.list("b", prefix=None, sizes=None)
    assert rec.last.url.query == b""
    client.automation.jobs("b", config_id=None, limit=5)
    assert dict(rec.last.url.params) == {"limit": "5"}


def test_query_values_are_url_encoded() -> None:
    rec = Recorder(lambda _r: envelope([]))
    make_client(rec).search("b", "a&b c")
    assert dict(rec.last.url.params) == {"q": "a&b c"}
    assert b"a%26b" in rec.last.url.query


def test_encode_query() -> None:
    assert encode_query(None) is None
    assert encode_query({}) is None
    assert encode_query({"skip": None}) is None
    assert encode_query(
        {"n": 2, "r": 2.5, "w": 3.0, "t": True, "f": False, "s": "x", "l": ["a", "é"], "x": None}
    ) == {"n": "2", "r": "2.5", "w": "3", "t": "true", "f": "false", "s": "x", "l": '["a","é"]'}


# --- JSON responses -----------------------------------------------------------


@pytest.mark.parametrize(
    ("response", "expected"),
    [
        (httpx.Response(200, json={"status": 1, "data": {"name": "b"}}), {"name": "b"}),
        (httpx.Response(200, json={"status": 1, "data": None}), None),
        (httpx.Response(200, json={"status": 1, "data": "file deleted"}), "file deleted"),
        (httpx.Response(200, json={"name": "no envelope"}), {"name": "no envelope"}),
        (httpx.Response(200, json=[{"id": "d1"}]), [{"id": "d1"}]),
        (httpx.Response(200, text=""), None),
        (httpx.Response(204), None),
    ],
)
def test_envelope_unwrapping(response: httpx.Response, expected: Any) -> None:
    assert make_client(reply(response)).buckets.get() == expected


def test_non_json_success_body_raises_with_status_and_raw_text() -> None:
    client = make_client(reply(httpx.Response(200, text="not json")))
    with pytest.raises(DocsError) as info:
        client.nodes.get("n1")
    assert info.value.status == 200
    assert info.value.payload == "not json"
    assert isinstance(info.value.__cause__, ValueError)


def test_void_methods_ignore_success_bodies() -> None:
    client = make_client(reply(httpx.Response(200, json={"status": 1, "data": None})))
    assert client.triggers.delete("t1") is None  # type: ignore[func-returns-value]
    client = make_client(reply(httpx.Response(204)))
    assert client.webhooks.delete("w1") is None  # type: ignore[func-returns-value]


# --- errors -------------------------------------------------------------------

ENVELOPE_ERROR = {
    "data": None,
    "status": 0,
    "error": {"message": "AAS-00106", "code": 400, "details": "bucket name is required"},
}


@pytest.mark.parametrize(
    ("status", "body", "message", "code"),
    [
        (400, ENVELOPE_ERROR, "bucket name is required", "AAS-00106"),
        (
            404,
            {"status": 0, "error": {"message": "AAS-00102", "code": 404}},
            "AAS-00102",
            "AAS-00102",
        ),
        (
            403,
            {"message": "you don't have access to this item"},
            "you don't have access to this item",
            None,
        ),
        (
            412,
            {
                "status": 0,
                "data": {"currentEtag": "e2", "updatedBy": "u-2"},
                "error": {"message": "the file was changed by someone else", "code": 412},
            },
            "the file was changed by someone else",
            None,
        ),
        (
            500,
            {"status": 0, "error": {"message": "", "details": ""}},
            "Request failed with status 500",
            None,
        ),
        (
            400,
            {"status": 0, "error": {"message": "invalid onConflict", "details": "got 'x'"}},
            "invalid onConflict",
            None,
        ),
        (
            400,
            {"status": 0, "error": {"message": "", "details": "only details"}},
            "only details",
            None,
        ),
        (500, {"unexpected": True}, "Request failed with status 500", None),
        (500, ["not", "an", "object"], "Request failed with status 500", None),
    ],
)
def test_error_messages_from_both_body_shapes(
    status: int, body: Any, message: str, code: str | None
) -> None:
    client = make_client(reply(httpx.Response(status, json=body)))
    with pytest.raises(DocsError) as info:
        client.files.update("b", {"fileName": "a.md", "ifMatch": "e1"})
    err = info.value
    assert err.status == status
    assert err.message == message
    assert err.code == code
    assert str(err) == message
    assert err.payload == body
    assert f"status={status}" in repr(err)


def test_error_with_non_json_body_keeps_raw_text() -> None:
    client = make_client(reply(httpx.Response(502, text="<html>Bad gateway</html>")))
    with pytest.raises(DocsError) as info:
        client.buckets.get()
    assert info.value.status == 502
    assert info.value.message == "Request failed with status 502"
    assert info.value.payload == "<html>Bad gateway</html>"


def test_error_with_empty_body_has_no_payload() -> None:
    with pytest.raises(DocsError) as info:
        make_client(reply(httpx.Response(401))).buckets.get()
    assert (info.value.status, info.value.payload) == (401, None)


def test_void_methods_still_raise_on_errors() -> None:
    client = make_client(reply(httpx.Response(404, json={"message": "webhook not found"})))
    with pytest.raises(DocsError) as info:
        client.webhooks.delete("w1")
    assert (info.value.status, info.value.message) == (404, "webhook not found")


@pytest.mark.parametrize(
    "exc", [httpx.ConnectError("connection refused"), httpx.ReadTimeout("timed out")]
)
def test_transport_failures_are_wrapped_with_status_0(exc: httpx.HTTPError) -> None:
    def boom(_req: httpx.Request) -> httpx.Response:
        raise exc

    with pytest.raises(DocsError) as info:
        make_client(Recorder(boom)).files.download_url("b", "a.txt")
    assert info.value.status == 0
    assert info.value.payload is None
    assert info.value.message == str(exc)
    assert info.value.__cause__ is exc


def test_transport_failure_without_text_uses_exception_name() -> None:
    def boom(_req: httpx.Request) -> httpx.Response:
        raise httpx.PoolTimeout("")

    with pytest.raises(DocsError) as info:
        make_client(Recorder(boom)).buckets.get()
    assert (info.value.message, info.value.status) == ("PoolTimeout", 0)


@pytest.mark.parametrize(("timeout", "expected"), [(5.0, 5.0), (None, None)])
def test_timeout_is_applied_per_request(timeout: float | None, expected: float | None) -> None:
    rec = Recorder()
    make_client(rec, timeout=timeout).buckets.get()
    assert rec.last.extensions["timeout"] == {
        "connect": expected,
        "read": expected,
        "write": expected,
        "pool": expected,
    }


# --- health -------------------------------------------------------------------


def test_health_is_plain_text_outside_the_prefix() -> None:
    rec = reply(httpx.Response(200, text="Working!", headers={"Content-Type": "text/plain"}))
    assert make_client(rec).health() == "Working!"
    assert str(rec.last.url) == "https://api.lowco.ai/health"
    assert rec.last.headers["Accept"] == "*/*"


def test_health_raises_on_error() -> None:
    with pytest.raises(DocsError) as info:
        make_client(reply(httpx.Response(503, text="down"))).health()
    assert (info.value.status, info.value.payload) == (503, "down")


# --- redirect URL methods -----------------------------------------------------

SIGNED = "https://cdn.example.com/b/a.pdf?X-Amz-Signature=abc"


def test_redirect_is_returned_not_followed_even_by_a_following_client() -> None:
    rec = Recorder(
        lambda r: (
            httpx.Response(307, headers={"Location": SIGNED})
            if r.url.host == "api.lowco.ai"
            else httpx.Response(200, content=b"file bytes")
        )
    )
    http = httpx.Client(transport=httpx.MockTransport(rec), follow_redirects=True)
    client = DocsClient("tok", org_id="org", http_client=http)
    assert client.files.download_url("b", "docs/a.pdf") == SIGNED
    assert client.files.preview_url("b", "docs/a.pdf") == SIGNED
    assert client.sharing.resolve_link("tok_1") == SIGNED
    assert [r.url.host for r in rec.requests] == ["api.lowco.ai"] * 3


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
def test_any_redirect_status_yields_its_location(status: int) -> None:
    client = make_client(reply(httpx.Response(status, headers={"Location": "/relative/x"})))
    assert client.files.download_url("b", "a.txt") == "https://api.lowco.ai/relative/x"


@pytest.mark.parametrize(
    "response",
    [httpx.Response(200, json={"status": 1, "data": "x"}), httpx.Response(307)],
)
def test_redirect_method_without_location_raises(response: httpx.Response) -> None:
    with pytest.raises(DocsError, match="Expected a redirect") as info:
        make_client(reply(response)).files.preview_url("b", "a.docx")
    assert info.value.status == response.status_code


def test_redirect_method_maps_errors() -> None:
    client = make_client(reply(httpx.Response(501, json={"message": "no converter configured"})))
    with pytest.raises(DocsError) as info:
        client.files.preview_url("b", "a.docx")
    assert (info.value.status, info.value.message) == (501, "no converter configured")


# --- binary downloads ---------------------------------------------------------


def test_binary_download_prefers_x_file_name() -> None:
    rec = reply(
        httpx.Response(
            200,
            content=b"PK\x03\x04",
            headers={
                "Content-Type": "application/zip",
                "X-File-Name": "Q3 report.zip",
                "Content-Disposition": 'attachment; filename="other.zip"',
            },
        )
    )
    result = make_client(rec).folders.download_zip("b", "reports/Q3")
    assert result == Binary(b"PK\x03\x04", "application/zip", "Q3 report.zip")
    assert rec.last.headers["Accept"] == "*/*"


@pytest.mark.parametrize(
    ("headers", "expected"),
    [
        ({"Content-Disposition": 'attachment; filename="a \\"b\\".zip"'}, 'a "b".zip'),
        ({"Content-Disposition": "inline; filename=plain.txt"}, "plain.txt"),
        ({"Content-Disposition": "attachment"}, None),
        ({}, None),
    ],
)
def test_file_name_from_content_disposition(headers: dict[str, str], expected: str | None) -> None:
    assert file_name_from(httpx.Headers(headers)) == expected


def test_binary_without_content_type_defaults_to_octet_stream() -> None:
    result = make_client(reply(httpx.Response(200, content=b"x"))).folders.download_zip("b", "f")
    assert result.content_type == "application/octet-stream"
    assert result.file_name is None


def test_binary_download_maps_json_errors() -> None:
    client = make_client(
        reply(
            httpx.Response(
                404,
                json={
                    "status": 0,
                    "error": {"message": "AAS-00102", "details": "folder not found"},
                },
            )
        )
    )
    with pytest.raises(DocsError) as info:
        client.folders.download_zip("b", "missing")
    assert (info.value.status, info.value.message) == (404, "folder not found")


# --- node files (permalinks) --------------------------------------------------

RESTORING: docs_types.ArchiveRestoring = {
    "status": "restoring",
    "nodeId": "n1",
    "name": "q3.pdf",
    "retryAfterSeconds": 300,
    "message": "this file was moved to cold storage; a restore has been requested",
}


def test_node_resolve_redirect_yields_url() -> None:
    rec = reply(httpx.Response(307, headers={"Location": SIGNED}))
    result = make_client(rec).nodes.resolve("n1", download=True)
    assert result == NodeFileResult(url=SIGNED)
    assert rec.last.url.params["download"] == "1"


def test_node_content_yields_bytes_and_name() -> None:
    rec = reply(
        httpx.Response(
            200,
            content=b"%PDF-1.7",
            headers={
                "Content-Type": "application/pdf",
                "X-File-Name": "q3.pdf",
                "Content-Disposition": 'inline; filename="q3.pdf"',
            },
        )
    )
    result = make_client(rec).nodes.content("n1")
    assert result == NodeFileResult(content=Binary(b"%PDF-1.7", "application/pdf", "q3.pdf"))
    assert (result.url, result.restoring, result.retry_after) == (None, None, None)


def test_node_resolve_restored_from_cold_storage_yields_bytes() -> None:
    rec = reply(httpx.Response(200, content=b"data", headers={"Content-Type": "text/plain"}))
    result = make_client(rec).nodes.resolve("n1")
    assert result.content == Binary(b"data", "text/plain", None)
    assert result.url is None


@pytest.mark.parametrize(("retry_after", "expected"), [("300", 300), (None, None), ("soon", None)])
def test_node_202_restoring(retry_after: str | None, expected: int | None) -> None:
    headers = {"Retry-After": retry_after} if retry_after is not None else {}
    response = httpx.Response(202, json={"status": 1, "data": RESTORING}, headers=headers)
    for call in ("resolve", "content"):
        result = getattr(make_client(reply(response)).nodes, call)("n1")
        assert result == NodeFileResult(restoring=RESTORING, retry_after=expected)
        assert (result.url, result.content) == (None, None)


@pytest.mark.parametrize("status", [400, 404, 410, 502])
def test_node_file_errors(status: int) -> None:
    client = make_client(reply(httpx.Response(status, json={"message": f"failed {status}"})))
    with pytest.raises(DocsError) as info:
        client.nodes.content("n1")
    assert (info.value.status, info.value.message) == (status, f"failed {status}")


# --- multipart uploads --------------------------------------------------------


def test_upload_file_field_names_and_response() -> None:
    doc = {"id": "n1", "name": "plan.md", "path": "projects/plan.md"}
    rec = Recorder(lambda _r: envelope(doc))
    result = make_client(rec).files.upload(
        "b", UploadFile("plan.md", b"# Plan", "text/markdown"), parent_id="projects"
    )
    assert result == doc
    assert parse_multipart(rec.last) == [
        ("ParentID", None, None, b"projects"),
        ("file", "plan.md", "text/markdown", b"# Plan"),
    ]


def test_upload_streams_file_objects() -> None:
    rec = Recorder()
    make_client(rec).app_files.upload("notes", ("big.bin", io.BytesIO(b"\x00" * 70_000)))
    ((name, filename, _ctype, data),) = parse_multipart(rec.last)
    assert (name, filename, len(data)) == ("file", "big.bin", 70_000)


def test_upload_ignores_a_configured_content_type() -> None:
    rec = Recorder()
    client = make_client(rec, headers={"Content-Type": "application/json"})
    client.files.upload("b", ("a.txt", b"a"))
    assert rec.last.headers.get_list("Content-Type")[0].startswith("multipart/form-data; boundary=")
    assert parse_multipart(rec.last) == [("file", "a.txt", "text/plain", b"a")]


def test_folder_upload_needs_one_relative_path_per_file() -> None:
    rec = Recorder()
    with pytest.raises(ValueError, match="relative_paths"):
        make_client(rec).folders.upload("b", [("a", b"a"), ("b", b"b")], relative_paths=["x/a"])
    assert rec.requests == []


def test_upload_rejects_malformed_files() -> None:
    with pytest.raises(TypeError, match="UploadFile"):
        make_client(Recorder()).files.upload("b", b"raw bytes")  # type: ignore[arg-type]
    with pytest.raises(TypeError, match="UploadFile"):
        make_client(Recorder()).files.upload("b", ("only-name",))  # type: ignore[arg-type]


def test_multipart_errors_are_mapped() -> None:
    body = {"status": 0, "error": {"message": "AAS-00106", "details": "no files uploaded"}}
    client = make_client(reply(httpx.Response(400, json=body)))
    with pytest.raises(DocsError) as info:
        client.folders.upload("b", [("a", b"a")])
    assert (info.value.status, info.value.message) == (400, "no files uploaded")


# --- HttpClient escape hatch --------------------------------------------------


def test_http_client_request_with_per_request_headers_and_relative_path() -> None:
    rec = Recorder(lambda _r: envelope({"ok": True}))
    http = HttpClient(
        "tok_123",
        org_id="org_1",
        headers={"X-Trace": "cfg"},
        http_client=httpx.Client(transport=httpx.MockTransport(rec)),
    )
    result = http.request(
        "POST",
        "v1/documents/custom",
        {"a": 1},
        query={"x": 1},
        headers={"X-Trace": "req", "X-Org-Id": "org_req"},
    )
    assert result == {"ok": True}
    req = rec.last
    assert str(req.url) == "https://api.lowco.ai/v1/documents/custom?x=1"
    assert req.headers["X-Trace"] == "req"
    assert req.headers[HEADER_ORG_ID] == "org_req"
    assert json.loads(req.content) == {"a": 1}
    assert http.request_void("DELETE", "/v1/documents/custom") is None  # type: ignore[func-returns-value]


# --- types --------------------------------------------------------------------


def test_types_module_exports_are_sorted_and_resolvable() -> None:
    assert docs_types.__all__ == sorted(docs_types.__all__)
    for name in docs_types.__all__:
        assert hasattr(docs_types, name), name
    assert docs_types.HEADER_ORG_ID == "X-Org-Id"
    assert docs_types.Document.__required_keys__ == frozenset()
    assert "eventTypes" in docs_types.WebhookRequest.__optional_keys__


def test_typed_usage() -> None:
    """Type-checked by mypy: TypedDict bodies and responses flow between calls."""
    doc = {"id": "n1", "name": "todo.md", "path": "notes/todo.md", "etag": "e1", "role": "owner"}
    client = make_client(Recorder(lambda _r: envelope(doc)))
    read: docs_types.FileContent = client.files.read("b", "notes/todo.md", meta=True)
    save: docs_types.UpdateFileRequest = {
        "parentName": "notes",
        "fileName": "todo.md",
        "content": "# Todo",
        "ifMatch": read["etag"],
    }
    saved = client.files.update("b", save)
    assert saved["name"] == "todo.md"
    hook: docs_types.WebhookRequest = {
        "url": "https://h.example.com",
        "method": "POST",
        "prefix": "in/",
        "eventTypes": ["create"],
        "headers": {"X-Secret": "s"},
    }
    client.webhooks.create(hook)
    env: docs_types.ApiEnvelope[list[docs_types.Document]] = {"status": 1, "data": [saved]}
    assert env["data"][0]["path"] == "notes/todo.md"
    upload: docs_types.FileInput = UploadFile("a.txt", io.BytesIO(b"a"), "text/plain")
    assert isinstance(upload, UploadFile)
