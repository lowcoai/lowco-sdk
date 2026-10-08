# docs — REST surface reference

Service: **document** manager. All routes are mounted under `/v1/documents/*`; the paths below are relative to that prefix.

## Conventions

- **Host**: always `https://api.lowco.ai`.
- **Auth**: `Authorization: Bearer <user-token-or-api-key>`. Required; it identifies the acting user.
- **Tenancy**: `X-Org-Id` is **required on every request**. Requests without it are rejected with `401`. On routes that take `:bucketName`, the bucket must belong to that org, or the request fails with `403`.
- **Response envelope**: success is `{ "status": 1, "data": … }`. Failures are either `{ "status": 0, "error": { message, code, details } }` or `{ "message": "…" }`. Every SDK (`@lowcoai/docs`, `github.com/lowcoai/lowco-sdk/go/docs`, `lowcoai-docs` on PyPI, `lowcoai_docs` on pub.dev) unwraps `data` and raises a typed error for both failure shapes.
- **Paths**: `*path` segments are object keys that may contain `/` (for example `.users/u-123/notes/todo.md`). Percent-encode each segment but keep the `/` separators. All other `:params` are single segments.
- **Redirects**: `download`, `preview`, `/d/:nodeId` and `/link/:token` answer `307` with a short-lived signed URL in `Location`. The SDKs do not follow the redirect; they return the URL. In browsers, `fetch` cannot read the `Location` of a redirect, so use these methods from a server runtime.
- **Cold storage**: `/d/:nodeId` and `/d/:nodeId/content` answer `202` with a restore status (and `Retry-After`) while an archived file is being restored. The SDKs return this as a "restoring" result, not an error.
- **Uploads** are `multipart/form-data`. Field names are case-sensitive: `upload-file` takes `file`, `ParentID`, `onConflict`; `upload-folder` takes repeated `files` parts with matching repeated `relativePaths`, plus `parentID` and `prefix`; app-file uploads take `file`, `path`, `onConflict`.

## Endpoints

### System

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/health` (no prefix) | Liveness probe; returns `Working!` as text |

### Buckets

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/v1/documents` (no trailing slash) | Get the org's bucket |
| `GET` | `/:bucketName/stats` | Get bucket storage usage |

### Folders

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/:bucketName/apps/:appId/objects` | List an app's data folder (query: `prefix`, `sizes`) |
| `POST` | `/:bucketName/duplicate` | Duplicate a file or folder |
| `POST` | `/:bucketName/folder` | Create a folder |
| `DELETE` | `/:bucketName/folder` | Delete a folder (any depth) (query: `path`) |
| `GET` | `/:bucketName/folder-zip/*path` | Download a folder as zip |
| `GET` | `/:bucketName/folder/:key` | Get a folder's raw listing |
| `DELETE` | `/:bucketName/folder/:key` | Delete a folder |
| `PUT` | `/:bucketName/folder/rename` | Rename or move a folder |
| `GET` | `/:bucketName/objects` | List a folder (query: `prefix`, `sizes`) |
| `GET` | `/:bucketName/objects/*path` | List a folder (path form) (query: `sizes`) |
| `GET` | `/:bucketName/public/objects` | List an org-library folder (query: `prefix`, `sizes`) |
| `POST` | `/:bucketName/upload-folder` | Upload a folder |
| `GET` | `/:bucketName/users/:userId/objects` | List a personal drive (query: `prefix`, `sizes`) |

### Files

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/:bucketName/archive/*path` | List a zip archive |
| `GET` | `/:bucketName/download/*path` | Download a file |
| `GET` | `/:bucketName/file` | Read a file by path (query: `path`, `meta`) |
| `POST` | `/:bucketName/file` | Create an empty file |
| `PUT` | `/:bucketName/file` | Save a text file |
| `DELETE` | `/:bucketName/file` | Delete a file (query form) (query: `path`) |
| `GET` | `/:bucketName/file/*path` | Get a file with its content |
| `PUT` | `/:bucketName/file/*path` | Save a text file (path form) |
| `DELETE` | `/:bucketName/file/*path` | Delete a file |
| `PUT` | `/:bucketName/file/rename` | Rename or move a file |
| `GET` | `/:bucketName/preview/*path` | Preview a file as PDF |
| `POST` | `/:bucketName/upload-file` | Upload a file |

### Nodes (permalinks)

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/d/:nodeId` | Resolve a permalink (query: `download`) |
| `GET` | `/d/:nodeId/content` | Stream a file by node id |
| `GET` | `/nodes/:nodeId` | Get node metadata |

### Library (starred, recent, trash)

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST` | `/:bucketName/nodes/:nodeId/star` | Star a node |
| `DELETE` | `/:bucketName/nodes/:nodeId/star` | Unstar a node |
| `GET` | `/:bucketName/recent` | List recent items (query: `limit`) |
| `POST` | `/:bucketName/star` | Star an item by path |
| `DELETE` | `/:bucketName/star` | Unstar an item by path (query: `path`) |
| `GET` | `/:bucketName/starred` | List starred items |
| `GET` | `/:bucketName/trash` | List trash |
| `DELETE` | `/:bucketName/trash/:nodeId` | Permanently delete a trashed item |
| `POST` | `/:bucketName/trash/:nodeId/restore` | Restore a trashed item |

### Search

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/:bucketName/search` | Search a bucket (query: `q`) |

### Sharing

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/:bucketName/share-links` | List a file's share links (query: `path`, `type`) |
| `POST` | `/:bucketName/share-links` | Create a share link |
| `DELETE` | `/:bucketName/share-links/:id` | Revoke a share link |
| `GET` | `/:bucketName/shared-with-me` | List items shared with me (query: `appKey`) |
| `GET` | `/:bucketName/shares` | List an item's grants (query: `path`, `type`) |
| `POST` | `/:bucketName/shares` | Share an item |
| `DELETE` | `/:bucketName/shares/:id` | Revoke a grant |
| `GET` | `/link/:token` | Follow a share link |

### Folder automation

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/:bucketName/folder-configs` | List folder automations (query: `prefix`) |
| `POST` | `/:bucketName/folder-configs` | Create a folder automation |
| `GET` | `/:bucketName/folder-configs/:id` | Get a folder automation |
| `PUT` | `/:bucketName/folder-configs/:id` | Replace a folder automation |
| `DELETE` | `/:bucketName/folder-configs/:id` | Delete a folder automation |
| `GET` | `/:bucketName/processing-jobs` | List pipeline runs (query: `configId`, `limit`) |

### App files

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST` | `/app-files/:appKey` | Upload an app file |
| `DELETE` | `/app-files/:appKey/*path` | Delete an app file |
| `GET` | `/app-files/:appKey/objects` | List app files (query: `prefix`) |
| `POST` | `/app-files/:appKey/sweep` | Archive an app's old files |

### Triggers

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/triggers` | List triggers |
| `POST` | `/triggers` | Create a trigger |
| `GET` | `/triggers/:id` | Get a trigger |
| `PUT` | `/triggers/:id` | Replace a trigger |
| `DELETE` | `/triggers/:id` | Delete a trigger |

### Webhooks

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/webhooks` | List webhooks |
| `POST` | `/webhooks` | Create a webhook |
| `GET` | `/webhooks/:id` | Get a webhook |
| `PUT` | `/webhooks/:id` | Replace a webhook |
| `DELETE` | `/webhooks/:id` | Delete a webhook |

## Not part of the public API

`POST /:bucketName/reindex`, `POST /:bucketName/move-prefix`, `POST /:bucketName/trash/purge` and `GET /internal/cdn-authz` are served only on the service's in-cluster listener, behind an internal token. They are not reachable through `api.lowco.ai`, and the SDKs do not expose them.

## See also

- OpenAPI spec: served by the service at `/swagger/doc.json` (UI at `/swagger/index.html`)
- Go client: [`../go/docs/README.md`](../go/docs/README.md)
- npm client: [`../npm/docs/README.md`](../npm/docs/README.md)
- Python client: [`../python/docs/README.md`](../python/docs/README.md)
- Dart client: [`../flutter/docs/README.md`](../flutter/docs/README.md)
