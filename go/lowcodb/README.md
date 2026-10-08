# lowcodb — Go SDK

Go client for the lowcodb manager service.

Every request is sent to the fixed host `https://api.lowco.ai` (`lowcodb.DefaultBaseURL`). `NewClient` requires a token (a user token or an API key) that is sent as `Authorization: Bearer <token>` on every request.

```
go get github.com/lowcoai/lowco-sdk/go/lowcodb
```

## Quick start

```go
package main

import (
    "context"
    "fmt"
    "log"

    lowcodb "github.com/lowcoai/lowco-sdk/go/lowcodb"
)

func main() {
    client, err := lowcodb.NewClient("<token-or-api-key>",
        lowcodb.WithOrgID("org_123"),
    )
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // 1. Create a base (schema/database)
    base, err := client.CreateBase(ctx, lowcodb.Base{
        Name:     "Sales",
        BaseType: lowcodb.BaseTypeInternal,
    })
    if err != nil { log.Fatal(err) }

    // 2. Define a table
    table, err := client.CreateTable(ctx, lowcodb.Table{
        BaseID: base.ID,
        Name:   "leads",
    })
    if err != nil { log.Fatal(err) }

    // 3. Add columns
    _, err = client.BulkCreateColumns(ctx, table.ID, []lowcodb.Column{
        {Name: "email", DataType: "string"},
        {Name: "score", DataType: "int"},
    })
    if err != nil { log.Fatal(err) }

    // 4. Insert a record (use the base's Schema as the path segment)
    rec, err := client.CreateRecord(ctx, base.Schema, table.Name, lowcodb.Record{
        "email": "alice@example.com",
        "score": 87,
    })
    if err != nil { log.Fatal(err) }
    fmt.Println("created", (*rec)["id"])

    // 5. Paginated list
    rows, err := client.ListRecords(ctx, base.Schema, table.Name, &lowcodb.ListParams{
        PageNo: 1,
        Size:   25,
        Filter: `score > 50`,
        Sort:   `-createdAt`,
    })
    if err != nil { log.Fatal(err) }
    fmt.Println("rows:", len(rows))
}
```

## Options

| Option | Description |
| ------ | ----------- |
| `WithOrgID(id)` | Sets `X-Org-Id`. |
| `WithDefaultHeader(k, v)` | Adds an arbitrary header. |
| `WithHTTPClient(c)` | Replaces the default `http.Client` (30 s timeout). |
| `WithAPIBasePath(p)` | Overrides `/v1/lowcodb` (useful behind reverse proxies). |

Headers can also be changed at runtime: `client.SetOrgID(...)`.

## Errors

All non-2xx responses are returned as `*lowcodb.RequestError`:

```go
if _, err := client.GetBase(ctx, "missing"); err != nil {
    var apiErr *lowcodb.RequestError
    if errors.As(err, &apiErr) {
        switch apiErr.StatusCode {
        case 404: // not found
        case 400: // validation
        }
    }
}
```

## API coverage

The SDK mirrors `lowcodb/manager/server/server.go` 1-to-1:

- **Bases** — `GetBase`, `CreateBase`, `UpdateBase`, `DeleteBase`, `ListBases`, `ExportBaseCollection`, `SyncBaseTables`
- **Tables** — `GetTable`, `CreateTable`, `UpdateTable`, `DeleteTable`, `ListTables`
- **Columns** — `GetColumn`, `CreateColumn`, `BulkCreateColumns`, `UpdateColumn`, `BulkUpdateColumns`, `DeleteColumn`, `ListColumns`, `ValidateField`
- **Indexes** — `GetTableIndex`, `CreateTableIndex`, `UpdateTableIndex`, `ListTableIndexes`, `DeleteTableIndex`
- **Records** — `CreateRecord`, `GetRecord`, `UpdateRecord`, `DeleteRecord`, `ListRecords`, `CountRecords`, `CreateBulkRecords`, `UpdateBulkRecords`, `DeleteBulkRecords`
- **Views (data)** — `GetViewRecord`, `ListViewRecords`, `CountViewRecords`
- **Views (metadata)** — `ListViews`, `CreateView`, `GetView`, `UpdateView`, `DeleteView`, `RefreshView`
- **Triggers** — `GetTrigger`, `CreateTrigger`, `UpdateTrigger`, `DeleteTrigger`, `ListTriggers`
- **Webhooks** — `GetWebhook`, `CreateWebhook`, `UpdateWebhook`, `DeleteWebhook`, `ListWebhooks`
- **Query** — `ExecuteQuery`, `GetQuerySuggestions`
- **Dashboards** — `GetOverviewCounts`, `GetMetricsDashboard`, `GetDashboardOverview`
- **Health** — `Health`

See [../../docs/lowcodb.md](../../docs/lowcodb.md) for the REST surface.
