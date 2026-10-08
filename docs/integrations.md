# integrations — REST surface reference

Service: **integrations-manager**. All routes are mounted under `/v1/integrations/*`.

## Conventions

- **Host**: always `https://api.lowco.ai`.
- **Auth**: `Authorization: Bearer <user-token-or-api-key>` — required; identifies the acting user.
- **Tenancy**: pass `X-Org-Id` on every request.
- **Response envelope**: `{ success, data, error, message }`. Clients should read the inner `data`. Every SDK (`@lowcoai/integrations`, `github.com/lowcoai/lowco-sdk/go/integrations`, `lowcoai-integrations` on PyPI, `lowcoai_integrations` on pub.dev) unwraps automatically.
- **Global org**: org `1` holds globally-shared applications/actions. List/Get endpoints merge org-scoped rows with global rows; mutations on a global entity transparently fork it into the caller's org.

## Endpoints

### Applications

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/applications` | List applications (with connection count, supports `tags=a,b` filter) |
| `GET`    | `/applications/:id` | Get one application |
| `POST`   | `/applications` | Create application |
| `PUT`    | `/applications/:id` | Update application (new version; forks from global if needed) |
| `PATCH`  | `/applications/:id/tags` | Append tags (deduplicated) |
| `DELETE` | `/applications/:id` | Delete application |
| `POST`   | `/applications/:id/run` | Run application (DB query / queue publish) |
| `POST`   | `/applications/:id/load-actions` | Bulk-replace actions from a Postman folder |
| `GET`    | `/applications/:id/versions` | Version history |
| `GET`    | `/applications/:id/regenerate-mcp-key` | Rotate the MCP key |
| `GET`    | `/applications/:id/mcp/tools` | List MCP tools derived from actions |
| `GET`    | `/applications/by-trigger` | Applications that have at least one trigger |
| `GET`    | `/applications/types` | Application type → subtypes catalog |
| `POST`   | `/applications/published/:key` | Published MCP JSON-RPC endpoint |
| `GET`    | `/applications/published/:key` | Published MCP welcome info |

### Actions

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/actions` | List actions |
| `GET`    | `/actions/:id` | Get one action |
| `POST`   | `/applications/:id/action` | Create an action under an application |
| `PUT`    | `/actions/:id` | Update action |
| `DELETE` | `/actions/:id` | Delete action |
| `POST`   | `/actions/:id/run` | Execute action (HTTP-style) |
| `GET`    | `/applications/:id/actions` | List actions for an application |
| `POST`   | `/actions/allCredential` | Batch resolve action IDs → applications + connections |

### Connections

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/connections` | List connections |
| `GET`    | `/connections/:id` | Get one connection (with app type metadata) |
| `POST`   | `/connections` | Create connection |
| `PUT`    | `/connections/:id` | Update connection |
| `DELETE` | `/connections/:id` | Delete connection |
| `PATCH`  | `/connections/:id/setDefault` | Mark connection as default for its application |
| `GET`    | `/applications/:id/connections` | List connections for one application |
| `GET`    | `/connections/:id/token` | Get stored OAuth token metadata |
| `POST`   | `/connections/:id/token/refresh` | Force-refresh OAuth token |

### Triggers

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST`   | `/triggers` | Create trigger (webhook / poll / stream) |
| `GET`    | `/triggers/:id` | Get one trigger (webhook variants include `webhookUrl`) |
| `PUT`    | `/triggers/:id` | Update trigger |
| `DELETE` | `/triggers/:id` | Delete trigger |
| `GET`    | `/triggers/:id/state` | Runner-owned runtime state (last run, error, cursor, lease) |
| `GET`    | `/applications/:id/triggers` | List triggers for an application |

### OAuth

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `POST`   | `/oauth/:appId/login` | Start authorization-code flow; returns provider URL |
| `POST`   | `/oauth/callback` | Finish authorization-code flow; creates connection + tokens |
| `POST`   | `/oauth/tokens/refresh-expiring` | Batch-refresh tokens expiring in the next 12h |

### Configurations

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`    | `/configurations` | Supported application types → subtypes |
