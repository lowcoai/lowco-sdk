# @lowcoai/lowcodb

TypeScript / Node client for the lowcodb manager service. Works in any environment that ships a global `fetch` (Node 18+, modern browsers, Bun, Deno).

```bash
npm install @lowcoai/lowcodb
```

## Quick start

```ts
import { LowcodbClient } from "@lowcoai/lowcodb";

const client = new LowcodbClient({
  token: "<token-or-api-key>", // required
  orgId: "org_123",
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

## DB functions

Author, version, and invoke server-side JavaScript functions on a base:

```ts
const fn = await client.createFunction({
  baseId: base.id,
  name: "create lead",
  body: `const lead = await ctx.db.table("leads").create(ctx.request.body);
return { lead };`,
});

// Console/test run — full result with logs and errors:
const run = await client.executeFunction(fn.id!, { email: "a@b.co", score: 10 });

// Data-plane invocation (what the gateway proxies /v1/fn/{key} to):
const out = await client.invokeFunction(base.schema!, fn.functionKey!, { email: "a@b.co" });
```

Also: `listFunctions`, `getFunction`, `updateFunction` (body changes snapshot a version), `deleteFunction`, `listFunctionVersions`.

## Transactions & events

```ts
// Ordered ops in ONE database transaction — all succeed or none apply (internal bases only):
const { results } = await client.executeTransaction(base.schema!, [
  { type: "create", table: "orders", record: { total: 120 } },
  { type: "update", table: "inventory", id: "9", record: { qty: 3 } },
]);

// Publish a data event on the platform bus:
await client.publishEvent(base.schema!, { eventType: "order.placed", record: { id: "o1" } });
```

## Options

All requests go to `https://api.lowco.ai` unless `baseUrl` overrides it.

| Option           | Description                                                            |
| ---------------- | ---------------------------------------------------------------------- |
| `token`          | User token or API key sent as `Authorization: Bearer <token>`. Required. |
| `orgId`          | Sets `X-Org-Id`.                                                       |
| `baseUrl`        | Manager origin (default `https://api.lowco.ai`); set for in-cluster or local use. |
| `defaultHeaders` | Extra headers added to every request.                                  |
| `apiBasePath`    | Overrides `/v1/lowcodb` (useful behind reverse proxies).               |
| `fetch`          | Custom fetch implementation (defaults to global `fetch`).              |
| `timeoutMs`      | Per-request timeout (default 30 000; `0` disables).                    |

You can also mutate identity at runtime: `client.setOrgId(...)`, `client.setHeader(k, v)`.

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
- **DB functions** — `listFunctions`, `getFunction`, `createFunction`, `updateFunction`, `deleteFunction`, `listFunctionVersions`, `executeFunction`, `invokeFunction`
- **Transactions** — `executeTransaction`
- **Events** — `publishEvent`
- **Query** — `executeQuery`, `getQuerySuggestions`
- **Dashboards** — `getOverviewCounts`, `getMetricsDashboard`, `getDashboardOverview`
- **Health** — `health`

See [../../docs/lowcodb.md](../../docs/lowcodb.md) for the REST surface.
