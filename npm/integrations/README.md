# @lowcoai/integrations

Official Node/TypeScript client for the **integrations-manager** product (routes under `/v1/integrations/*`).

```bash
npm install @lowcoai/integrations
```

## Quick start

```ts
import { IntegrationsClient } from "@lowcoai/integrations";

const client = new IntegrationsClient({
  token: "your-token-or-api-key", // required
  orgId: "1"
});

const apps = await client.applications.list({ page: 1, limit: 20, tags: "crm,sales" });
console.log(`found ${apps.length} applications`);
```

## Run an action

```ts
const result = await client.actions.run("action_123", {
  credentialId: "conn_456",
  inputBody: { to: "alice@example.com", subject: "Hello" }
});
```

## OAuth flow

```ts
const { url } = await client.oauth.login("app_slack", {
  applicationId: "app_slack",
  name: "Slack — Sales workspace"
});
// redirect user to url ...

// On the redirect_uri callback:
await client.oauth.callback({ state, code });
```

## Resources

`client.applications`, `client.actions`, `client.connections`, `client.triggers`,
`client.oauth`, `client.configurations`, `client.mcp` — see
[`../../docs/integrations.md`](../../docs/integrations.md) for the full
method-to-endpoint map.

## Error handling

All non-2xx responses throw `IntegrationsError`:

```ts
import { IntegrationsError } from "@lowcoai/integrations";

try {
  await client.actions.run("action_123", { inputBody: {} });
} catch (err) {
  if (err instanceof IntegrationsError) {
    console.error(err.status, err.payload);
  }
}
```

## Conventions

- Host: all requests go to `https://api.lowco.ai`.
- Tenancy: `X-Org-Id` header (set via `orgId`).
- Auth: `Authorization: Bearer <token>` — `token` (user token or API key) is required.
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.
