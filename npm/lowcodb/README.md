# @lowcoai/lowcodb

TypeScript / Node client for the lowcodb manager service. Works in any environment that ships a global `fetch` (Node 18+, modern browsers, Bun, Deno).

```bash
npm install @lowcoai/lowcodb
```

## Quick start

```ts
import { LowcodbClient } from "@lowcoai/lowcodb";

const client = new LowcodbClient({
  baseURL: "http://localhost:8080",
  orgId: "org_123",
  userId: "user_123",
});

// 1. Create a base
const base = await client.createBase({ name: "Sales", baseType: "internal" });

// 2. Define a table
const table = await client.createTable({ baseId: base.id, name: "leads" });

// 3. Add columns
await client.bulkCreateColumns(table.id!, [
  { name: "email", dataType: "string" },
  { name: "score", dataType: "int" },
]);

// 4. Insert a record (path uses base.schema and table.name)
const created = await client.createRecord(base.schema!, table.name!, {
  email: "alice@example.com",
  score: 87,
});

// 5. Paginated list
const rows = await client.listRecords(base.schema!, table.name!, {
  pageNo: 1,
  size: 25,
  filter: "score > 50",
  sort: "-createdAt",
});
```

## Options

| Option           | Description                                               |
| ---------------- | --------------------------------------------------------- |
| `baseURL`        | Manager URL (required).                                   |
| `orgId`          | Sets `X-Org-Id`.                                          |
| `userId`         | Sets `X-User-Id`.                                         |
| `defaultHeaders` | Extra headers added to every request.                     |
| `apiBasePath`    | Overrides `/v1/lowcodb` (useful behind reverse proxies).  |
| `fetch`          | Custom fetch implementation (defaults to global `fetch`). |
| `timeoutMs`      | Per-request timeout (default 30 000; `0` disables).       |

You can also mutate identity at runtime: `client.setOrgId(...)`, `client.setUserId(...)`, `client.setHeader(k, v)`.

## Errors

Every non-2xx response throws `LowcodbError`:

```ts
import { LowcodbError } from "@lowcoai/lowcodb";

try {
  await client.getBase("missing");
} catch (err) {
  if (err instanceof LowcodbError) {
    console.error(err.statusCode, err.code, err.message, err.body);
  }
}
```

## API coverage

The client mirrors `lowcodb/manager/server/server.go` 1-to-1:

- **Bases** — `getBase`, `createBase`, `updateBase`, `deleteBase`, `listBases`, `exportBaseCollection`, `syncBaseTables`
- **Tables** — `getTable`, `createTable`, `updateTable`, `deleteTable`, `listTables`
- **Columns** — `getColumn`, `createColumn`, `bulkCreateColumns`, `updateColumn`, `bulkUpdateColumns`, `deleteColumn`, `listColumns`, `validateField`
- **Indexes** — `getTableIndex`, `createTableIndex`, `updateTableIndex`, `listTableIndexes`, `deleteTableIndex`
- **Records** — `createRecord`, `getRecord`, `updateRecord`, `deleteRecord`, `listRecords`, `countRecords`, `createBulkRecords`, `updateBulkRecords`, `deleteBulkRecords`
- **Views (data)** — `getViewRecord`, `listViewRecords`, `countViewRecords`
- **Views (metadata)** — `listViews`, `createView`, `getView`, `updateView`, `deleteView`, `refreshView`
- **Triggers** — `getTrigger`, `createTrigger`, `updateTrigger`, `deleteTrigger`, `listTriggers`
- **Webhooks** — `getWebhook`, `createWebhook`, `updateWebhook`, `deleteWebhook`, `listWebhooks`
- **Query** — `executeQuery`, `getQuerySuggestions`
- **Dashboards** — `getOverviewCounts`, `getMetricsDashboard`, `getDashboardOverview`
- **Health** — `health`

See [../../docs/lowcodb.md](../../docs/lowcodb.md) for the REST surface.
