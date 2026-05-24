# agentx

Go client for the agentx backend, covering the **agent-manager**, **agent-kb**
(knowledge-base) and **agent-executor** services in a single package.

```bash
go get github.com/backend-platform/lowco-sdk/go/agentx
```

One `Client`, three sub-clients:

```go
import (
    "context"

    "github.com/backend-platform/lowco-sdk/go/agentx"
)

ctx := context.Background()
client, err := agentx.NewClient("http://localhost:8080",
    agentx.WithOrgID("org_123"),
    agentx.WithUserID("user_123"),
)
if err != nil {
    panic(err)
}

agents, _ := client.Manager.ListAgents(ctx, &agentx.ListParams{PageNo: 1, Size: 25})
kbs,    _ := client.KB.ListKnowledgeBases(ctx, nil)
resp,   _ := client.Executor.SendMessage(ctx, "agent_abc", agentx.MessageSendParams{
    Message: agentx.A2AMessage{
        Role:      agentx.MessageRoleUser,
        MessageID: "msg_001",
        Kind:      "message",
        Parts:     []agentx.Part{agentx.TextPart{Kind: agentx.PartKindText, Text: "Hello!"}},
    },
    ChatType: "chat",
})
```

## Split deployments

When the three services are on different hosts, omit `baseURL` and pass
per-service URLs instead:

```go
client, _ := agentx.NewClient("",
    agentx.WithManagerURL("http://manager.internal:8080"),
    agentx.WithKBURL("http://kb.internal:8080"),
    agentx.WithExecutorURL("http://executor.internal:8080"),
    agentx.WithOrgID("org_123"),
)
```

Any combination works – a global `baseURL` plus selective overrides is fine.

## Streaming the executor

```go
err := client.Executor.StreamMessage(ctx, "agent_abc", params, func(ev agentx.StreamEvent) error {
    msg, err := ev.Message()
    if err != nil {
        // non-Message frame – inspect ev.Data directly
        return nil
    }
    fmt.Printf("delta: %+v\n", msg)
    return nil
})
```

Return a non-nil error from the handler to abort the stream early. For
long-running streams, pass `agentx.WithHTTPClient(&http.Client{})` so the
default 30s `Timeout` doesn't truncate the connection.

## Options

| Option                              | Description                                              |
| ----------------------------------- | -------------------------------------------------------- |
| `WithOrgID(id)`                     | Sets `X-Org-Id`.                                         |
| `WithUserID(id)`                    | Sets `X-User-Id`.                                        |
| `WithDefaultHeader(k, v)`           | Adds an arbitrary header to every request.               |
| `WithManagerURL(u)` / `WithKBURL(u)` / `WithExecutorURL(u)` | Per-service base URL override.       |
| `WithManagerAPIBasePath(p)` / `WithKBAPIBasePath(p)` / `WithExecutorAPIBasePath(p)` | Override the route prefix per service. |
| `WithHTTPClient(c)`                 | Provides a custom `*http.Client` (default: 30s timeout). |

Identity can also be mutated at runtime via `client.SetOrgID(...)`,
`client.SetUserID(...)`, `client.SetHeader(k, v)`.

## Errors

Every HTTP-level non-2xx response returns `*agentx.RequestError`. JSON-RPC
level errors from the executor are surfaced in `JSONRPCResponse.Error`.

```go
agent, err := client.Manager.GetAgent(ctx, "missing")
if err != nil {
    var apiErr *agentx.RequestError
    if errors.As(err, &apiErr) {
        fmt.Println(apiErr.StatusCode, apiErr.Code, apiErr.Message, apiErr.Body)
    }
}

resp, err := client.Executor.SendMessage(ctx, "agent_abc", params)
if resp != nil && resp.Error != nil {
    fmt.Println(resp.Error.Code, resp.Error.Message)
}
```

## API coverage

Mirrors each service's `server.go` 1-to-1.

**`client.Manager`** — agents (`ListAgents`, `GetAgent`, `CreateAgent`,
`UpdateAgent`, `PatchAgent`, `GetAgentCount`, `DeleteAgent`,
`BulkDeleteAgents`, `GetAgentVersions`), published agents (`PublishAgent`,
`GetPublishedAgent`, `UpdatePublishedAgent`, `DeletePublishedAgent`,
`ListPublishedAgents`), LLM models (`CreateModel`, `GetModel`, `UpdateModel`,
`ListModels`, `DeleteModel`, `EnableModel`, `DisableModel`), conversations
(`ListConversationsByAgent`, `CreateConversation`, `DeleteConversation`,
`GetConversationMessages`), `Health`.

**`client.KB`** — knowledge bases (`ListKnowledgeBases`,
`CreateKnowledgeBase`, `GetKnowledgeBase`, `UpdateKnowledgeBase`,
`GetKnowledgeBaseCount`), datasets (`ListDatasets`, `CreateDataset`,
`GetDataset`, `UpdateDataset`, `DeleteDataset`, `GetDatasetCount`),
embeddings (`StoreEmbeddings`), `Health`.

**`client.Executor`** — `SendMessage`, `StreamMessage`, `Health`.
