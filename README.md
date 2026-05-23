# lowco-sdk

Official client SDKs for the [lowco](https://github.com/backend-platform) backend-platform services.

The repository is a **multi-module monorepo**: one folder per ecosystem (Go / npm / …), and one sub-folder per backend product (currently `lowcodb`; more products will land here over time).

```
lowco-sdk/
├── go/
│   └── lowcodb/      ← github.com/backend-platform/lowco-sdk/go/lowcodb
├── npm/
│   └── lowcodb/      ← @backend-platform/lowco-sdk-lowcodb
└── docs/
    └── lowcodb.md    ← REST surface reference (language-agnostic)
```

Each module is independent — you can `go get` or `npm install` a single product without pulling the others.

---

## Products

| Product   | Go module                                          | npm package                           | Docs                               |
| --------- | -------------------------------------------------- | ------------------------------------- | ---------------------------------- |
| `lowcodb` | `github.com/backend-platform/lowco-sdk/go/lowcodb` | `@backend-platform/lowco-sdk-lowcodb` | [docs/lowcodb.md](docs/lowcodb.md) |

> Future products (e.g. `lowco-events`, `lowco-workflows`) will follow the same `go/<product>` + `npm/<product>` pattern.

---

## Quick start

### Go

```bash
go get github.com/backend-platform/lowco-sdk/go/lowcodb
```

```go
import lowcodb "github.com/backend-platform/lowco-sdk/go/lowcodb"

client, _ := lowcodb.NewClient("http://localhost:8080",
    lowcodb.WithOrgID("org_123"),
    lowcodb.WithUserID("user_123"),
)
bases, _ := client.ListBases(ctx, nil)
```

See [go/lowcodb/README.md](go/lowcodb/README.md).

### npm

```bash
npm install @backend-platform/lowco-sdk-lowcodb
```

```ts
import { LowcodbClient } from "@backend-platform/lowco-sdk-lowcodb";

const client = new LowcodbClient({
  baseURL: "http://localhost:8080",
  orgId: "org_123",
  userId: "user_123",
});

const bases = await client.listBases();
```

See [npm/lowcodb/README.md](npm/lowcodb/README.md).

---

## Adding a new product to this SDK

1. Create `go/<product>/` with its own `go.mod` (module path `github.com/backend-platform/lowco-sdk/go/<product>`).
2. Create `npm/<product>/` with its own `package.json` (name `@backend-platform/lowco-sdk-<product>`).
3. Add a `docs/<product>.md` REST reference.
4. Register it in the table above.

Per-product modules keep dependency surface area small and let consumers upgrade products independently.

---

## Repository conventions

- Every SDK uses **headers** for tenancy (`X-Org-Id`, `X-User-Id`) — never query params.
- Every SDK speaks the manager's enveloped JSON response shape (`{ success, data, error, message }`) and unwraps `data` for the caller.
- Errors surface as a typed exception (`*lowcodb.RequestError` / `LowcodbError`) with `statusCode`, `message`, `code`, and the raw body for debugging.
- Method names mirror the controller verbs in `lowcodb/manager` (`GetBase`, `ListTables`, `CreateRecord`, …) so the SDKs and server stay in lockstep.

NPM package - @lowcoai/lowcodb
