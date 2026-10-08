# lowco-sdk

Official client SDKs for the [lowco](https://lowco.ai) platform services.

The repository is a **multi-module monorepo**: one folder per ecosystem (Go / npm / Python / Flutter), and one sub-folder per backend product.

```
lowco-sdk/
├── go/
│   ├── lowcodb/        ← github.com/lowcoai/lowco-sdk/go/lowcodb
│   ├── agentx/         ← github.com/lowcoai/lowco-sdk/go/agentx
│   ├── workflow/       ← github.com/lowcoai/lowco-sdk/go/workflow
│   ├── integrations/   ← github.com/lowcoai/lowco-sdk/go/integrations
│   └── flux/           ← github.com/lowcoai/lowco-sdk/go/flux
├── npm/
│   ├── lowcodb/        ← @lowcoai/lowcodb
│   ├── agentx/         ← @lowcoai/agentx
│   ├── workflow/       ← @lowcoai/workflow
│   ├── integrations/   ← @lowcoai/integrations
│   ├── flux/           ← @lowcoai/flux
│   ├── auth/           ← @lowcoai/auth      (React)
│   └── engage/         ← @lowcoai/engage    (browser)
├── python/
│   ├── lowcodb/        ← lowcoai-lowcodb       (import lowcoai.lowcodb)
│   ├── agentx/         ← lowcoai-agentx        (import lowcoai.agentx)
│   ├── workflow/       ← lowcoai-workflow      (import lowcoai.workflow)
│   ├── integrations/   ← lowcoai-integrations  (import lowcoai.integrations)
│   ├── flux/           ← lowcoai-flux          (import lowcoai.flux, asyncio)
│   ├── auth/           ← lowcoai-auth          (import lowcoai.auth)
│   └── engage/         ← lowcoai-engage        (import lowcoai.engage)
├── flutter/
│   ├── lowcodb/        ← lowcoai_lowcodb       (pure Dart)
│   ├── agentx/         ← lowcoai_agentx        (pure Dart)
│   ├── workflow/       ← lowcoai_workflow      (pure Dart)
│   ├── integrations/   ← lowcoai_integrations  (pure Dart)
│   ├── flux/           ← lowcoai_flux          (pure Dart)
│   ├── auth/           ← lowcoai_auth          (Flutter)
│   └── engage/         ← lowcoai_engage        (Flutter)
└── docs/
    ├── lowcodb.md       ← REST surface reference (language-agnostic)
    ├── workflow.md      ← REST surface reference (language-agnostic)
    └── integrations.md  ← REST surface reference (language-agnostic)
```

`agentx` is a single SDK covering three services – **agent-manager**, **agent-kb** and **agent-executor** – exposed as `client.Manager`, `client.KB` and `client.Executor` sub-clients (`client.manager` / `client.kb` / `client.executor` in Python and Dart) sharing one HTTP transport.

Each module is independent — you can `go get`, `npm install`, `pip install` or `dart pub add` a single product without pulling the others. The Python packages share the `lowcoai` namespace package, mirroring the `@lowcoai/` npm scope.

The Dart API clients are pure Dart (`package:http` / `web_socket_channel`), so they run in Flutter on iOS, Android, web and desktop as well as on the Dart VM. `lowcoai_auth` and `lowcoai_engage` are Flutter packages: auth drives the system browser and stores tokens in secure storage, engage persists device and session ids.

---

## Products

| Product        | Services covered                          | Go module                                               | npm package             | PyPI package           | pub.dev package        | Docs                                         |
| -------------- | ----------------------------------------- | ------------------------------------------------------- | ----------------------- | ---------------------- | ---------------------- | -------------------------------------------- |
| `lowcodb`      | lowcodb manager                           | `github.com/lowcoai/lowco-sdk/go/lowcodb`      | `@lowcoai/lowcodb`      | `lowcoai-lowcodb`      | `lowcoai_lowcodb`      | [docs/lowcodb.md](docs/lowcodb.md)           |
| `agentx`       | agent-manager · agent-kb · agent-executor | `github.com/lowcoai/lowco-sdk/go/agentx`       | `@lowcoai/agentx`       | `lowcoai-agentx`       | `lowcoai_agentx`       | [go/agentx/README.md](go/agentx/README.md)   |
| `workflow`     | workflow-orchestrator                     | `github.com/lowcoai/lowco-sdk/go/workflow`     | `@lowcoai/workflow`     | `lowcoai-workflow`     | `lowcoai_workflow`     | [docs/workflow.md](docs/workflow.md)         |
| `integrations` | integrations-manager                      | `github.com/lowcoai/lowco-sdk/go/integrations` | `@lowcoai/integrations` | `lowcoai-integrations` | `lowcoai_integrations` | [docs/integrations.md](docs/integrations.md) |
| `flux`         | flux realtime WebSocket                   | `github.com/lowcoai/lowco-sdk/go/flux`         | `@lowcoai/flux`         | `lowcoai-flux`         | `lowcoai_flux`         | [npm/flux/README.md](npm/flux/README.md)     |
| `auth`         | lowco OAuth (Authorization Code + PKCE)   | —                                                       | `@lowcoai/auth`         | `lowcoai-auth`         | `lowcoai_auth`         | [npm/auth/README.md](npm/auth/README.md)     |
| `engage`       | engage event tracking                     | —                                                       | `@lowcoai/engage`       | `lowcoai-engage`       | `lowcoai_engage`       | [npm/engage/README.md](npm/engage/README.md) |

Every package has its own README with the full surface (`python/<product>/README.md`, `flutter/<product>/README.md`).

> Future products will follow the same `go/<product>` + `npm/<product>` + `python/<product>` + `flutter/<product>` pattern.

---

## Quick start

### Go

```bash
go get github.com/lowcoai/lowco-sdk/go/lowcodb
```

```go
import lowcodb "github.com/lowcoai/lowco-sdk/go/lowcodb"

client, _ := lowcodb.NewClient("<token-or-api-key>",
    lowcodb.WithOrgID("org_123"),
)
bases, _ := client.ListBases(ctx, nil)
```

See [go/lowcodb/README.md](go/lowcodb/README.md).

```bash
go get github.com/lowcoai/lowco-sdk/go/agentx
```

```go
import "github.com/lowcoai/lowco-sdk/go/agentx"

client, _ := agentx.NewClient("<token-or-api-key>",
    agentx.WithOrgID("org_123"),
)
agents, _ := client.Manager.ListAgents(ctx, nil)
kbs,    _ := client.KB.ListKnowledgeBases(ctx, nil)
resp,   _ := client.Executor.SendMessage(ctx, "agent_abc", params)
```

See [go/agentx/README.md](go/agentx/README.md).

```bash
go get github.com/lowcoai/lowco-sdk/go/workflow
```

```go
import "github.com/lowcoai/lowco-sdk/go/workflow"

client, _ := workflow.NewClient(workflow.Config{
    Token: "<token-or-api-key>",
    OrgID: "org_123",
})
workflows, _ := client.Workflows.List(ctx, nil)
```

See [go/workflow/README.md](go/workflow/README.md).

```bash
go get github.com/lowcoai/lowco-sdk/go/integrations
```

```go
import "github.com/lowcoai/lowco-sdk/go/integrations"

client, _ := integrations.NewClient(integrations.Config{
    Token: "<token-or-api-key>",
    OrgID: "org_123",
})
apps, _ := client.Applications.List(ctx, nil)
result, _ := client.Actions.Run(ctx, "action_123", integrations.RunActionRequest{
    CredentialID: "conn_456",
    InputBody:    map[string]any{"to": "alice@example.com"},
})
```

See [go/integrations/README.md](go/integrations/README.md).

### npm

```bash
npm install @lowcoai/lowcodb
```

```ts
import { LowcodbClient } from "@lowcoai/lowcodb";

const client = new LowcodbClient({
  token: "<token-or-api-key>",
  orgId: "org_123",
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
  token: "<token-or-api-key>",
  orgId: "org_123",
});

const agents = await client.Manager.listAgents();
const kbs = await client.KB.listKnowledgeBases();
const resp = await client.Executor.sendMessage("agent_abc", params);
```

See [npm/agentx/README.md](npm/agentx/README.md).

```bash
npm install @lowcoai/workflow
```

```ts
import { WorkflowClient } from "@lowcoai/workflow";

const client = new WorkflowClient({
  token: "<token-or-api-key>",
  orgId: "org_123",
});

const workflows = await client.workflows.list();
```

See [npm/workflow/README.md](npm/workflow/README.md).

```bash
npm install @lowcoai/integrations
```

```ts
import { IntegrationsClient } from "@lowcoai/integrations";

const client = new IntegrationsClient({
  token: "<token-or-api-key>",
  orgId: "org_123",
});

const apps = await client.applications.list();
const result = await client.actions.run("action_123", {
  credentialId: "conn_456",
  inputBody: { to: "alice@example.com" },
});
```

See [npm/integrations/README.md](npm/integrations/README.md).

### Python

Python 3.10+. Every HTTP product ships a sync client and an asyncio twin (`LowcodbClient` / `AsyncLowcodbClient`, …) with the same methods, built on httpx.

```bash
pip install lowcoai-lowcodb
```

```python
from lowcoai.lowcodb import LowcodbClient

with LowcodbClient("<token-or-api-key>", org_id="org_123") as client:
    bases = client.list_bases()
    rows = client.list_records("app_crm", "leads", filter="status='open'", size=50)
```

```python
from lowcoai.agentx import AsyncAgentxClient

async with AsyncAgentxClient("<token-or-api-key>", org_id="org_123") as client:
    agents = await client.manager.list_agents()
    async for event in client.executor.stream_message("agent_abc", params):
        print(event.data)
```

```python
from lowcoai.workflow import WorkflowClient
from lowcoai.integrations import IntegrationsClient

workflows = WorkflowClient("<token-or-api-key>", org_id="org_123").workflows.list()
apps = IntegrationsClient("<token-or-api-key>", org_id="org_123").applications.list()
```

```python
from lowcoai.flux import FluxClient

async with FluxClient("<token-or-api-key>", "org_123") as flux:
    channel = await flux.subscribe("channel:<schema>", events=["messages.*"])
    channel.bind("messages.insert", lambda data, msg: print(data))
```

`lowcoai-auth` (PKCE authorize URL, code exchange, refresh) and `lowcoai-engage` (server-side event tracking) are the server-side counterparts of the browser packages. See `python/<product>/README.md`.

### Dart / Flutter

```bash
dart pub add lowcoai_lowcodb   # or: flutter pub add lowcoai_lowcodb
```

```dart
import 'package:lowcoai_lowcodb/lowcoai_lowcodb.dart';

final client = LowcodbClient(token: '<token-or-api-key>', orgId: 'org_123');
final bases = await client.listBases();
final rows = await client.listRecords('app_crm', 'leads', const ListParams(size: 50));
```

```dart
import 'package:lowcoai_agentx/lowcoai_agentx.dart';

final agentx = AgentxClient(token: '<token-or-api-key>', orgId: 'org_123');
final agents = await agentx.manager.listAgents();
await for (final event in agentx.executor.streamMessage('agent_abc', params)) {
  print(tryParseMessage(event));
}
```

```dart
import 'package:lowcoai_flux/lowcoai_flux.dart';

final flux = FluxClient(token: '<token-or-api-key>', orgId: 'org_123')..connect();
flux.subscribe('channel:<schema>', events: ['messages.*']).bind('messages.insert', (data, msg) => print(data));
```

In Flutter apps, `lowcoai_auth` provides `LowcoAuth` (a `ChangeNotifier`), `LowcoAuthProvider` and `WithAuthenticationRequired` for the lowco PKCE login. `lowcoai_engage` provides `LowcoAnalytics.instance` and a `LowcoAnalyticsObserver` for automatic screen views. See `flutter/<product>/README.md`.

---

## Adding a new product to this SDK

1. Create `go/<product>/` with its own `go.mod` (module path `github.com/lowcoai/lowco-sdk/go/<product>`).
2. Create `npm/<product>/` with its own `package.json` (name `@lowcoai/<product>`).
3. Create `python/<product>/` with its own `pyproject.toml` (distribution `lowcoai-<product>`, package `src/lowcoai/<product>/` — no `src/lowcoai/__init__.py`, it is a namespace package) and matching sync + async clients.
4. Create `flutter/<product>/` with its own `pubspec.yaml` (name `lowcoai_<product>`), pure Dart unless it needs Flutter plugins.
5. Add a `docs/<product>.md` REST reference (or link to the package README).
6. Register it in the table above.

Per-product modules keep dependency surface area small and let consumers upgrade products independently. `python/lowcodb` and `flutter/lowcodb` are the reference layouts to copy.

---

## Development

Each package is self-contained; run its checks from its own folder.

| Ecosystem | Checks |
| --------- | ------ |
| Go        | `go vet ./... && go test ./...` |
| npm       | `npm install && npm run typecheck && npm run build` |
| Python    | `pip install -e ".[dev]"`, then `pytest`, `ruff check .`, `ruff format --check .`, `mypy src tests` |
| Dart      | `dart pub get && dart format --set-exit-if-changed . && dart analyze && dart test` |
| Flutter   | `flutter pub get && dart format --set-exit-if-changed . && flutter analyze && flutter test` (`flutter/auth`, `flutter/engage`) |

---

## Repository conventions

- Every SDK targets the fixed API host `https://api.lowco.ai` (`wss://ws.lowco.ai/` for flux) — base URLs are not configurable.
- Every SDK authenticates with a required user token or API key sent as `Authorization: Bearer <value>`; user identity is derived from the token, so there is no `X-User-Id` header.
- Org scoping uses the `X-Org-Id` header — never query params.
- Every SDK speaks the service's enveloped JSON response shape (`{ success, data, error, message }`) and unwraps `data` for the caller.
- Errors surface as a typed exception (`*RequestError` / `*Error` class; `…Exception` in Dart) with `statusCode`, `message`, `code`, and the raw body for debugging.
- Method names mirror the controller verbs in the corresponding service so the SDKs and server stay in lockstep (snake_case in Python, lowerCamelCase in Dart).
- Wire payloads keep the server's field names in every language: TypedDicts with camelCase keys in Python, model classes with `fromJson` / `toJson` (nulls omitted) in Dart.

NPM packages — `@lowcoai/lowcodb`, `@lowcoai/agentx`, `@lowcoai/workflow`, `@lowcoai/integrations`, `@lowcoai/flux`, `@lowcoai/auth`, `@lowcoai/engage`.

PyPI packages — `lowcoai-lowcodb`, `lowcoai-agentx`, `lowcoai-workflow`, `lowcoai-integrations`, `lowcoai-flux`, `lowcoai-auth`, `lowcoai-engage`.

pub.dev packages — `lowcoai_lowcodb`, `lowcoai_agentx`, `lowcoai_workflow`, `lowcoai_integrations`, `lowcoai_flux`, `lowcoai_auth`, `lowcoai_engage`.
