# lowcoai-docs

Python client for the lowco **document service**: files, folders, sharing, triggers and webhooks (routes under `/v1/documents/*`). Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-docs
```

## Quick start

```python
from lowcoai.docs import DocsClient

with DocsClient("<token-or-api-key>", org_id="org_123") as client:
    bucket = client.buckets.get()["name"]  # the org's bucket, created on first use

    client.folders.create(bucket, {"parentName": "", "folderName": "projects/2026"})
    doc = client.files.upload(bucket, ("plan.md", b"# Plan"), parent_id="projects/2026")

    for item in client.folders.list(bucket, prefix="projects/2026"):
        print(item["type"], item["path"], item.get("size"))
```

### asyncio

```python
from lowcoai.docs import AsyncDocsClient

async with AsyncDocsClient("<token-or-api-key>", org_id="org_123") as client:
    bucket = (await client.buckets.get())["name"]
    hits = await client.search(bucket, "quarterly report")
```

`AsyncDocsClient` has the same resources and methods as `DocsClient`; each endpoint method is a coroutine. Close it with `await client.aclose()` if you don't use `async with`.

## Options

| Argument      | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `token`       | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `org_id`      | Organization id, sent as the `X-Org-Id` header. Required — the service rejects every request without it. |
| `timeout`     | Per-request timeout in seconds (default `30`). `None` disables it.                   |
| `headers`     | Extra headers added to every request. An `Authorization` or `X-Org-Id` entry here wins over `token` / `org_id`. |
| `http_client` | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

All requests go to `https://api.lowco.ai`. An empty `token` or `org_id` raises `ValueError`. The caller's identity comes from the token; the SDK sends no `X-User-Id` (add one through `headers` if your setup needs it).

## Data shapes

Request and response bodies are plain dicts typed as `TypedDict`s generated from the service's OpenAPI spec (`Document`, `FileContent`, `NodeView`, `Share`, `ShareLink`, `FolderConfig`, `Trigger`, `Webhook`, …), with keys exactly as on the wire (camelCase). A value returned by one call can be sent back as the body of another. The service's `{"status": 1, "data": ...}` envelope is unwrapped for you; calls whose payload is a confirmation message (most deletes, `star`, `unstar`, …) return that string.

`bucket` is the bucket name (`client.buckets.get()["name"]`). Paths are bucket keys such as `projects/plan.md` or `.users/u-123/notes/todo.md`. In URLs, single-segment parameters (bucket, ids, keys, tokens, app keys) are fully percent-encoded, while file and folder paths keep their `/` and have each segment encoded (a leading `/` is dropped). Segments that are exactly `.` or `..` are rejected with `DocsError` before anything is sent. Optional query arguments left as `None` are omitted.

## Surface

| Resource            | Methods |
| ------------------- | ------- |
| `client`            | `health()` (plain text), `search(bucket, q)` |
| `client.buckets`    | `get()`, `stats(bucket)` |
| `client.folders`    | `list(bucket, prefix=, sizes=)`, `list_at(bucket, path, sizes=)`, `list_public(bucket, prefix=, sizes=)`, `list_user(bucket, user_id, prefix=, sizes=)`, `list_app(bucket, app_id, prefix=, sizes=)`, `get(bucket, key)`, `create(bucket, body)`, `delete(bucket, key)`, `delete_by_path(bucket, path)`, `upload(bucket, files, relative_paths=, parent_id=, prefix=)`, `download_zip(bucket, path)`, `duplicate(bucket, body)`, `rename(bucket, body)` |
| `client.files`      | `get(bucket, path)`, `read(bucket, path, meta=)`, `create_blank(bucket, body)`, `update(bucket, body)`, `update_at(bucket, path, body)`, `rename(bucket, body)`, `delete(bucket, path)`, `delete_by_path(bucket, path)`, `upload(bucket, file, parent_id=, on_conflict=)`, `download_url(bucket, path)`, `preview_url(bucket, path)`, `list_archive(bucket, path)` |
| `client.nodes`      | `get(node_id)`, `resolve(node_id, download=False)`, `content(node_id)` |
| `client.library`    | `star(bucket, node_id)`, `unstar(bucket, node_id)`, `star_path(bucket, path, type=)`, `unstar_path(bucket, path)`, `starred(bucket)`, `recent(bucket, limit=)`, `trash(bucket)`, `restore(bucket, node_id)`, `purge(bucket, node_id)` |
| `client.sharing`    | `create(bucket, body)`, `list(bucket, path, type=)`, `delete(bucket, id)`, `shared_with_me(bucket, app_key=)`, `create_link(bucket, body)`, `list_links(bucket, path, type=)`, `delete_link(bucket, id)`, `resolve_link(token)` |
| `client.automation` | `list(bucket, prefix=)`, `create(bucket, body)`, `get(bucket, id)`, `update(bucket, id, body)`, `delete(bucket, id)`, `jobs(bucket, config_id=, limit=)` |
| `client.app_files`  | `upload(app_key, file, path=, on_conflict=)`, `list(app_key, prefix=)`, `delete(app_key, path)`, `sweep(app_key, body)` |
| `client.triggers`   | `list()`, `create(body)`, `get(id)`, `update(id, body)`, `delete(id)` |
| `client.webhooks`   | `list(page=, limit=)`, `create(body)`, `get(id)`, `update(id, body)`, `delete(id)` |

`triggers.delete` and `webhooks.delete` return `None`.

## Examples

### Folders

```python
# sizes=False skips recursive folder sizes (folders then report size 0)
client.folders.list(bucket, prefix="projects", sizes=False)
client.folders.list_user(bucket, "u-123", prefix="notes")  # a personal drive
client.folders.rename(
    bucket, {"parentName": "projects", "oldName": "2025", "newName": "archive/2025"}
)
client.folders.delete_by_path(bucket, "projects/old/")  # any depth; goes to the trash
```

### Files

```python
current = client.files.read(bucket, "notes/todo.md")  # content + etag + role
client.files.update(
    bucket,
    {
        "parentName": "notes",
        "fileName": "todo.md",
        "content": "# Todo\n- ship",
        "ifMatch": current["etag"],
    },
)  # DocsError(status=412) when someone saved in between
client.files.create_blank(bucket, {"parentName": "notes", "fileName": "ideas.md"})
url = client.files.download_url(bucket, "reports/q3.pdf")  # short-lived signed URL
```

### Nodes (permalinks)

```python
result = client.nodes.resolve("7489521000000000042", download=True)
if result.url:  # 307: a fresh short-lived URL
    print(result.url)
elif result.content:  # 200: bytes of a file just restored from cold storage
    open(result.content.file_name or "file", "wb").write(result.content.data)
elif result.restoring:  # 202: restore in progress
    print(f"retry in {result.retry_after}s:", result.restoring["message"])
```

`nodes.content(node_id)` streams the bytes instead of redirecting (`result.content`, or `result.restoring` while a restore runs).

### Library

```python
client.library.star_path(bucket, "projects/plan.md")
client.library.recent(bucket, limit=20)
trashed = client.library.trash(bucket)
client.library.restore(bucket, trashed[0]["id"])
```

### Sharing

```python
client.sharing.create(
    bucket,
    {
        "path": ".users/u-123/q3.pdf",
        "type": "file",
        "subjectType": "user",
        "subjectId": "u-456",
        "role": "viewer",
    },
)
grants = client.sharing.list(bucket, ".users/u-123/q3.pdf")
link = client.sharing.create_link(bucket, {"path": ".users/u-123/q3.pdf", "type": "file"})
file_url = client.sharing.resolve_link(link["token"])
```

### Automation

```python
rule = client.automation.create(
    bucket,
    {
        "prefix": "invoices/",
        "pipelineType": "custom_workflow",
        "workflowId": "wf_1",
        "fileSuffixes": [".pdf"],
    },
)
client.automation.jobs(bucket, config_id=rule["id"], limit=10)
```

### App files

```python
stored = client.app_files.upload("invoicing", ("INV-0042.pdf", pdf_bytes), path="2026/invoices")
stored["permalink"]  # store this (or stored["nodeId"]), not a storage URL
client.app_files.sweep("invoicing", {"prefix": "2026", "olderThanDays": 365})
```

### Triggers and webhooks

```python
client.triggers.create(
    {
        "eventType": "create",
        "prefix": "invoices/",
        "suffix": ".pdf",
        "workflowId": "wf_1",
        "active": True,
    }
)
client.webhooks.create(
    {
        "url": "https://hooks.example.com/docs",
        "method": "POST",
        "prefix": "uploads/",
        "eventTypes": ["create", "delete"],
        "active": True,
    }
)
client.webhooks.list(page=1, limit=50)
```

## Uploads

Upload methods take a file as an `UploadFile(name, data, content_type=None)` or a `(name, data)` / `(name, data, content_type)` tuple, where `data` is `bytes` or a binary file object (streamed). Without a content type, one is guessed from the name (else `application/octet-stream`). Form fields use the service's exact names:

| Method              | Parts |
| ------------------- | ----- |
| `files.upload`      | `file`, `ParentID` (from `parent_id`), `onConflict` |
| `folders.upload`    | repeated `files`, repeated `relativePaths` (same order; one per file), `parentID`, `prefix` |
| `app_files.upload`  | `file`, `path`, `onConflict` |

```python
from lowcoai.docs import UploadFile

with open("photo.jpg", "rb") as fh:
    client.folders.upload(
        bucket,
        [UploadFile("photo.jpg", fh), ("notes.txt", b"hello")],
        relative_paths=["trip/photo.jpg", "trip/notes.txt"],
        parent_id="projects",
    )
```

## Redirects and downloads

- `files.download_url`, `files.preview_url` and `sharing.resolve_link` answer with a 307 redirect. The SDK never follows it (even if your `httpx` client is configured to) and returns the `Location` URL as a string.
- `folders.download_zip` returns a `Binary(data, content_type, file_name)`; `file_name` comes from the `X-File-Name` header, else from `Content-Disposition`.
- `nodes.resolve` / `nodes.content` return a `NodeFileResult` with exactly one of `url`, `content` (`Binary`) or `restoring` (`ArchiveRestoring`) set, plus `retry_after` (seconds, from `Retry-After`) on a 202.
- `health()` returns the plain-text body (`"Working!"`); it is served at `/health`, outside `/v1/documents`.

### Endpoints the SDK does not wrap

`HttpClient` / `AsyncHttpClient` are the transports behind the resources and apply the same headers, envelope unwrapping and error mapping (`request`, `request_void`, `request_text`, `request_binary`, `request_redirect`, `request_node_file`, `request_multipart`):

```python
from lowcoai.docs import HttpClient

with HttpClient("<token>", org_id="org_123") as http:
    data = http.request("GET", "/v1/documents/my-bucket/objects", query={"prefix": "a"})
```

## Errors

Every non-2xx response raises `DocsError`:

```python
from lowcoai.docs import DocsError

try:
    client.files.read(bucket, "missing.md")
except DocsError as err:
    print(err.status, err.message, err.code, err.payload)
```

- `message` — the best message in the error body. The service sends either `{"status": 0, "error": {"message", "code", "details"}}` or `{"message": "..."}`. When `error.message` is a platform code such as `AAS-00106`, `details` is the message and the code goes to `code`; otherwise `error.message` (or `message`) is used, falling back to `"Request failed with status <n>"`.
- `status` — the HTTP status; `0` when no response arrived (connection error, timeout — the `httpx` exception is chained as `__cause__`) or a `.` / `..` path segment was refused.
- `code` — the platform error code (e.g. `AAS-00106`) when the body carries one, else `None`.
- `payload` — the parsed JSON error body (a failed conditional save puts the file's current `currentEtag` / `updatedBy` under `payload["data"]`); the raw text when the body is not JSON; `None` when empty.

A 2xx response whose body is not JSON raises `DocsError` with that 2xx `status` and the raw text as `payload` (`triggers.delete` / `webhooks.delete` ignore the body). A redirect method that gets no 3xx `Location` raises `DocsError` too.
