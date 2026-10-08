# lowcoai_workflow

Dart / Flutter client for the **workflow-orchestrator** product (routes under `/v1/wf/*`). Pure Dart on top of [`package:http`](https://pub.dev/packages/http), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM. It mirrors the TypeScript SDK `@lowcoai/workflow`.

```yaml
dependencies:
  lowcoai_workflow: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_workflow/lowcoai_workflow.dart';

final client = WorkflowClient(token: '<token-or-api-key>', orgId: 'org_123');

final workflows = await client.workflows.list(const PaginationQuery(page: 1, limit: 20));

// Start from the beginning
await client.workflows.run(const RunWorkflowRequest(
  workflowId: 'wf_123',
  inputData: {'orderId': 'o_1'},
  environmentId: 'env_default',
));

// Resume from an intermediate activity
await client.workflows.run(const RunWorkflowRequest(
  workflowId: 'wf_123',
  activityId: 'human_review_1',
  executionId: 'exe_123',
  environmentId: 'env_default',
));

// Complete a human task
final tasks = await client.humanTasks.list(const PaginationQuery(page: 1, limit: 10));
if (tasks.isNotEmpty) await client.humanTasks.complete(tasks.first.id!, 'approve');

client.close();
```

## Options

| Parameter    | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| `token`      | User token or API key, sent as `Authorization: Bearer <token>`. Required (`ArgumentError` if blank). Not sent when `headers` already contain `Authorization`. |
| `orgId`      | Sent as the `X-Org-Id` header, unless `headers` already contain one.                 |
| `timeout`    | Per-request timeout (default 30 s); `null` disables it. A timed-out request is aborted and throws `WorkflowException` with status `0`. |
| `headers`    | Extra headers added to every request.                                                |
| `httpClient` | Your own `http.Client` (e.g. `cupertino_http` / `cronet_http` in Flutter, or `MockClient` in tests). Not closed by `close()`. |

Every request goes to `https://api.lowco.ai`. Responses are unwrapped from the `{ success, data, error, message }` envelope.

## Data shapes

Entities are immutable model classes named like the TS types (`Workflow`, `Environment`, `FunctionEntity`, `Execution`, `HumanTask`, …) with `fromJson` / `toJson`. Field names match the wire; fields that are required in TS are `required` here; `toJson` omits null fields. Timestamps are ISO-8601 strings, free-form JSON is `Map<String, dynamic>` / `Object?`.

`WorkflowUINode` keeps every key it does not model (`position`, `measured`, `selected`, …) in `extra` and writes it back in `toJson`, so a canvas graph read with `getById` can be sent back with `update` without losing anything.

List methods take an optional `PaginationQuery(page:, limit:, sortBy:, sortOrder:, where:, extra: {...})`. Anything in `extra` is sent as a query parameter too (booleans as `true`/`false`, numbers as strings, other objects as JSON; `null` is skipped).

## Surface

| Resource              | Methods |
| --------------------- | ------- |
| `client.workflows`    | `list`, `count`, `getById`, `create`, `update`, `delete`, `run`, `versions`, `publish`, `published`, `publishedCount`, `getPublishedById`, `updatePublished`, `deletePublished`, `webPublished`, `webPublishedById`, `searchPublishedTemplates({q, category, limit})` |
| `client.environments` | `list`, `getById`, `create`, `update`, `delete`, `setDefault` |
| `client.functions`    | `list`, `getById`, `create`, `update`, `delete`, `versions`, `execute` |
| `client.executions`   | `list([query, full])`, `count`, `getById`, `logs` |
| `client.activities`   | `list`, `count`, `getById`, `logs` |
| `client.humanTasks`   | `list`, `getById`, `complete` |
| `client.analytics`    | `getDefault` (`default()` in TS — a reserved word in Dart), `getById` |
| `client.dryRun`       | `execute` |
| `client.webhooks`     | `trigger(workflowId, {payload, env, triggeredBy, async})` — the only webhook route the orchestrator serves; register webhooks through the integrations service |

`count`-style methods return `Object?` (a number or an object, like the TS SDK). `create` / `update` of workflows accept a `Workflow` or a `WorkflowUpdateRequest` (which adds a version `comment`).

### Webhooks

```dart
await client.webhooks.trigger(
  'wf_123',
  payload: {'orderId': 'o_2'},
  env: 'prod',
  triggeredBy: 'crm',
  async: true, // return without waiting for the run
);
```

### Calling an endpoint the SDK does not wrap

`WorkflowHttpClient` is the transport every resource uses (the TS SDK's `HttpClient`):

```dart
final transport = WorkflowHttpClient(token: '<token>', orgId: 'org_123');
final data = await transport.request('GET', '/v1/wf/workflows', query: {'page': 1});
transport.close();
```

## Errors

Every failure throws `WorkflowException` with `message`, `status` and `payload` (the TS SDK's `WorkflowError`):

```dart
try {
  await client.workflows.getById('wf_unknown');
} on WorkflowException catch (e) {
  print('${e.status} ${e.payload}');
}
```

- Non-2xx response: `message` is `Request failed with status <n>`, `status` the HTTP status and `payload` the decoded JSON body — or the raw text when the body is not JSON.
- Network error or timeout: `status` is `0` and `payload` is `null`.

## Using it with other lowco packages

`lowcoai_integrations` exports the same `PaginationQuery`, `BaseEntity`, `ApiEnvelope`, `JsonObject`, `lowcoBaseUrl` and `headerOrgId` names (and `lowcoai_lowcodb` some of them), like their TS counterparts. Import one of the packages with a prefix when you use both in one file:

```dart
import 'package:lowcoai_integrations/lowcoai_integrations.dart' as integrations;
import 'package:lowcoai_workflow/lowcoai_workflow.dart';
```
