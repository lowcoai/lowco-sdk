# lowco-sdk

Official client SDKs for the [lowco](https://github.com/backend-platform) backend-platform services.

The repository is a **multi-module monorepo**: one folder per ecosystem (Go / npm / …), and one sub-folder per backend product.

```
lowco-sdk/
├── go/
│   ├── lowcodb/      ← github.com/backend-platform/lowco-sdk/go/lowcodb
│   └── agentx/       ← github.com/backend-platform/lowco-sdk/go/agentx
├── npm/
│   ├── lowcodb/      ← @lowcoai/lowcodb
│   └── agentx/       ← @lowcoai/agentx
└── docs/
    └── lowcodb.md    ← REST surface reference (language-agnostic)
```

`agentx` is a single SDK covering three services – **agent-manager**, **agent-kb** and **agent-executor** – exposed as `client.Manager`, `client.KB` and `client.Executor` sub-clients sharing one HTTP transport.

Each module is independent — you can `go get` or `npm install` a single product without pulling the others.

---

## Products

| Product   | Services covered                              | Go module                                          | npm package        | Docs                                       |
| --------- | --------------------------------------------- | -------------------------------------------------- | ------------------ | ------------------------------------------ |
| `lowcodb` | lowcodb manager                               | `github.com/backend-platform/lowco-sdk/go/lowcodb` | `@lowcoai/lowcodb` | [docs/lowcodb.md](docs/lowcodb.md)         |
| `agentx`  | agent-manager · agent-kb · agent-executor     | `github.com/backend-platform/lowco-sdk/go/agentx`  | `@lowcoai/agentx`  | [go/agentx/README.md](go/agentx/README.md) |

> Future products will follow the same `go/<product>` + `npm/<product>` pattern.

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

```bash
go get github.com/backend-platform/lowco-sdk/go/agentx
```

```go
import "github.com/backend-platform/lowco-sdk/go/agentx"

client, _ := agentx.NewClient("http://localhost:8080",
    agentx.WithOrgID("org_123"),
    agentx.WithUserID("user_123"),
)
agents, _ := client.Manager.ListAgents(ctx, nil)
kbs,    _ := client.KB.ListKnowledgeBases(ctx, nil)
resp,   _ := client.Executor.SendMessage(ctx, "agent_abc", params)
```

See [go/agentx/README.md](go/agentx/README.md).

### npm

```bash
npm install @lowcoai/lowcodb
```

```ts
import { LowcodbClient } from "@lowcoai/lowcodb";

const client = new LowcodbClient({
  baseURL: "http://localhost:8080",
  orgId: "org_123",
  userId: "user_123",
});

const bases = await client.listBases();
```

See [npm/lowcodb/README.md](npm/lowcodb/README.md).

```bash
npm install @lowcoai/agentx
```

```ts
import { AgentxClient } from "@lowcoai/agentx";

const client = new AgentxClient({
  baseURL: "http://localhost:8080",
  orgId: "org_123",
  userId: "user_123",
});

const agents = await client.Manager.listAgents();
const kbs = await client.KB.listKnowledgeBases();
const resp = await client.Executor.sendMessage("agent_abc", params);
```

See [npm/agentx/README.md](npm/agentx/README.md).

---

## Adding a new product to this SDK

1. Create `go/<product>/` with its own `go.mod` (module path `github.com/backend-platform/lowco-sdk/go/<product>`).
2. Create `npm/<product>/` with its own `package.json` (name `@lowcoai/<product>`).
3. Add a `docs/<product>.md` REST reference (or link to the package README).
4. Register it in the table above.

Per-product modules keep dependency surface area small and let consumers upgrade products independently.

---

## Repository conventions

- Every SDK uses **headers** for tenancy (`X-Org-Id`, `X-User-Id`) — never query params.
- Every SDK speaks the service's enveloped JSON response shape (`{ success, data, error, message }`) and unwraps `data` for the caller.
- Errors surface as a typed exception (`*RequestError` / `*Error` class) with `statusCode`, `message`, `code`, and the raw body for debugging.
- Method names mirror the controller verbs in the corresponding service so the SDKs and server stay in lockstep.

NPM packages — `@lowcoai/lowcodb`, `@lowcoai/agentx`.
