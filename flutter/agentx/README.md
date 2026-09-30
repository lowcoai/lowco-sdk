# lowcoai_agentx

Dart / Flutter client for the **agentx** services: the agent manager, knowledge bases and the A2A agent executor (synchronous and SSE-streamed). Pure Dart on top of [`package:http`](https://pub.dev/packages/http), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM.

```yaml
dependencies:
  lowcoai_agentx: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_agentx/lowcoai_agentx.dart';

final client = AgentxClient(token: '<token-or-api-key>', orgId: 'org_123');

final agents = await client.manager.listAgents(const ListParams(size: 20));
final total = await client.manager.getAgentCount();

const params = MessageSendParams(
  message: A2AMessage(role: 'user', parts: [TextPart(text: 'Hello!')], messageId: 'msg-1'),
);

// Synchronous JSON-RPC call.
final resp = await client.executor.sendMessage(agents.first.id!, params);
final reply = A2AMessage.fromJson(resp.result as Map<String, dynamic>);

// Server-sent events, one StreamEvent per event.
await for (final ev in client.executor.streamMessage(agents.first.id!, params)) {
  final msg = tryParseMessage(ev); // null when the payload is not a JSON object
  print(msg?.parts ?? ev.data);
}

client.close();
```

## Options

| Parameter             | Description                                                                          |
| --------------------- | ------------------------------------------------------------------------------------ |
| `token`               | User token or API key, sent as `Authorization: Bearer <token>`. Required.            |
| `orgId`               | Sent as the `X-Org-Id` header.                                                       |
| `managerApiBasePath`  | Agent-manager route prefix, default `/v1/agentx/manager`.                            |
| `kbApiBasePath`       | Agent-kb route prefix, default `/v1/agentx/kb`.                                      |
| `executorApiBasePath` | Agent-executor route prefix, default `/v1/agentx/executors`.                         |
| `defaultHeaders`      | Extra headers added to every request.                                                |
| `timeout`             | Per-request timeout for non-streaming calls (default 30 s); `null` disables it. A timed-out request is aborted and throws `TimeoutException`. `streamMessage` never times out. |
| `httpClient`          | Your own `http.Client` (e.g. `cupertino_http` / `cronet_http` in Flutter, or `MockClient` in tests). Not closed by `close()`. |

All requests go to `https://api.lowco.ai`. The three sub-clients share one transport and one header map: `client.setOrgId(...)` and `client.setHeader(key, value)` change headers for later requests of all of them; pass `null` to remove.

## Data shapes

Entities are immutable model classes (`Agent`, `LlmModel`, `Conversation`, `KnowledgeBase`, `Dataset`, …) with `fromJson` / `toJson`. Field names match the wire; `toJson` omits null fields, so an update only sends what you set. Timestamps are ISO-8601 strings, as sent by the server. `MessageContent` (conversation message content) is either a `String` or a list of block maps and is passed through untouched.

List (and count) methods take an optional `ListParams(pageNo:, size:, filter:, sort:)`. The count endpoints return a plain `int`.

Executor types follow the A2A protocol:

- `Part` is a sealed class: `TextPart`, `FilePart` (with a sealed `FilePayload`: `FileWithBytes` or `FileWithURI`) and `DataPart`, chosen by `kind`. Anything else — a new kind, or a known kind with a missing payload — decodes as `UnknownPart`, which keeps the raw map, so decoding never throws. Use an exhaustive `switch` over the parts.
- `A2AMessage`, `MessageSendParams`, `MessageSendConfiguration`, `PushNotificationConfig`.
- `JSONRPCRequest`, `JSONRPCResponse` (`result` is raw JSON, `error` a `JSONRPCError`), plus `JSONRPCErrorCodes` and `A2AErrorCodes`.

## Surface

| Sub-client | Area             | Methods |
| ---------- | ---------------- | ------- |
| `manager`  | Health           | `health` |
|            | Agents           | `listAgents`, `getAgent`, `createAgent`, `updateAgent`, `patchAgent`, `getAgentCount` (int), `deleteAgent`, `bulkDeleteAgents`, `getAgentVersions` |
|            | Published agents | `publishAgent`, `getPublishedAgent`, `updatePublishedAgent`, `deletePublishedAgent`, `listPublishedAgents` |
|            | LLM models       | `createModel`, `getModel`, `updateModel`, `listModels`, `deleteModel`, `enableModel`, `disableModel` |
|            | Conversations    | `listConversationsByAgent`, `createConversation`, `deleteConversation`, `getConversationMessages` |
| `kb`       | Health           | `health` |
|            | Knowledge bases  | `listKnowledgeBases`, `createKnowledgeBase`, `getKnowledgeBase`, `updateKnowledgeBase`, `getKnowledgeBaseCount` (int) |
|            | Datasets         | `listDatasets`, `createDataset`, `getDataset`, `updateDataset`, `deleteDataset`, `getDatasetCount` (int) |
|            | Embeddings       | `storeEmbeddings` (returns the service's message) |
| `executor` | Health           | `health` |
|            | Messages         | `sendMessage` (`JSONRPCResponse`), `streamMessage` (`Stream<StreamEvent>`) |

### Streaming

`streamMessage` posts the same JSON-RPC `message/send` request as `sendMessage` with `Accept: text/event-stream`. The request is sent when you listen. Each `StreamEvent.data` is the payload of one server-sent event (multi-line `data:` fields joined with `\n`; comments, `event:`/`id:`/`retry:` fields and data-less heartbeats are skipped). Cancelling the subscription — `break` in an `await for`, `stream.first`, `subscription.cancel()` — aborts the HTTP request. A non-2xx reply arrives as an `AgentxException` stream error.

```dart
final sub = client.executor.streamMessage(agentId, params).listen(
  (ev) => print(ev.data),
  onError: (Object e) => print('stream failed: $e'),
);
// Later, e.g. when the user taps "stop":
await sub.cancel();
```

## Errors

Every non-2xx response throws `AgentxException` with `statusCode`, `message`, `code` and the raw `body`:

```dart
try {
  await client.manager.getAgent('missing');
} on AgentxException catch (e) {
  print('${e.statusCode} ${e.code} ${e.message}');
}
```

`message` and `code` come from the `{ error: { code, message } }` envelope when present, else from a top-level `message`, else the raw response text. JSON-RPC errors from the executor are not thrown: they are returned in `JSONRPCResponse.error`.
