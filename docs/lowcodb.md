# lowcodb — REST surface

Language-agnostic reference for the lowcodb manager API consumed by the [Go](../go/lowcodb), [npm](../npm/lowcodb), [Python](../python/lowcodb) and [Dart / Flutter](../flutter/lowcodb) SDKs.

All routes live under the base path **`/v1/lowcodb`** (overridable per-SDK).

---

## Authentication & tenancy

The API host is always `https://api.lowco.ai`. Every request carries:

| Header           | Purpose                                                        |
| ---------------- | -------------------------------------------------------------- |
| `Authorization`  | `Bearer <user-token>` — identifies the acting user.             |
| `X-Api-Key`      | `lc_…` API key — instead of `Authorization`. The SDKs pick the header from the token's shape. |
| `X-Org-Id`       | Tenant ID — scopes reads and writes.                            |

## Where a base's data is served: the gateway

The **management plane** (bases, tables, columns, views, functions, query, …) lives under
`/v1/lowcodb`. The **data plane** — records, view rows, DB-function invocation and
transactions — is served only by the base's **API gateway**:

```
https://api.lowco.ai/gateway/<hash>/v1/<table>[/<id>|/count|/bulk]
https://api.lowco.ai/gateway/<hash>/v1/views/<view>[/<id>|/count]
https://api.lowco.ai/gateway/<hash>/v1/fn/<functionKey>
https://api.lowco.ai/gateway/<hash>/v1/transactions
```

The manager's `/v1/lowcodb/data/...` and `/v1/lowcodb/fn/...` routes are cluster-internal.
Every base has a gateway from creation; `GET /v1/lowcodb/bases/{id}/gateway` and
`GET /v1/lowcodb/bases/gateway-by-schema/{schema}` answer where it is:

```json
{ "gatewayId": "…", "hash": "WOsqwRyURn", "contextPath": "/gateway/WOsqwRyURn",
  "url": "https://api.lowco.ai/gateway/WOsqwRyURn",
  "internalUrl": "http://gateway-svc-…:80/gateway/WOsqwRyURn",
  "routes": { "tables": "/v1/{table}", "views": "/v1/views/{view}", "functions": "/v1/fn/{key}", "transactions": "/v1/transactions" },
  "sync": { "status": "synced", "syncedAt": "…", "routeCount": 42 } }
```

The SDKs keep their `(schema, table)` signatures and resolve the schema's gateway behind
them (looked up once, cached 10 minutes, looked up again on a 404 — the hash can be
regenerated). Each also offers:

- a **pinned gateway** per schema (`WithGateway` / `gateways:` / `gateways=` /
  `gateways:`), for API keys that may call the gateway but not the management API;
- the **internal origin** (`WithGatewayOrigin(GatewayOriginInternal)` /
  `gatewayOrigin: "internal"` / `gateway_origin="internal"` / `GatewayOrigin.internal`),
  for callers inside the cluster;
- a **GatewayClient** (`client.Gateway(path)` / `client.gateway(path)`) with the same
  data methods minus the schema, for callers that hold the gateway rather than the base.

The gateway authenticates every call (kavach) and requires a permission per route — the
platform's `lowcodb.data.tables.read|write|delete`, `lowcodb.data.views.read`,
`lowcodb.functions.invoke.execute`, `lowcodb.records.transactions.write` unless the
base's app publishes its own policy. List and count routes forward only `filter`,
`sort`, `pageNo` and `size`. A plan cap answers **402** with `{"code": "QUOTA_EXCEEDED",
"meter", "consumed", "included", "hard_cap", "period_end", "app_key", "upgrade": {…}}`,
which the SDKs raise as `QuotaExceededError` / `QuotaExceededException`.

```go
lowcodb.NewClient("<token-or-api-key>", lowcodb.WithOrgID("..."))
```

```ts
new LowcodbClient({ token: "<token-or-api-key>", orgId: "..." })
```

```python
LowcodbClient("<token-or-api-key>", org_id="...")  # or AsyncLowcodbClient
```

```dart
LowcodbClient(token: '<token-or-api-key>', orgId: '...')
```

---

## Response envelope

Almost every endpoint returns the manager's standard envelope. The SDKs unwrap `data` for you and only surface the inner value to callers.

```json
{
  "success": true,
  "data":    <payload>,
  "message": "ok",
  "error":   null
}
```

Exceptions (returned un-enveloped):

- `POST /validate` — returns `ValidationResponse` directly.
- `GET /health` — empty body.
- `GET /metrics` — Prometheus text exposition.
- `GET /bases/{id}/export` — `application/json` Postman collection (raw bytes).

### Error envelope

```json
{
  "success": false,
  "data":    null,
  "message": "human readable",
  "error":   {
    "code":    "OPTIONAL_CODE",
    "message": "developer-facing detail",
    "details": { ... }
  }
}
```

Every SDK translates this into a typed exception:

| SDK | Exception | Fields |
| --- | --------- | ------ |
| Go  | `*lowcodb.RequestError` | `StatusCode`, `Message`, `Code`, `Body` |
| npm | `LowcodbError`          | `statusCode`, `message`, `code`, `body` |
| Python | `LowcodbError`       | `status_code`, `message`, `code`, `body` |
| Dart   | `LowcodbException`   | `statusCode`, `message`, `code`, `body` |

---

## Pagination & filtering

Endpoints that list collections accept these query parameters:

| Param    | Description                                                  |
| -------- | ------------------------------------------------------------ |
| `pageNo` | 1-based page index.                                          |
| `size`   | Page size. Use `-1` for "all rows" (where the manager allows).|
| `filter` | Manager filter DSL, e.g. `name = "leads"` or `score > 50`.   |
| `sort`   | Comma-separated; prefix with `-` for descending.             |

The SDKs ship a `ListParams` helper (Go: struct; npm: object literal; Dart: `ListParams` class). The Python SDK takes them as keyword arguments (`page_no=`, `size=`, `filter=`, `sort=`).

---

## Endpoint groups

### Bases

A *base* is a logical database (its own schema, optionally backed by an external connection).

| Method | Path                                       | Purpose                                  |
| ------ | ------------------------------------------ | ---------------------------------------- |
| GET    | `/bases`                                   | List bases (paginated).                  |
| POST   | `/bases`                                   | Create a base.                           |
| GET    | `/bases/{id}`                              | Fetch one.                               |
| PUT    | `/bases/{id}`                              | Update.                                  |
| DELETE | `/bases/{id}`                              | Drop the base **and its schema**.        |
| GET    | `/bases/{id}/export`                       | Download a Postman collection.           |
| POST   | `/bases/{id}/sync-tables`                  | Reconcile external-DB tables (external bases only). Returns `SyncTablesResult`. |

`baseType` is `internal` (default; lowcodb-managed schema) or `external` (a registered `connectionId` is required; lowcodb reads through but never mutates external DDL).

### Tables

| Method | Path             | Purpose                       |
| ------ | ---------------- | ----------------------------- |
| GET    | `/tables`        | List (paginated).             |
| POST   | `/tables`        | Create. Returns `TableWithColumns`. |
| GET    | `/tables/{id}`   | Fetch (with column summaries).|
| PUT    | `/tables/{id}`   | Update.                       |
| DELETE | `/tables/{id}`   | Drop.                         |

### Columns

| Method | Path                                          | Purpose                       |
| ------ | --------------------------------------------- | ----------------------------- |
| GET    | `/tables/{tableId}/columns`                   | List (paginated).             |
| GET    | `/tables/{tableId}/columns/{id}`              | Fetch.                        |
| POST   | `/tables/{tableId}/columns`                   | Create.                       |
| POST   | `/tables/{tableId}/columns/bulk`              | Bulk create. Returns `ColumnsBulkResult`. |
| PUT    | `/tables/{tableId}/columns/{id}`              | Update.                       |
| PUT    | `/tables/{tableId}/columns/bulk`              | Bulk update.                  |
| DELETE | `/tables/{tableId}/columns/{id}`              | Drop.                         |
| POST   | `/validate`                                   | Field-level validation (un-enveloped). |

### Table indexes

| Method | Path                                           | Purpose       |
| ------ | ---------------------------------------------- | ------------- |
| GET    | `/tables/{tableId}/indexes`                    | List.         |
| GET    | `/tables/{tableId}/index/{id}`                 | Fetch one.    |
| POST   | `/tables/{tableId}/index`                      | Create.       |
| PUT    | `/tables/{tableId}/index/{id}`                 | Rename (`indexName` only). |
| DELETE | `/tables/{tableId}/index/{id}`                 | Drop.         |

### Records (table data)

Served by the base's gateway (see above). `{table}` is the table's key.

| Method | Path (under `/gateway/<hash>`) | Purpose                          |
| ------ | ------------------------------ | -------------------------------- |
| GET    | `/v1/{table}`                  | Paginated list (`filter`, `sort`, `pageNo`, `size`). |
| GET    | `/v1/{table}/count`            | Row count (honors `filter`).     |
| GET    | `/v1/{table}/{id}`             | Fetch one.                       |
| POST   | `/v1/{table}`                  | Insert.                          |
| PUT    | `/v1/{table}/{id}`             | Update.                          |
| DELETE | `/v1/{table}/{id}`             | Delete one. Returns `{deletedCount}`. |
| POST   | `/v1/{table}/bulk`             | Bulk insert.                     |
| PUT    | `/v1/{table}/bulk`             | Bulk update. Returns `RecordsBulkResult`. |
| DELETE | `/v1/{table}/bulk`             | Bulk delete; body is the criterion. |
| POST   | `/v1/transactions`             | Ordered writes in one transaction (internal bases). |
| *      | `/v1/fn/{functionKey}`         | Invoke an active DB function (methods as it allows). |

Validation errors are returned as `400` with a per-field map (the SDKs surface them through `LowcodbError`/`RequestError`/`LowcodbException`).

### Views

Metadata routes:

| Method | Path             | Purpose             |
| ------ | ---------------- | ------------------- |
| GET    | `/views`         | List.               |
| POST   | `/views`         | Create.             |
| GET    | `/views/{id}`    | Fetch.              |
| PUT    | `/views/{id}`    | Update.             |
| DELETE | `/views/{id}`    | Drop.               |
| POST   | `/views/{id}/refresh` | Refresh a materialized view; body `{ "concurrent": bool }`. |

Read-only data routes, on the base's gateway:

| Method | Path (under `/gateway/<hash>`) | Purpose            |
| ------ | ------------------------------ | ------------------ |
| GET    | `/v1/views/{view}`             | Paginated list.    |
| GET    | `/v1/views/{view}/count`       | Count.             |
| GET    | `/v1/views/{view}/{id}`        | Fetch one row.     |

### Triggers

| Method | Path                  | Purpose                                                      |
| ------ | --------------------- | ------------------------------------------------------------ |
| GET    | `/triggers`           | List; each entry is enriched with `workflowName` when available. |
| POST   | `/triggers`           | Create. `{ baseId, tableId, eventType, eventTime, workflowId }`. |
| GET    | `/triggers/{id}`      | Fetch.                                                       |
| PUT    | `/triggers/{id}`      | Update.                                                      |
| DELETE | `/triggers/{id}`      | Drop.                                                        |

### Webhooks

| Method | Path                  | Purpose                                                                                |
| ------ | --------------------- | -------------------------------------------------------------------------------------- |
| GET    | `/webhooks`           | List.                                                                                  |
| POST   | `/webhooks`           | Create. `{ baseId, tableId, url, method, headers, eventTypes[], active }`.             |
| GET    | `/webhooks/{id}`      | Fetch.                                                                                 |
| PUT    | `/webhooks/{id}`      | Update.                                                                                |
| DELETE | `/webhooks/{id}`      | Drop.                                                                                  |

### Query

| Method | Path                              | Purpose                                                          |
| ------ | --------------------------------- | ---------------------------------------------------------------- |
| POST   | `/query/execute`                  | Run a SELECT/INSERT/UPDATE/DELETE statement against one base. Body `{ query, baseId }` (or `{ query, schema }`). Returns `{ rows: [...] }`. |
| GET    | `/query/suggestions?query=&baseId=` | Autocomplete suggestions for the editor. Returns `{ suggestions: [...] }`. |

`baseId` (or `schema`) is required and the query runs against that one base within your org — the manager never targets its metadata schema and never crosses orgs. Only single SELECT/INSERT/UPDATE/DELETE statements are allowed (no DDL, no multiple statements, no comments); SELECT needs the `lowcodb.query.core.read` permission and INSERT/UPDATE/DELETE need `lowcodb.query.core.write`.

### Dashboards

| Method | Path                                              | Purpose                                                                                  |
| ------ | ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| GET    | `/overview/counts`                                | Counts of bases / tables / columns, with a per-base breakdown.                           |
| GET    | `/metrics/dashboard?range=&from=&to=&baseId=`     | Time-bucketed activity. `range` is a Go duration like `"5m"`; `from`/`to` are RFC 3339.  |
| GET    | `/dashboard/overview?baseId=&tableId=&startDate=&endDate=` | High-level activity rollup backed by ClickHouse.                                  |

### Health & metrics

| Method | Path        | Purpose                            |
| ------ | ----------- | ---------------------------------- |
| GET    | `/health`   | Liveness probe.                    |
| GET    | `/metrics`  | Prometheus exposition (text/plain).|

---

## SDK ↔ endpoint cheat sheet

| Endpoint                                                | Go method                  | npm method               |
| ------------------------------------------------------- | -------------------------- | ------------------------ |
| `GET /bases`                                            | `ListBases`                | `listBases`              |
| `POST /bases`                                           | `CreateBase`               | `createBase`             |
| `GET /bases/{id}`                                       | `GetBase`                  | `getBase`                |
| `PUT /bases/{id}`                                       | `UpdateBase`               | `updateBase`             |
| `DELETE /bases/{id}`                                    | `DeleteBase`               | `deleteBase`             |
| `GET /bases/{id}/export`                                | `ExportBaseCollection`     | `exportBaseCollection`   |
| `POST /bases/{id}/sync-tables`                          | `SyncBaseTables`           | `syncBaseTables`         |
| `GET /tables`                                           | `ListTables`               | `listTables`             |
| `POST /tables`                                          | `CreateTable`              | `createTable`            |
| `GET /tables/{id}`                                      | `GetTable`                 | `getTable`               |
| `PUT /tables/{id}`                                      | `UpdateTable`              | `updateTable`            |
| `DELETE /tables/{id}`                                   | `DeleteTable`              | `deleteTable`            |
| `GET /tables/{tableId}/columns`                         | `ListColumns`              | `listColumns`            |
| `POST /tables/{tableId}/columns`                        | `CreateColumn`             | `createColumn`           |
| `POST /tables/{tableId}/columns/bulk`                   | `BulkCreateColumns`        | `bulkCreateColumns`      |
| `PUT /tables/{tableId}/columns/{id}`                    | `UpdateColumn`             | `updateColumn`           |
| `PUT /tables/{tableId}/columns/bulk`                    | `BulkUpdateColumns`        | `bulkUpdateColumns`      |
| `DELETE /tables/{tableId}/columns/{id}`                 | `DeleteColumn`             | `deleteColumn`           |
| `GET /tables/{tableId}/columns/{id}`                    | `GetColumn`                | `getColumn`              |
| `POST /validate`                                        | `ValidateField`            | `validateField`          |
| `POST /tables/{tableId}/index`                          | `CreateTableIndex`         | `createTableIndex`       |
| `GET /tables/{tableId}/index/{id}`                      | `GetTableIndex`            | `getTableIndex`          |
| `PUT /tables/{tableId}/index/{id}`                      | `UpdateTableIndex`         | `updateTableIndex`       |
| `GET /tables/{tableId}/indexes`                         | `ListTableIndexes`         | `listTableIndexes`       |
| `DELETE /tables/{tableId}/index/{id}`                   | `DeleteTableIndex`         | `deleteTableIndex`       |
| `POST /gateway/<hash>/v1/{table}`                        | `CreateRecord`             | `createRecord`           |
| `GET /gateway/<hash>/v1/{table}`                         | `ListRecords`              | `listRecords`            |
| `GET /gateway/<hash>/v1/{table}/{id}`                    | `GetRecord`                | `getRecord`              |
| `PUT /gateway/<hash>/v1/{table}/{id}`                    | `UpdateRecord`             | `updateRecord`           |
| `DELETE /gateway/<hash>/v1/{table}/{id}`                 | `DeleteRecord`             | `deleteRecord`           |
| `GET /gateway/<hash>/v1/{table}/count`                   | `CountRecords`             | `countRecords`           |
| `POST /gateway/<hash>/v1/{table}/bulk`                   | `CreateBulkRecords`        | `createBulkRecords`      |
| `PUT /gateway/<hash>/v1/{table}/bulk`                    | `UpdateBulkRecords`        | `updateBulkRecords`      |
| `DELETE /gateway/<hash>/v1/{table}/bulk`                 | `DeleteBulkRecords`        | `deleteBulkRecords`      |
| `GET /gateway/<hash>/v1/views/{view}`                    | `ListViewRecords`          | `listViewRecords`        |
| `GET /gateway/<hash>/v1/views/{view}/{id}`               | `GetViewRecord`            | `getViewRecord`          |
| `GET /gateway/<hash>/v1/views/{view}/count`         | `CountViewRecords`         | `countViewRecords`       |
| `GET /views`                                            | `ListViews`                | `listViews`              |
| `POST /views`                                           | `CreateView`               | `createView`             |
| `GET /views/{id}`                                       | `GetView`                  | `getView`                |
| `PUT /views/{id}`                                       | `UpdateView`               | `updateView`             |
| `DELETE /views/{id}`                                    | `DeleteView`               | `deleteView`             |
| `POST /views/{id}/refresh`                              | `RefreshView`              | `refreshView`            |
| `GET /triggers`                                         | `ListTriggers`             | `listTriggers`           |
| `POST /triggers`                                        | `CreateTrigger`            | `createTrigger`          |
| `GET /triggers/{id}`                                    | `GetTrigger`               | `getTrigger`             |
| `PUT /triggers/{id}`                                    | `UpdateTrigger`            | `updateTrigger`          |
| `DELETE /triggers/{id}`                                 | `DeleteTrigger`            | `deleteTrigger`          |
| `GET /webhooks`                                         | `ListWebhooks`             | `listWebhooks`           |
| `POST /webhooks`                                        | `CreateWebhook`            | `createWebhook`          |
| `GET /webhooks/{id}`                                    | `GetWebhook`               | `getWebhook`             |
| `PUT /webhooks/{id}`                                    | `UpdateWebhook`            | `updateWebhook`          |
| `DELETE /webhooks/{id}`                                 | `DeleteWebhook`            | `deleteWebhook`          |
| `POST /query/execute`                                   | `ExecuteQuery`             | `executeQuery`           |
| `GET /query/suggestions`                                | `GetQuerySuggestions`      | `getQuerySuggestions`    |
| `GET /overview/counts`                                  | `GetOverviewCounts`        | `getOverviewCounts`      |
| `GET /metrics/dashboard`                                | `GetMetricsDashboard`      | `getMetricsDashboard`    |
| `GET /dashboard/overview`                               | `GetDashboardOverview`     | `getDashboardOverview`   |
| `GET /health`                                           | `Health`                   | `health`                 |
