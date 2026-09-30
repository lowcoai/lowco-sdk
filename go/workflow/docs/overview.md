# Overview

The `workflow` Go package is the Go counterpart of the Node `@lowcoai/workflow`, designed for strongly typed access to `workflow-orchestrator` APIs.

## Package layout

- `transport.go`: shared HTTP transport, auth headers, query handling, response envelope parsing
- `client.go`: top-level `Client` composition with one sub-client per resource
- `types.go`: request and response models
- `errors.go`: `Error` type returned for non-2xx responses, transport failures and the deprecated webhook methods
- `helpers.go`: internal helpers (query encoding)
- `*_resource.go`: endpoint groups by domain

## API model

All methods follow this style:

```go
result, err := client.Workflows.List(ctx, query)
```

- `context.Context` is always the first argument.
- `error` is always returned as the second return value.
- DELETE endpoints return only `error` where no payload is expected.

## Authentication model

Auth and org headers are configured once in `Config`:

- `Token` -> `Authorization: Bearer <token>`
- `OrgID` -> `X-Org-Id: <orgId>`
- `Headers` -> merged custom headers

## Response envelope behavior

The orchestrator often returns:

```json
{
  "success": true,
  "data": { "...": "..." }
}
```

The SDK unwraps `data` automatically. If `data` is missing, the full payload is unmarshaled into the provided result target.
