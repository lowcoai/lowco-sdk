## 0.2.0

- Records, view rows, DB functions and transactions go through the base's API gateway
  (`https://api.lowco.ai/gateway/<hash>/v1/...`); the manager's data routes are
  cluster-internal. Method signatures are unchanged — the client resolves a schema's
  gateway (`getGateway`, cached) behind them. `gateways:` pins a gateway per schema,
  `gatewayOrigin: GatewayOrigin.internal` picks the in-cluster address.
- `client.gateway('/gateway/<hash>')` returns a `GatewayClient` with the same data
  methods minus the schema.
- An `lc_` API key is sent as `X-Api-Key`; user tokens stay `Authorization: Bearer`.
- A 402 `QUOTA_EXCEEDED` from the gateway throws `QuotaExceededException` (meter,
  consumed, included, hardCap, periodEnd, upgrade).

## 0.1.0

- Initial release: full lowcodb manager surface (bases, tables, columns, indexes, records, view data, dashboards, triggers, webhooks, transactions, events, DB functions, query, views).
