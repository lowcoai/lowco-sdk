# @lowcoai/docs

Official Node/TypeScript client for the lowco **document** service: files, folders, sharing,
triggers and webhooks (routes under `/v1/documents/*`).

```bash
npm install @lowcoai/docs
```

Requires Node.js 18+ (it uses the global `fetch`, `FormData` and `Blob`). No runtime dependencies.

## Quick start

```ts
import { DocsClient } from "@lowcoai/docs";

const client = new DocsClient({
  token: process.env.LOWCO_TOKEN!, // required: user token or API key
  orgId: "org-1",                  // required: sent as X-Org-Id
});

// The org's bucket (created on first use). Its name is the `bucketName` the other calls take.
const bucket = await client.buckets.get();
const b = bucket.name!;

const items = await client.folders.list(b, { prefix: "projects" });
console.log(items.map((d) => `${d.type} ${d.path}`));
```

## Configuration

| Option      | Type                      | Default        | Notes                                                       |
| ----------- | ------------------------- | -------------- | ----------------------------------------------------------- |
| `token`     | `string`                  | (required)     | Sent as `Authorization: Bearer <token>`.                    |
| `orgId`     | `string`                  | (required)     | Sent as `X-Org-Id`; the service rejects requests without it. |
| `timeoutMs` | `number`                  | `30000`        | Per-request timeout.                                        |
| `headers`   | `Record<string, string>`  | `{}`           | Extra headers on every request.                             |
| `fetch`     | `typeof fetch`            | global `fetch` | Custom fetch (proxies, tests).                              |

The constructor throws when `token` or `orgId` is missing or blank. The host is always
`https://api.lowco.ai`.

## Folders

```ts
import { readFile, writeFile } from "node:fs/promises";

await client.folders.create(b, { parentName: "projects", folderName: "2026/q4" });
const q4 = await client.folders.listAt(b, "projects/2026/q4", { sizes: false });

// Upload a local folder: one entry per file, relative paths in the same order.
await client.folders.upload(
  b,
  [
    { data: await readFile("photos/a.jpg"), fileName: "a.jpg", contentType: "image/jpeg" },
    { data: await readFile("photos/2026/b.png"), fileName: "b.png" },
  ],
  { relativePaths: ["photos/a.jpg", "photos/2026/b.png"], parentId: "uploads" },
);

const zip = await client.folders.downloadZip(b, "projects/2026");
await writeFile(zip.fileName ?? "folder.zip", zip.data);

await client.folders.deleteByPath(b, "projects/2026/q4/");
```

Also: `listPublic`, `listUser`, `listApp`, `get`, `delete`, `duplicate`, `rename`.

## Files

```ts
// Upload (multipart). Accepts { data, fileName, contentType? }, a File or a Blob.
const doc = await client.files.upload(
  b,
  { data: await readFile("q3.pdf"), fileName: "q3.pdf", contentType: "application/pdf" },
  { parentId: "reports", onConflict: "rename" },
);

// Read a text file with its etag, then save it conditionally.
const note = await client.files.read(b, ".users/u-123/notes/todo.md");
await client.files.update(b, {
  parentName: ".users/u-123/notes",
  fileName: "todo.md",
  content: `${note.content}\n- ship it`,
  ifMatch: note.etag,
});

// Short-lived URLs (the SDK returns the redirect target instead of following it).
const downloadUrl = await client.files.downloadUrl(b, "reports/q3.pdf");
const pdfPreviewUrl = await client.files.previewUrl(b, "reports/q3.docx");
```

Also: `get`, `createBlank`, `updateAt`, `rename`, `delete`, `deleteByPath`, `listArchive`.

## Nodes (permalinks)

Node ids survive renames; store `/v1/documents/d/{nodeId}` instead of storage URLs.

```ts
const meta = await client.nodes.get(doc.id!);

const result = await client.nodes.resolve(doc.id!, { download: true });
if (result.url) {
  console.log("signed URL", result.url);
} else if (result.content) {
  console.log("bytes", result.content.data.byteLength); // restored from cold storage
} else if (result.restoring) {
  console.log(`restoring, retry in ${result.retryAfter}s`);
}

// Bytes directly, for callers that cannot follow a redirect.
const file = await client.nodes.content(doc.id!);
```

## Library (starred, recent, trash)

```ts
await client.library.starPath(b, "projects/plan.md");
const starred = await client.library.starred(b);
const recent = await client.library.recent(b, { limit: 20 });

const trash = await client.library.trash(b);
if (trash[0]?.id) await client.library.restore(b, trash[0].id);
```

Also: `star`, `unstar`, `unstarPath`, `purge`.

## Search

```ts
const hits = await client.search(b, "quarterly revenue");
const contentHits = hits.filter((d) => d.metadata?.matchedBy === "content");
```

## Sharing

```ts
await client.sharing.create(b, {
  path: ".users/u-123/reports/q3.pdf",
  type: "file",
  subjectType: "user",
  subjectId: "u-456",
  role: "viewer",
});
const grants = await client.sharing.list(b, { path: ".users/u-123/reports/q3.pdf" });

const link = await client.sharing.createLink(b, { path: ".users/u-123/reports/q3.pdf" });
const fileUrl = await client.sharing.resolveLink(link.token!);

const sharedWithMe = await client.sharing.sharedWithMe(b, { appKey: "notes" });
```

Also: `delete`, `listLinks`, `deleteLink`.

## Folder automation

```ts
const rule = await client.automation.create(b, {
  prefix: "invoices/",
  pipelineType: "custom_workflow",
  workflowId: "7489521000000000001",
  fileSuffixes: [".pdf"],
});
const runs = await client.automation.jobs(b, { configId: rule.id, limit: 10 });
```

Also: `list`, `get`, `update`, `delete`.

## App files

App data lives under `.apps/{appKey}/` in the org's bucket (derived from `X-Org-Id`).

```ts
const uploaded = await client.appFiles.upload(
  "invoicing",
  { data: pdfBytes, fileName: "INV-0042.pdf", contentType: "application/pdf" },
  { path: "2026/invoices" },
);
console.log(uploaded.permalink); // store this, not a storage URL

const files = await client.appFiles.list("invoicing", { prefix: "2026" });
await client.appFiles.delete("invoicing", "2026/invoices/INV-0042.pdf");
await client.appFiles.sweep("invoicing", { prefix: "2026", olderThanDays: 365 });
```

## Triggers and webhooks

```ts
await client.triggers.create({
  eventType: "create",
  prefix: "invoices/",
  suffix: ".pdf",
  workflowId: "7489521000000000001",
  active: true, // omitted means false
});

await client.webhooks.create({
  url: "https://hooks.example.com/documents",
  method: "POST",
  prefix: "uploads/images/",
  eventTypes: ["create", "update"],
  active: true,
});
const hooks = await client.webhooks.list({ page: 1, limit: 20 });
```

Both resources also have `get`, `update` (replaces every field) and `delete`.

## Error handling

Every failure throws `DocsError`: non-2xx responses, network errors and timeouts (`status` `0`).

```ts
import { DocsError } from "@lowcoai/docs";

try {
  await client.files.update(b, { fileName: "todo.md", content: "...", ifMatch: staleEtag });
} catch (err) {
  if (err instanceof DocsError) {
    console.error(err.status, err.message, err.code, err.payload);
    if (err.status === 412) {
      // Conditional save lost the race: payload.data holds the current state.
      const current = (err.payload as { data?: { currentEtag?: string } }).data;
    }
  }
}
```

The service answers errors as `{ "status": 0, "error": { message, code, details } }` or
`{ "message": "..." }`. `err.message` is the most readable text of either shape (the
`details` text when `error.message` is a platform code such as `AAS-00106`, which is then
in `err.code`); `err.payload` is the parsed body.

## Redirects, binaries and cold storage

- **URL methods** (`files.downloadUrl`, `files.previewUrl`, `sharing.resolveLink`, and
  `nodes.resolve` when it redirects) send the request with `redirect: "manual"` and return
  the `Location` URL instead of following the 307. In browsers, `fetch` hides the
  `Location` of a redirect (an "opaque redirect"), so these methods throw a `DocsError`
  there; call them from a server runtime.
- **Binary methods** (`folders.downloadZip`, `nodes.content`, `nodes.resolve` on 200)
  return `{ data: Uint8Array, contentType, fileName? }`. `fileName` comes from
  `X-File-Name`, else from `Content-Disposition`.
- **Cold storage**: `nodes.resolve` and `nodes.content` answer 202 while an archived file
  is restored. That is returned as `{ restoring, retryAfter }` (seconds), not thrown.

## Conventions

- Host: all requests go to `https://api.lowco.ai`; routes live under `/v1/documents`
  (`health()` calls `/health`).
- Tenancy: `X-Org-Id` header (set via `orgId`, required).
- Auth: `Authorization: Bearer <token>`; `token` (user token or API key) is required.
- Response envelope: `{ "status": 1, "data": ... }`; the SDK unwraps `data` for you.
- Paths: single-segment parameters (bucket name, ids, keys, tokens, app keys) are fully
  percent-encoded; object paths keep their `/` separators and encode each segment
  (`"a b/c.txt"` is sent as `a%20b/c.txt`). `.` and `..` segments are rejected.
- Query parameters left `undefined` are not sent.

See [`../../docs/docs.md`](../../docs/docs.md) for the full endpoint map.
