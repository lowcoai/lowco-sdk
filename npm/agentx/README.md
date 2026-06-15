# @lowcoai/agentx

TypeScript / Node client for the agentx backend, covering the **agent-manager**, **agent-kb** (knowledge-base) and **agent-executor** services in a single package. Works in any environment that ships a global `fetch` and streaming `Response.body` (Node 18+, modern browsers, Bun, Deno).

```bash
npm install @lowcoai/agentx
```

## Quick start

```ts
import { AgentxClient } from "@lowcoai/agentx";

const client = new AgentxClient({
  token: "<token-or-api-key>", // required
  orgId: "org_123",
});

const agents = await client.Manager.listAgents({ pageNo: 1, size: 25 });
const kbs = await client.KB.listKnowledgeBases();

const resp = await client.Executor.sendMessage("agent_abc", {
  message: {
    role: "user",
    messageId: "msg_001",
    kind: "message",
    parts: [{ kind: "text", text: "Hello!" }],
  },
  chatType: "chat",
});

if (resp.error) console.error("rpc error", resp.error);
else console.log("result", resp.result);
```

## Streaming the executor

```ts
import { tryParseMessage } from "@lowcoai/agentx";

const ac = new AbortController();
for await (const ev of client.Executor.streamMessage("agent_abc", params, { signal: ac.signal })) {
  const msg = tryParseMessage(ev);
  if (msg) console.log("delta:", msg);
  else console.log("raw:", ev.data);
}
```

Call `ac.abort()` to stop the stream early.

## Options

All requests go to `https://api.lowco.ai`.

| Option                   | Description                                                            |
| ------------------------ | ---------------------------------------------------------------------- |
| `token`                  | User token or API key sent as `Authorization: Bearer <token>`. Required. |
| `managerApiBasePath` / `kbApiBasePath` / `executorApiBasePath` | Route prefix per service (defaults `/v1/agentx/manager`, `/v1/agentx/kb`, `/v1/agentx/executors`). |
| `orgId`                  | Sets `X-Org-Id`.                                                       |
| `defaultHeaders`         | Extra headers added to every request.                                  |
| `fetch`                  | Custom fetch implementation (defaults to global `fetch`).              |
| `timeoutMs`              | Per-request timeout for non-streaming calls (default 30 000; `0` disables). |

Identity can also be mutated at runtime via `client.setOrgId(...)`, `client.setHeader(k, v)`.

## Errors

HTTP-level non-2xx responses throw `AgentxError`. JSON-RPC level errors from the executor are surfaced inside the `error` field of `JSONRPCResponse`.

```ts
import { AgentxError } from "@lowcoai/agentx";

try {
  await client.Manager.getAgent("missing");
} catch (err) {
  if (err instanceof AgentxError) {
    console.error(err.statusCode, err.code, err.message, err.body);
  }
}
```

## API coverage

Mirrors each service's `server.go` 1-to-1.

**`client.Manager`** — agents (`listAgents`, `getAgent`, `createAgent`, `updateAgent`, `patchAgent`, `getAgentCount`, `deleteAgent`, `bulkDeleteAgents`, `getAgentVersions`), published agents (`publishAgent`, `getPublishedAgent`, `updatePublishedAgent`, `deletePublishedAgent`, `listPublishedAgents`), LLM models (`createModel`, `getModel`, `updateModel`, `listModels`, `deleteModel`, `enableModel`, `disableModel`), conversations (`listConversationsByAgent`, `createConversation`, `deleteConversation`, `getConversationMessages`), `health`.

**`client.KB`** — knowledge bases (`listKnowledgeBases`, `createKnowledgeBase`, `getKnowledgeBase`, `updateKnowledgeBase`, `getKnowledgeBaseCount`), datasets (`listDatasets`, `createDataset`, `getDataset`, `updateDataset`, `deleteDataset`, `getDatasetCount`), embeddings (`storeEmbeddings`), `health`.

**`client.Executor`** — `sendMessage`, `streamMessage`, `health`.
