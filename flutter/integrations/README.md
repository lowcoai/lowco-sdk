# lowcoai_integrations

Dart / Flutter client for the **integrations-manager** product (routes under `/v1/integrations/*`). Pure Dart on top of [`package:http`](https://pub.dev/packages/http), so it runs in Flutter (iOS, Android, web, desktop) and on the Dart VM. It mirrors the TypeScript SDK `@lowcoai/integrations`.

```yaml
dependencies:
  lowcoai_integrations: ^0.1.0
```

## Quick start

```dart
import 'package:lowcoai_integrations/lowcoai_integrations.dart';

final client = IntegrationsClient(token: '<token-or-api-key>', orgId: 'org_123');

final apps = await client.applications.list(
  const PaginationQuery(page: 1, limit: 20, tags: 'crm,sales'),
);

// Run an action
final result = await client.actions.run(
  'action_123',
  const RunActionRequest(
    credentialId: 'conn_456',
    inputBody: {'to': 'alice@example.com', 'subject': 'Hello'},
  ),
);

client.close();
```

## OAuth flow

```dart
final login = await client.oauth.login(
  'app_slack',
  const ConnectionCreateRequest(applicationId: 'app_slack', name: 'Slack — Sales workspace'),
);
// redirect the user to login.url ...

// On the redirect_uri callback:
await client.oauth.callback(CallbackRequest(state: state, code: code));
```

## Options

| Parameter    | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| `token`      | User token or API key, sent as `Authorization: Bearer <token>`. Required (`ArgumentError` if blank). Not sent when `headers` already contain `Authorization`. |
| `orgId`      | Sent as the `X-Org-Id` header, unless `headers` already contain one.                 |
| `timeout`    | Per-request timeout (default 30 s); `null` disables it. A timed-out request is aborted and throws `IntegrationsException` with status `0`. |
| `headers`    | Extra headers added to every request.                                                |
| `httpClient` | Your own `http.Client` (e.g. `cupertino_http` / `cronet_http` in Flutter, or `MockClient` in tests). Not closed by `close()`. |

Every request goes to `https://api.lowco.ai`. Responses are unwrapped from the `{ success, data, error, message }` envelope.

## Data shapes

Entities are immutable model classes named like the TS types (`Application`, `ApplicationAction`, `Connection`, `ApplicationTrigger`, `AuthToken`, `JsonRpcRequest`, …) with `fromJson` / `toJson`. Field names match the wire; fields that are required in TS are `required` here; `toJson` omits null fields. The TS string unions (`ApplicationType`, `ApplicationSubType`, `ConnectionType`, `ConnectionStatus`) are plain `String`s — the known values are documented on each field. Timestamps are ISO-8601 strings, free-form JSON is `Map<String, dynamic>` / `Object?`. `SubApplicationConfig` is `Map<String, List<String>>`.

`PostmanFolder` keeps every key it does not model (`description`, `auth`, `event`, `variable`, …) in `extra` and writes it back in `toJson`, so a Postman collection passes through `applications.loadActions` unchanged.

List methods take an optional `PaginationQuery(page:, limit:, sortBy:, sortOrder:, filter:, tags:, extra: {...})`. Anything in `extra` is sent as a query parameter too (booleans as `true`/`false`, numbers as strings, other objects as JSON; `null` is skipped).

## Surface

| Resource                | Methods |
| ----------------------- | ------- |
| `client.applications`   | `list`, `getById`, `create`, `update`, `delete`, `patchTags`, `run`, `loadActions`, `versions`, `regenerateMcpKey`, `getMcpTools`, `getSubApplications`, `getApplicationsWithTriggers` |
| `client.actions`        | `list`, `getById`, `create(applicationId, action)`, `update`, `delete`, `listByApplication`, `run`, `resolveCredentials` |
| `client.connections`    | `list`, `getById`, `create`, `update`, `delete`, `listByApplication`, `setAsDefault(id, applicationId)` |
| `client.triggers`       | `listByApplication`, `getById`, `create`, `update`, `delete`, `getState` |
| `client.oauth`          | `login`, `callback`, `getTokenByCredentialId`, `refreshTokenByCredentialId`, `refreshExpiringTokens` |
| `client.configurations` | `get` |
| `client.mcp`            | `callPublished(key, JsonRpcRequest)`, `infoPublished(key)` |

`actions.run` / `applications.run` return whatever the upstream call returned (`Object?`).

### MCP

```dart
final res = await client.mcp.callPublished(
  'mcp_key',
  const JsonRpcRequest(jsonrpc: '2.0', id: 1, method: 'tools/list'),
);
print(res.error?.message ?? res.result);
```

### Calling an endpoint the SDK does not wrap

`IntegrationsHttpClient` is the transport every resource uses (the TS SDK's `HttpClient`):

```dart
final transport = IntegrationsHttpClient(token: '<token>', orgId: 'org_123');
final data = await transport.request('GET', '/v1/integrations/applications', query: {'page': 1});
transport.close();
```

## Errors

Every failure throws `IntegrationsException` with `message`, `status` and `payload` (the TS SDK's `IntegrationsError`):

```dart
try {
  await client.actions.run('action_123', const RunActionRequest(inputBody: {}));
} on IntegrationsException catch (e) {
  print('${e.status} ${e.payload}');
}
```

- Non-2xx response: `message` is `Request failed with status <n>`, `status` the HTTP status and `payload` the decoded JSON body — or the raw text when the body is not JSON.
- Network error or timeout: `status` is `0` and `payload` is `null`.

## Using it with other lowco packages

`lowcoai_workflow` exports the same `PaginationQuery`, `BaseEntity`, `ApiEnvelope`, `JsonObject`, `lowcoBaseUrl` and `headerOrgId` names (and `lowcoai_lowcodb` some of them), like their TS counterparts. Import one of the packages with a prefix when you use both in one file:

```dart
import 'package:lowcoai_integrations/lowcoai_integrations.dart';
import 'package:lowcoai_workflow/lowcoai_workflow.dart' as wf;
```
