# integrations (Go)

Official Go client for the **integrations-manager** product (routes under `/v1/integrations/*`).

```bash
go get github.com/lowcoai/lowco-sdk/go/integrations
```

## Quick start

```go
package main

import (
	"context"
	"log"

	"github.com/lowcoai/lowco-sdk/go/integrations"
)

func main() {
	ctx := context.Background()

	client, err := integrations.NewClient(integrations.Config{
		Token: "your-token-or-api-key", // required
		OrgID: "1",
	})
	if err != nil {
		log.Fatal(err)
	}

	page, limit := 1, 20
	apps, err := client.Applications.List(ctx, &integrations.PaginationQuery{
		Page:  &page,
		Limit: &limit,
		Tags:  "crm,sales",
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("found %d applications", len(apps))
}
```

## Run an action

```go
result, err := client.Actions.Run(ctx, "action_123", integrations.RunActionRequest{
	CredentialID: "conn_456",
	InputBody: map[string]any{
		"to":      "alice@example.com",
		"subject": "Hello",
	},
})
```

## OAuth flow

```go
login, _ := client.OAuth.Login(ctx, "app_slack", integrations.ConnectionCreateRequest{
	ApplicationID: "app_slack",
	Name:          "Slack — Sales workspace",
})
// redirect user to login.URL ...

// On the redirect_uri callback:
_, _ = client.OAuth.Callback(ctx, integrations.CallbackRequest{
	State: state,
	Code:  code,
})
```

## Resources

`client.Applications`, `client.Actions`, `client.Connections`, `client.Triggers`,
`client.OAuth`, `client.Configurations`, `client.MCP` — see
[`../../docs/integrations.md`](../../docs/integrations.md) for the full
method-to-endpoint map.

## Error handling

All non-2xx responses return `*integrations.Error`:

```go
if err != nil {
	var sdkErr *integrations.Error
	if errors.As(err, &sdkErr) {
		log.Printf("status=%d payload=%v", sdkErr.Status, sdkErr.Payload)
	}
}
```

## Conventions

- Host: all requests go to `https://api.lowco.ai` (`integrations.DefaultBaseURL`).
- Auth: `Config.Token` is required (a user token or an API key) and is sent as `Authorization: Bearer <Token>` on every request.
- Tenancy: `X-Org-Id` header (set via `Config.OrgID`).
- Response envelope: `{ success, data, error, message }` — the SDK unwraps `data` for you.
