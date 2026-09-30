# lowcoai_lowcodb

Dart / Flutter client for the **lowcodb manager** service. Pure Dart on top of [`package:http`](https://pub.dev/packages/http), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM.

```yaml
dependencies:
  lowcoai_lowcodb: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_lowcodb/lowcoai_lowcodb.dart';

final client = LowcodbClient(token: '<token-or-api-key>', orgId: 'org_123');

final bases = await client.listBases();
final base = await client.createBase(const Base(name: 'crm', baseType: 'internal'));

final row = await client.createRecord(base.schema!, 'leads', {'name': 'Ada', 'status': 'open'});
final open = await client.listRecords(
  base.schema!,
  'leads',
  const ListParams(filter: "status='open'", size: 50),
);

client.close();
```

## Options

| Parameter        | Description                                                                          |
| ---------------- | ------------------------------------------------------------------------------------ |
| `token`          | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `orgId`          | Sent as the `X-Org-Id` header.                                                       |
| `baseUrl`        | Origin of the manager, e.g. `http://lowcodb-service:8080` in-cluster. Defaults to `https://api.lowco.ai`. |
| `apiBasePath`    | Route prefix, default `/v1/lowcodb`.                                                 |
| `defaultHeaders` | Extra headers added to every request.                                                |
| `timeout`        | Per-request timeout (default 30 s); `null` disables it. A timed-out request is aborted and throws `TimeoutException`. |
| `httpClient`     | Your own `http.Client` (e.g. `cupertino_http` / `cronet_http` in Flutter, or `MockClient` in tests). Not closed by `close()`. |

`client.setOrgId(...)` and `client.setHeader(key, value)` change headers for later requests; pass `null` to remove.

## Data shapes

Entities are immutable model classes (`Base`, `Table`, `Column`, `DBFunction`, …) with `fromJson` / `toJson`. Field names match the wire; `toJson` omits null fields, so an update only sends what you set. Rows are `Map<String, dynamic>` (`LowcodbRecord`). Timestamps are ISO-8601 strings, as sent by the server.

List methods take an optional `ListParams(pageNo:, size:, filter:, sort:)`.

## Surface

| Area             | Methods |
| ---------------- | ------- |
| Health           | `health` |
| Bases            | `getBase`, `createBase`, `updateBase`, `deleteBase`, `listBases`, `exportBaseCollection` (bytes), `syncBaseTables` |
| Tables           | `getTable`, `createTable`, `updateTable`, `deleteTable`, `listTables` |
| Columns          | `getColumn`, `createColumn`, `bulkCreateColumns`, `updateColumn`, `bulkUpdateColumns`, `deleteColumn`, `listColumns`, `validateField` |
| Table indexes    | `getTableIndex`, `createTableIndex`, `updateTableIndex`, `listTableIndexes`, `deleteTableIndex` |
| Records          | `createRecord`, `getRecord`, `updateRecord`, `deleteRecord`, `listRecords`, `countRecords`, `createBulkRecords`, `updateBulkRecords`, `deleteBulkRecords` |
| View data        | `getViewRecord`, `listViewRecords`, `countViewRecords` |
| Dashboards       | `getOverviewCounts`, `getMetricsDashboard`, `getDashboardOverview` |
| Triggers         | `getTrigger`, `createTrigger`, `updateTrigger`, `deleteTrigger`, `listTriggers` |
| Webhooks         | `getWebhook`, `createWebhook`, `updateWebhook`, `deleteWebhook`, `listWebhooks` |
| Transactions     | `executeTransaction` |
| Events           | `publishEvent` |
| DB functions     | `listFunctions`, `getFunction`, `createFunction`, `updateFunction`, `deleteFunction`, `listFunctionVersions`, `executeFunction`, `invokeFunction` |
| Query            | `executeQuery`, `getQuerySuggestions` |
| Views (metadata) | `listViews`, `createView`, `getView`, `updateView`, `deleteView`, `refreshView` |

### Transactions

```dart
await client.executeTransaction('app_crm', [
  const TransactionOperation(type: 'create', table: 'leads', record: {'name': 'Ada'}),
  const TransactionOperation(type: 'update', table: 'accounts', id: 'acc_1', record: {'leadCount': 4}),
]);
```

### DB functions

```dart
final result = await client.executeFunction(fnId, {'value': 21}); // console run: result, logs, error
final value = await client.invokeFunction('app_crm', 'score-lead', body: {'value': 21});
final viaGet = await client.invokeFunction('app_crm', 'score-lead', method: 'GET');
```

## Errors

Every non-2xx response throws `LowcodbException` with `statusCode`, `message`, `code` and the raw `body`:

```dart
try {
  await client.invokeFunction('app_crm', 'score-lead', body: {});
} on LowcodbException catch (e) {
  print('${e.statusCode} ${e.message}');
}
```

When the manager answers with an opaque platform code (`AAS-00105`) as the message, `message` carries the human-readable `error.details` instead; the code is still in `body`.
