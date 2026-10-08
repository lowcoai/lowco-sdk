"""Every client and resource method: verb, path (with encoded params), body,
query and result decoding.

The same table drives the sync client and the asyncio client.
"""

from __future__ import annotations

import inspect
import json
from collections.abc import Callable
from dataclasses import dataclass, field
from email.parser import BytesParser
from email.policy import default as email_policy
from typing import Any

import httpx
import pytest

from lowcoai.docs import AsyncDocsClient, Binary, DocsClient, NodeFileResult, UploadFile

NO_BODY = object()
P = "/v1/documents"
B = "my bucket"  # bucket names are encoded like every single-segment param
EB = "my%20bucket"
ID = "a/b c"  # single-segment params: "/" is encoded too
E = "a%2Fb%20c"
PATH = "/dir one/sub/r&d ä.txt"  # wildcard params: each segment encoded, "/" kept
EP = "dir%20one/sub/r%26d%20%C3%A4.txt"
DATA = {"id": "x1", "ok": True}
LOCATION = "https://cdn.example.com/signed/x1?sig=abc"
ZIP = b"PK\x03\x04zip-bytes"

FOLDER: dict[str, Any] = {"parentName": "projects", "folderName": "2026/q4"}
RENAME: dict[str, Any] = {"parentName": "projects", "oldName": "a.md", "newName": "b.md"}
BLANK: dict[str, Any] = {"parentName": "notes", "fileName": "todo.md"}
SAVE: dict[str, Any] = {
    "parentName": "notes",
    "fileName": "todo.md",
    "content": "# Todo",
    "ifMatch": "etag-1",
}
DUP: dict[str, Any] = {"path": "projects/plan.md", "type": "file"}
SHARE: dict[str, Any] = {
    "path": ".users/u1/q3.pdf",
    "type": "file",
    "subjectType": "user",
    "subjectId": "u2",
    "role": "viewer",
}
LINK: dict[str, Any] = {"path": ".users/u1/q3.pdf", "type": "file", "expiresAt": "2026-12-31"}
RULE: dict[str, Any] = {
    "prefix": "invoices/",
    "pipelineType": "custom_workflow",
    "workflowId": "wf_1",
    "eventTypes": ["create", "update"],
    "config": {"lang": "en"},
}
SWEEP: dict[str, Any] = {"prefix": "skills", "olderThanDays": 30, "limit": 100}
TRIGGER: dict[str, Any] = {"eventType": "create", "workflowId": "wf_1", "prefix": "in/"}
HOOK: dict[str, Any] = {
    "url": "https://hooks.example.com/d",
    "method": "POST",
    "prefix": "uploads/",
    "eventTypes": ["create", "delete"],
    "headers": {"X-Secret": "s"},
    "active": True,
}

# (field name, filename or None for text fields, content type or None, bytes)
Part = tuple[str, str | None, str | None, bytes]


@dataclass(frozen=True)
class Case:
    name: str  # "<resource attr>.<method>[variant]" or "<client method>"
    call: Callable[[Any], Any]
    method: str
    path: str
    body: Any = NO_BODY
    query: dict[str, str] = field(default_factory=dict)
    # How the response is decoded: json | void | text | redirect | binary | node.
    kind: str = "json"
    multipart: list[Part] | None = None


CASES: list[Case] = [
    # client
    Case("health", lambda c: c.health(), "GET", "/health", kind="text"),
    Case(
        "search",
        lambda c: c.search(B, "q3 report"),
        "GET",
        f"{P}/{EB}/search",
        query={"q": "q3 report"},
    ),
    # buckets
    Case("buckets.get", lambda c: c.buckets.get(), "GET", P),
    Case("buckets.stats", lambda c: c.buckets.stats(B), "GET", f"{P}/{EB}/stats"),
    # folders
    Case("folders.list", lambda c: c.folders.list(B), "GET", f"{P}/{EB}/objects"),
    Case(
        "folders.list[query]",
        lambda c: c.folders.list(B, prefix="projects/2026", sizes=False),
        "GET",
        f"{P}/{EB}/objects",
        query={"prefix": "projects/2026", "sizes": "false"},
    ),
    Case(
        "folders.list_at",
        lambda c: c.folders.list_at(B, PATH, sizes=True),
        "GET",
        f"{P}/{EB}/objects/{EP}",
        query={"sizes": "true"},
    ),
    Case(
        "folders.list_public",
        lambda c: c.folders.list_public(B, prefix="shared"),
        "GET",
        f"{P}/{EB}/public/objects",
        query={"prefix": "shared"},
    ),
    Case(
        "folders.list_user",
        lambda c: c.folders.list_user(B, ID, prefix="notes", sizes=False),
        "GET",
        f"{P}/{EB}/users/{E}/objects",
        query={"prefix": "notes", "sizes": "false"},
    ),
    Case(
        "folders.list_app",
        lambda c: c.folders.list_app(B, ID),
        "GET",
        f"{P}/{EB}/apps/{E}/objects",
    ),
    Case("folders.get", lambda c: c.folders.get(B, ID), "GET", f"{P}/{EB}/folder/{E}"),
    Case(
        "folders.create", lambda c: c.folders.create(B, FOLDER), "POST", f"{P}/{EB}/folder", FOLDER
    ),
    Case("folders.delete", lambda c: c.folders.delete(B, ID), "DELETE", f"{P}/{EB}/folder/{E}"),
    Case(
        "folders.delete_by_path",
        lambda c: c.folders.delete_by_path(B, "projects/2026/"),
        "DELETE",
        f"{P}/{EB}/folder",
        query={"path": "projects/2026/"},
    ),
    Case(
        "folders.upload",
        lambda c: c.folders.upload(
            B,
            [("a.txt", b"A"), UploadFile("b.png", b"B", "image/png")],
            relative_paths=["photos/a.txt", "photos/2026/b.png"],
            parent_id="projects",
            prefix="ignored-when-parent-set",
        ),
        "POST",
        f"{P}/{EB}/upload-folder",
        multipart=[
            ("relativePaths", None, None, b"photos/a.txt"),
            ("relativePaths", None, None, b"photos/2026/b.png"),
            ("parentID", None, None, b"projects"),
            ("prefix", None, None, b"ignored-when-parent-set"),
            ("files", "a.txt", "text/plain", b"A"),
            ("files", "b.png", "image/png", b"B"),
        ],
    ),
    Case(
        "folders.upload[minimal]",
        lambda c: c.folders.upload(B, [("x.bin", b"\x00\x01", "application/octet-stream")]),
        "POST",
        f"{P}/{EB}/upload-folder",
        multipart=[("files", "x.bin", "application/octet-stream", b"\x00\x01")],
    ),
    Case(
        "folders.download_zip",
        lambda c: c.folders.download_zip(B, PATH),
        "GET",
        f"{P}/{EB}/folder-zip/{EP}",
        kind="binary",
    ),
    Case(
        "folders.duplicate",
        lambda c: c.folders.duplicate(B, DUP),
        "POST",
        f"{P}/{EB}/duplicate",
        DUP,
    ),
    Case(
        "folders.rename",
        lambda c: c.folders.rename(B, RENAME),
        "PUT",
        f"{P}/{EB}/folder/rename",
        RENAME,
    ),
    # files
    Case("files.get", lambda c: c.files.get(B, PATH), "GET", f"{P}/{EB}/file/{EP}"),
    Case(
        "files.read",
        lambda c: c.files.read(B, ".users/u-1/notes/todo.md"),
        "GET",
        f"{P}/{EB}/file",
        query={"path": ".users/u-1/notes/todo.md"},
    ),
    Case(
        "files.read[meta]",
        lambda c: c.files.read(B, "a b.md", meta=True),
        "GET",
        f"{P}/{EB}/file",
        query={"path": "a b.md", "meta": "1"},
    ),
    Case(
        "files.read[meta=False]",
        lambda c: c.files.read(B, "a.md", meta=False),
        "GET",
        f"{P}/{EB}/file",
        query={"path": "a.md"},
    ),
    Case(
        "files.create_blank",
        lambda c: c.files.create_blank(B, BLANK),
        "POST",
        f"{P}/{EB}/file",
        BLANK,
    ),
    Case("files.update", lambda c: c.files.update(B, SAVE), "PUT", f"{P}/{EB}/file", SAVE),
    Case(
        "files.update_at",
        lambda c: c.files.update_at(B, PATH, SAVE),
        "PUT",
        f"{P}/{EB}/file/{EP}",
        SAVE,
    ),
    Case(
        "files.rename", lambda c: c.files.rename(B, RENAME), "PUT", f"{P}/{EB}/file/rename", RENAME
    ),
    Case("files.delete", lambda c: c.files.delete(B, PATH), "DELETE", f"{P}/{EB}/file/{EP}"),
    Case(
        "files.delete_by_path",
        lambda c: c.files.delete_by_path(B, "projects/plan.md"),
        "DELETE",
        f"{P}/{EB}/file",
        query={"path": "projects/plan.md"},
    ),
    Case(
        "files.upload",
        lambda c: c.files.upload(
            B, ("report.pdf", b"%PDF-1.7"), parent_id="projects/2026", on_conflict="rename"
        ),
        "POST",
        f"{P}/{EB}/upload-file",
        multipart=[
            ("ParentID", None, None, b"projects/2026"),
            ("onConflict", None, None, b"rename"),
            ("file", "report.pdf", "application/pdf", b"%PDF-1.7"),
        ],
    ),
    Case(
        "files.upload[minimal]",
        lambda c: c.files.upload(B, UploadFile("notes", b"n")),
        "POST",
        f"{P}/{EB}/upload-file",
        multipart=[("file", "notes", "application/octet-stream", b"n")],
    ),
    Case(
        "files.download_url",
        lambda c: c.files.download_url(B, PATH),
        "GET",
        f"{P}/{EB}/download/{EP}",
        kind="redirect",
    ),
    Case(
        "files.preview_url",
        lambda c: c.files.preview_url(B, PATH),
        "GET",
        f"{P}/{EB}/preview/{EP}",
        kind="redirect",
    ),
    Case(
        "files.list_archive",
        lambda c: c.files.list_archive(B, "exports/report.zip"),
        "GET",
        f"{P}/{EB}/archive/exports/report.zip",
    ),
    # nodes
    Case("nodes.get", lambda c: c.nodes.get(ID), "GET", f"{P}/nodes/{E}"),
    Case("nodes.resolve", lambda c: c.nodes.resolve(ID), "GET", f"{P}/d/{E}", kind="node"),
    Case(
        "nodes.resolve[download]",
        lambda c: c.nodes.resolve(ID, download=True),
        "GET",
        f"{P}/d/{E}",
        query={"download": "1"},
        kind="node",
    ),
    Case(
        "nodes.resolve[download=False]",
        lambda c: c.nodes.resolve(ID, download=False),
        "GET",
        f"{P}/d/{E}",
        kind="node",
    ),
    Case("nodes.content", lambda c: c.nodes.content(ID), "GET", f"{P}/d/{E}/content", kind="node"),
    # library
    Case("library.star", lambda c: c.library.star(B, ID), "POST", f"{P}/{EB}/nodes/{E}/star"),
    Case("library.unstar", lambda c: c.library.unstar(B, ID), "DELETE", f"{P}/{EB}/nodes/{E}/star"),
    Case(
        "library.star_path",
        lambda c: c.library.star_path(B, "projects/plan.md"),
        "POST",
        f"{P}/{EB}/star",
        {"path": "projects/plan.md"},
    ),
    Case(
        "library.star_path[type]",
        lambda c: c.library.star_path(B, "projects", type="folder"),
        "POST",
        f"{P}/{EB}/star",
        {"path": "projects", "type": "folder"},
    ),
    Case(
        "library.unstar_path",
        lambda c: c.library.unstar_path(B, "projects/plan.md"),
        "DELETE",
        f"{P}/{EB}/star",
        query={"path": "projects/plan.md"},
    ),
    Case("library.starred", lambda c: c.library.starred(B), "GET", f"{P}/{EB}/starred"),
    Case("library.recent", lambda c: c.library.recent(B), "GET", f"{P}/{EB}/recent"),
    Case(
        "library.recent[limit]",
        lambda c: c.library.recent(B, limit=10),
        "GET",
        f"{P}/{EB}/recent",
        query={"limit": "10"},
    ),
    Case("library.trash", lambda c: c.library.trash(B), "GET", f"{P}/{EB}/trash"),
    Case(
        "library.restore",
        lambda c: c.library.restore(B, ID),
        "POST",
        f"{P}/{EB}/trash/{E}/restore",
    ),
    Case("library.purge", lambda c: c.library.purge(B, ID), "DELETE", f"{P}/{EB}/trash/{E}"),
    # sharing
    Case("sharing.create", lambda c: c.sharing.create(B, SHARE), "POST", f"{P}/{EB}/shares", SHARE),
    Case(
        "sharing.list",
        lambda c: c.sharing.list(B, ".users/u1/q3.pdf"),
        "GET",
        f"{P}/{EB}/shares",
        query={"path": ".users/u1/q3.pdf"},
    ),
    Case(
        "sharing.list[type]",
        lambda c: c.sharing.list(B, path=".users/u1/reports", type="folder"),
        "GET",
        f"{P}/{EB}/shares",
        query={"path": ".users/u1/reports", "type": "folder"},
    ),
    Case("sharing.delete", lambda c: c.sharing.delete(B, ID), "DELETE", f"{P}/{EB}/shares/{E}"),
    Case(
        "sharing.shared_with_me",
        lambda c: c.sharing.shared_with_me(B),
        "GET",
        f"{P}/{EB}/shared-with-me",
    ),
    Case(
        "sharing.shared_with_me[app_key]",
        lambda c: c.sharing.shared_with_me(B, app_key="notes"),
        "GET",
        f"{P}/{EB}/shared-with-me",
        query={"appKey": "notes"},
    ),
    Case(
        "sharing.create_link",
        lambda c: c.sharing.create_link(B, LINK),
        "POST",
        f"{P}/{EB}/share-links",
        LINK,
    ),
    Case(
        "sharing.list_links",
        lambda c: c.sharing.list_links(B, ".users/u1/q3.pdf", type="file"),
        "GET",
        f"{P}/{EB}/share-links",
        query={"path": ".users/u1/q3.pdf", "type": "file"},
    ),
    Case(
        "sharing.delete_link",
        lambda c: c.sharing.delete_link(B, ID),
        "DELETE",
        f"{P}/{EB}/share-links/{E}",
    ),
    Case(
        "sharing.resolve_link",
        lambda c: c.sharing.resolve_link("tok/en 1"),
        "GET",
        f"{P}/link/tok%2Fen%201",
        kind="redirect",
    ),
    # automation
    Case("automation.list", lambda c: c.automation.list(B), "GET", f"{P}/{EB}/folder-configs"),
    Case(
        "automation.list[prefix]",
        lambda c: c.automation.list(B, prefix="invoices/"),
        "GET",
        f"{P}/{EB}/folder-configs",
        query={"prefix": "invoices/"},
    ),
    Case(
        "automation.create",
        lambda c: c.automation.create(B, RULE),
        "POST",
        f"{P}/{EB}/folder-configs",
        RULE,
    ),
    Case(
        "automation.get", lambda c: c.automation.get(B, ID), "GET", f"{P}/{EB}/folder-configs/{E}"
    ),
    Case(
        "automation.update",
        lambda c: c.automation.update(B, ID, {**RULE, "active": False}),
        "PUT",
        f"{P}/{EB}/folder-configs/{E}",
        {**RULE, "active": False},
    ),
    Case(
        "automation.delete",
        lambda c: c.automation.delete(B, ID),
        "DELETE",
        f"{P}/{EB}/folder-configs/{E}",
    ),
    Case("automation.jobs", lambda c: c.automation.jobs(B), "GET", f"{P}/{EB}/processing-jobs"),
    Case(
        "automation.jobs[query]",
        lambda c: c.automation.jobs(B, config_id="cfg_1", limit=20),
        "GET",
        f"{P}/{EB}/processing-jobs",
        query={"configId": "cfg_1", "limit": "20"},
    ),
    # app files
    Case(
        "app_files.upload",
        lambda c: c.app_files.upload(
            ID,
            ("INV-1.pdf", b"%PDF", "application/pdf"),
            path="2026/invoices",
            on_conflict="replace",
        ),
        "POST",
        f"{P}/app-files/{E}",
        multipart=[
            ("path", None, None, b"2026/invoices"),
            ("onConflict", None, None, b"replace"),
            ("file", "INV-1.pdf", "application/pdf", b"%PDF"),
        ],
    ),
    Case(
        "app_files.list",
        lambda c: c.app_files.list("invoicing", prefix="2026"),
        "GET",
        f"{P}/app-files/invoicing/objects",
        query={"prefix": "2026"},
    ),
    Case(
        "app_files.delete",
        lambda c: c.app_files.delete("invoicing", PATH),
        "DELETE",
        f"{P}/app-files/invoicing/{EP}",
    ),
    Case(
        "app_files.sweep",
        lambda c: c.app_files.sweep("invoicing", SWEEP),
        "POST",
        f"{P}/app-files/invoicing/sweep",
        SWEEP,
    ),
    # triggers
    Case("triggers.list", lambda c: c.triggers.list(), "GET", f"{P}/triggers"),
    Case("triggers.create", lambda c: c.triggers.create(TRIGGER), "POST", f"{P}/triggers", TRIGGER),
    Case("triggers.get", lambda c: c.triggers.get(ID), "GET", f"{P}/triggers/{E}"),
    Case(
        "triggers.update",
        lambda c: c.triggers.update(ID, TRIGGER),
        "PUT",
        f"{P}/triggers/{E}",
        TRIGGER,
    ),
    Case(
        "triggers.delete",
        lambda c: c.triggers.delete(ID),
        "DELETE",
        f"{P}/triggers/{E}",
        kind="void",
    ),
    # webhooks
    Case("webhooks.list", lambda c: c.webhooks.list(), "GET", f"{P}/webhooks"),
    Case(
        "webhooks.list[page]",
        lambda c: c.webhooks.list(page=2, limit=25),
        "GET",
        f"{P}/webhooks",
        query={"page": "2", "limit": "25"},
    ),
    Case("webhooks.create", lambda c: c.webhooks.create(HOOK), "POST", f"{P}/webhooks", HOOK),
    Case("webhooks.get", lambda c: c.webhooks.get(ID), "GET", f"{P}/webhooks/{E}"),
    Case(
        "webhooks.update", lambda c: c.webhooks.update(ID, HOOK), "PUT", f"{P}/webhooks/{E}", HOOK
    ),
    Case(
        "webhooks.delete",
        lambda c: c.webhooks.delete(ID),
        "DELETE",
        f"{P}/webhooks/{E}",
        kind="void",
    ),
]


def _respond(kind: str) -> httpx.Response:
    if kind == "text":
        return httpx.Response(200, text="Working!", headers={"Content-Type": "text/plain"})
    if kind in ("redirect", "node"):
        return httpx.Response(307, headers={"Location": LOCATION})
    if kind == "binary":
        return httpx.Response(
            200,
            content=ZIP,
            headers={
                "Content-Type": "application/zip",
                "Content-Disposition": 'attachment; filename="dir one.zip"',
            },
        )
    if kind == "void":
        return httpx.Response(204)
    return httpx.Response(200, json={"status": 1, "data": DATA})


EXPECTED: dict[str, Any] = {
    "json": DATA,
    "void": None,
    "text": "Working!",
    "redirect": LOCATION,
    "binary": Binary(ZIP, "application/zip", "dir one.zip"),
    "node": NodeFileResult(url=LOCATION),
}


def _handler(case: Case, seen: list[httpx.Request]) -> Callable[[httpx.Request], httpx.Response]:
    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return _respond(case.kind)

    return handle


def parse_multipart(request: httpx.Request) -> list[Part]:
    """Splits a multipart/form-data body into (name, filename, content type, bytes)."""
    head = b"Content-Type: " + request.headers["Content-Type"].encode() + b"\r\n\r\n"
    message = BytesParser(policy=email_policy).parsebytes(head + request.content)
    assert message.is_multipart()
    parts: list[Part] = []
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        filename = part.get_filename()
        content_type = part.get_content_type() if filename is not None else None
        payload = part.get_payload(decode=True)
        assert isinstance(name, str) and isinstance(payload, bytes)
        parts.append((name, filename, content_type, payload))
    return parts


def _check(case: Case, seen: list[httpx.Request], result: Any) -> None:
    assert len(seen) == 1
    req = seen[0]
    assert req.method == case.method
    assert req.url.scheme == "https"
    assert req.url.host == "api.lowco.ai"
    assert req.url.raw_path.decode().split("?")[0] == case.path
    assert dict(req.url.params) == case.query
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    expected_accept = "application/json" if case.kind in ("json", "void") else "*/*"
    assert req.headers["Accept"] == expected_accept
    if case.multipart is not None:
        assert req.headers["Content-Type"].startswith("multipart/form-data; boundary=")
        assert parse_multipart(req) == case.multipart
    elif case.body is NO_BODY:
        assert req.content == b""
        assert "Content-Type" not in req.headers
    else:
        assert req.headers["Content-Type"] == "application/json"
        assert json.loads(req.content) == case.body
    assert result == EXPECTED[case.kind]


@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
def test_sync_call(case: Case) -> None:
    seen: list[httpx.Request] = []
    http = httpx.Client(transport=httpx.MockTransport(_handler(case, seen)))
    with DocsClient("tok_123", org_id="org_1", http_client=http) as client:
        result = case.call(client)
    _check(case, seen, result)


@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
async def test_async_call(case: Case) -> None:
    seen: list[httpx.Request] = []
    http = httpx.AsyncClient(transport=httpx.MockTransport(_handler(case, seen)))
    async with AsyncDocsClient("tok_123", org_id="org_1", http_client=http) as client:
        pending = case.call(client)
        assert inspect.iscoroutine(pending)
        result = await pending
    _check(case, seen, result)


def test_table_covers_every_method() -> None:
    client = DocsClient("tok", org_id="org")
    expected = {
        f"{attr}.{name}"
        for attr, resource in vars(client).items()
        if not attr.startswith("_")
        for name, _ in inspect.getmembers(resource, inspect.ismethod)
        if not name.startswith("_")
    }
    expected |= {"health", "search"}
    covered = {case.name.split("[")[0] for case in CASES}
    assert covered == expected
    # The cross-language contract's surface: 69 operations.
    assert len(expected) == 69
