# lowcodb — REST surface

Language-agnostic reference for the lowcodb manager API consumed by the [Go](../go/lowcodb), [npm](../npm/lowcodb), [Python](../python/lowcodb) and [Dart / Flutter](../flutter/lowcodb) SDKs.

All routes live under the base path **`/v1/lowcodb`** (overridable per-SDK).

---

## Authentication & tenancy

The API host is always `https://api.lowco.ai`. Every request carries:

| Header           | Purpose                                                        |
| ---------------- | -------------------------------------------------------------- |
| `Authorization`  | `Bearer <user-token-or-api-key>` — required; identifies the acting user. |
| `X-Org-Id`       | Tenant ID — scopes reads and writes.                            |

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

All record routes are scoped to `{schema}` (the base's `schema` field) and `{tableName}` (the table's `name`).

| Method | Path                                                         | Purpose                          |
| ------ | ------------------------------------------------------------ | -------------------------------- |
| GET    | `/data/{schema}/tables/{tableName}/records`                  | Paginated list.                  |
| GET    | `/data/{schema}/tables/{tableName}/records/count`            | Row count (honors `filter`).     |
| GET    | `/data/{schema}/tables/{tableName}/records/{id}`             | Fetch one.                       |
| POST   | `/data/{schema}/tables/{tableName}/records`                  | Insert.                          |
| PUT    | `/data/{schema}/tables/{tableName}/records/{id}`             | Update.                          |
| DELETE | `/data/{schema}/tables/{tableName}/records/{id}`             | Delete one. Returns `{deletedCount}`. |
| POST   | `/data/{schema}/tables/{tableName}/records/bulk`             | Bulk insert.                     |
| PUT    | `/data/{schema}/tables/{tableName}/records/bulk`             | Bulk update. Returns `RecordsBulkResult`. |
| DELETE | `/data/{schema}/tables/{tableName}/records/bulk`             | Bulk delete; body is the criterion. |

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

Read-only data routes (mirror tables):

| Method | Path                                               | Purpose            |
| ------ | -------------------------------------------------- | ------------------ |
| GET    | `/data/{schema}/views/{viewName}/records`          | Paginated list.    |
| GET    | `/data/{schema}/views/{viewName}/records/count`    | Count.             |
| GET    | `/data/{schema}/views/{viewName}/records/{id}`     | Fetch one row.     |

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
| `POST /data/{schema}/tables/{name}/records`             | `CreateRecord`             | `createRecord`           |
| `GET /data/{schema}/tables/{name}/records`              | `ListRecords`              | `listRecords`            |
| `GET /data/{schema}/tables/{name}/records/{id}`         | `GetRecord`                | `getRecord`              |
| `PUT /data/{schema}/tables/{name}/records/{id}`         | `UpdateRecord`             | `updateRecord`           |
| `DELETE /data/{schema}/tables/{name}/records/{id}`      | `DeleteRecord`             | `deleteRecord`           |
| `GET /data/{schema}/tables/{name}/records/count`        | `CountRecords`             | `countRecords`           |
| `POST /data/{schema}/tables/{name}/records/bulk`        | `CreateBulkRecords`        | `createBulkRecords`      |
| `PUT /data/{schema}/tables/{name}/records/bulk`         | `UpdateBulkRecords`        | `updateBulkRecords`      |
| `DELETE /data/{schema}/tables/{name}/records/bulk`      | `DeleteBulkRecords`        | `deleteBulkRecords`      |
| `GET /data/{schema}/views/{name}/records`               | `ListViewRecords`          | `listViewRecords`        |
| `GET /data/{schema}/views/{name}/records/{id}`          | `GetViewRecord`            | `getViewRecord`          |
| `GET /data/{schema}/views/{name}/records/count`         | `CountViewRecords`         | `countViewRecords`       |
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
