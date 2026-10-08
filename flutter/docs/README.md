# lowcoai_docs

Dart / Flutter client for the lowco **document service** (routes under `/v1/documents`): files, folders, sharing, folder automation, app files, triggers and webhooks. Pure Dart on top of [`package:http`](https://pub.dev/packages/http), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM. It mirrors the TypeScript SDK `@lowcoai/docs`.

```yaml
dependencies:
  lowcoai_docs: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_docs/lowcoai_docs.dart';

final client = DocsClient(token: '<token-or-api-key>', orgId: 'org_123');

// The org's bucket; its name is the bucketName every other call takes.
final bucket = (await client.buckets.get()).name!;

final rows = await client.folders.list(bucket, prefix: 'projects');
final file = await client.files.read(bucket, 'projects/plan.md');
print('${file.name}: ${file.content}');

client.close();
```

## Options

| Parameter    | Description |
| ------------ | ----------- |
| `token`      | User token or API key, sent as `Authorization: Bearer <token>`. Required (`ArgumentError` if blank). Not sent when `headers` already contain `Authorization`. |
| `orgId`      | Organization id, sent as the `X-Org-Id` header (unless `headers` already contain one). Required (`ArgumentError` if blank): the service rejects every request without it. |
| `timeout`    | Per-request timeout (default 30 s); `null` disables it. A timed-out request is aborted and throws `DocsException` with status `0`. |
| `headers`    | Extra headers added to every request. |
| `httpClient` | Your own `http.Client` (e.g. `cupertino_http` / `cronet_http` in Flutter, or `MockClient` in tests). Not closed by `close()`. |

Every request goes to `https://api.lowco.ai`. The acting user comes from the token (the gateway derives it), so the SDK sends no `X-User-Id`; add one through `headers` if you call the service some other way. JSON responses are unwrapped from the `{ status, data }` envelope.

## Data shapes

Entities and request bodies are immutable model classes named after the service's schemas (`Document`, `NodeView`, `FileContent`, `Share`, `ShareLink`, `FolderConfig`, `ProcessingJob`, `Trigger`, `Webhook`, `CreateFolderRequest`, `UpdateFileRequest`, …) with `fromJson` / `toJson`. Field names match the wire; request fields the service rejects when missing are `required`; `toJson` omits null fields. Timestamps are ISO-8601 strings, enum-like fields are strings (their allowed values are in the doc comments) and free-form JSON is `Map<String, dynamic>`.

Methods returning the service's confirmation message (`file deleted`, `link revoked`, …) return it as a `String`.

### Paths

- Single-segment parameters (`bucketName`, folder `key`, `nodeId`, `id`, `token`, `appKey`, `userId`, `appId`) are fully percent-encoded, so `a/b` becomes `a%2Fb`.
- File and folder paths in the URL (`files.get`, `files.delete`, `folders.listAt`, `folders.downloadZip`, `appFiles.delete`, …) keep their `/` separators and have each segment encoded (`a b/c.txt` → `a%20b/c.txt`); a leading `/` is dropped.
- A `.` or `..` segment throws `DocsException` (status `0`) before anything is sent: URL normalisation would otherwise send the request to a different route.
- Endpoints that take the path as `?path=` (`files.read`, `files.deleteByPath`, `folders.deleteByPath`, `library.unstarPath`, sharing lists) accept any nesting.

## Surface

| Resource            | Methods |
| ------------------- | ------- |
| `client`            | `health()`, `search(bucketName, q)` |
| `client.buckets`    | `get`, `stats` |
| `client.folders`    | `list`, `listAt`, `listPublic`, `listUser`, `listApp`, `get`, `create`, `delete`, `deleteByPath`, `upload`, `downloadZip`, `duplicate`, `rename` |
| `client.files`      | `get`, `read`, `createBlank`, `update`, `updateAt`, `rename`, `delete`, `deleteByPath`, `upload`, `downloadUrl`, `previewUrl`, `listArchive` |
| `client.nodes`      | `get`, `resolve`, `content` |
| `client.library`    | `star`, `unstar`, `starPath`, `unstarPath`, `starred`, `recent`, `trash`, `restore`, `purge` |
| `client.sharing`    | `create`, `list`, `delete`, `sharedWithMe`, `createLink`, `listLinks`, `deleteLink`, `resolveLink` |
| `client.automation` | `list`, `create`, `get`, `update`, `delete`, `jobs` |
| `client.appFiles`   | `upload`, `list`, `delete`, `sweep` |
| `client.triggers`   | `list`, `create`, `get`, `update`, `delete` |
| `client.webhooks`   | `list({page, limit})`, `create`, `get`, `update`, `delete` |

### Buckets

```dart
final bucket = await client.buckets.get(); // a folder Document
final stats = await client.buckets.stats(bucket.name!);
print('${stats.visibleFiles} files, ${stats.visibleSize} bytes');
```

### Folders

```dart
await client.folders.create(bucket, const CreateFolderRequest(folderName: 'photos/2026'));

// Upload a whole folder: one `files` part per file, `relativePaths` in the same order.
final result = await client.folders.upload(
  bucket,
  [UploadFile(bytes: jpegBytes, fileName: 'a.jpg', contentType: 'image/jpeg')],
  relativePaths: ['trip/a.jpg'],
  parentId: 'photos/2026',
);

final zip = await client.folders.downloadZip(bucket, 'photos/2026'); // FileDownload
await client.folders.deleteByPath(bucket, 'photos/2026/trip/');
```

### Files

```dart
final doc = await client.files.upload(
  bucket,
  UploadFile.fromString('# Plan', fileName: 'plan.md', contentType: 'text/markdown'),
  parentId: 'projects', // sent as the `ParentID` form field
  onConflict: 'rename', // or 'replace' (default)
);

// Conditional save: read the etag, send it back as ifMatch.
final current = await client.files.read(bucket, 'projects/plan.md');
try {
  await client.files.update(bucket, UpdateFileRequest(
    parentName: 'projects',
    fileName: 'plan.md',
    content: '# Plan v2',
    ifMatch: current.etag,
  ));
} on DocsException catch (e) {
  if (e.status == 412) print('changed by ${e.precondition?.updatedBy}');
}

final url = await client.files.downloadUrl(bucket, 'projects/plan.md');
```

### Nodes and permalinks

```dart
final node = await client.nodes.get(doc.id!);

final res = await client.nodes.resolve(doc.id!, download: true);
if (res.url != null) {
  print('fetch ${res.url}'); // 307: fresh short-lived URL
} else if (res.isRestoring) {
  print('in cold storage, retry in ${res.retryAfter ?? res.restoring!.retryAfterSeconds} s');
} else {
  save(res.content!.data); // 200: bytes of a file restored from cold storage
}
```

### Library

```dart
await client.library.starPath(bucket, 'projects', type: 'folder');
final recent = await client.library.recent(bucket, limit: 20);
final trashed = await client.library.trash(bucket);
await client.library.restore(bucket, trashed.first.id!);
```

### Sharing

```dart
await client.sharing.create(bucket, const CreateShareRequest(
  path: '.users/u-123/reports/q3.pdf',
  type: 'file',
  subjectType: 'user', // or 'org'
  subjectId: 'u-456',
  role: 'viewer', // or 'editor'
));
final grants = await client.sharing.list(bucket, path: '.users/u-123/reports/q3.pdf');
final link = await client.sharing.createLink(
    bucket, const CreateShareLinkRequest(path: '.users/u-123/reports/q3.pdf'));
final fileUrl = await client.sharing.resolveLink(link.token!);
```

### Folder automation

```dart
final rule = await client.automation.create(bucket, const FolderConfigRequest(
  prefix: 'invoices/',
  pipelineType: 'custom_workflow', // or 'extract_text', 'thumbnail'
  workflowId: 'wf_123',
  fileSuffixes: ['.pdf'],
));
final runs = await client.automation.jobs(bucket, configId: rule.id, limit: 10);
```

### App files

```dart
final stored = await client.appFiles.upload(
  'invoicing',
  UploadFile(bytes: pdfBytes, fileName: 'INV-0042.pdf', contentType: 'application/pdf'),
  path: '2026',
);
print(stored.permalink); // store this, not a storage URL: it survives renames
final sweep = await client.appFiles.sweep('invoicing', const SweepRequest(olderThanDays: 90));
```

### Triggers and webhooks

```dart
await client.triggers.create(const TriggerRequest(
  prefix: 'invoices/',
  suffix: '.pdf',
  eventType: 'create',
  workflowId: 'wf_123',
  active: true, // the service stores false when omitted
));

await client.webhooks.create(const WebhookRequest(
  url: 'https://hooks.example.com/documents',
  method: 'POST',
  prefix: 'uploads/',
  eventTypes: ['create', 'update'],
  headers: {'X-Secret': '...'},
  active: true,
));
final hooks = await client.webhooks.list(page: 1, limit: 50);
```

### Calling an endpoint the SDK does not wrap

`DocsHttpClient` is the transport every resource uses:

```dart
final transport = DocsHttpClient(token: '<token>', orgId: 'org_123');
final data = await transport.request('GET', '$docsBasePath/my-bucket/starred');
transport.close();
```

## Redirects and binary responses

- **URL methods** (`files.downloadUrl`, `files.previewUrl`, `sharing.resolveLink`) send the request with redirects disabled (`http.Request.followRedirects = false`) and return the `Location` of the `307` as a string. Browsers always follow redirects and never expose the `Location`, so on **Flutter web** these methods throw a `DocsException` explaining that they need a server, the Dart VM or a mobile/desktop app.
- **`nodes.resolve` / `nodes.content`** return a `NodeFileResult` with exactly one of `url` (307), `content` (200, a `FileDownload`) or `restoring` (202, an `ArchiveRestoring` for a file in cold storage; `retryAfter` holds the `Retry-After` seconds). On the web the browser follows `resolve`'s redirect itself, so you get `content` (when the file host allows the cross-origin read).
- **Binary downloads** (`folders.downloadZip`, node content) return `FileDownload { data, contentType, fileName }`; `fileName` comes from `X-File-Name`, else the `Content-Disposition` filename.

## Errors

Every failure throws `DocsException` with `message`, `status`, `code` and `payload`:

```dart
try {
  await client.files.get(bucket, 'missing.md');
} on DocsException catch (e) {
  print('${e.status} ${e.code} ${e.message} ${e.payload}');
}
```

- Non-2xx response: `status` is the HTTP status and `payload` the decoded JSON body (or the raw text). `message` comes from the body: for `{"status": 0, "error": {"message", "code", "details"}}` a platform code in `error.message` (e.g. `AAS-00106`) goes to `code` and `error.details` becomes the message; for `{"message": "..."}` it is that message; otherwise `Request failed with status <n>`.
- `412` from a conditional save: `precondition` holds the file's current etag and last editor.
- Network error or timeout: `status` is `0` and `payload` is `null`.

## Using it with other lowco packages

`lowcoai_workflow`, `lowcoai_integrations` and `lowcoai_lowcodb` export some of the same names (`ApiEnvelope`, `BaseEntity`, `JsonObject`, `TriggersResource`, `WebhooksResource`, `lowcoBaseUrl`, `headerOrgId`). Import one of the packages with a prefix when you use both in one file:

```dart
import 'package:lowcoai_docs/lowcoai_docs.dart' as docs;
import 'package:lowcoai_workflow/lowcoai_workflow.dart';
```
