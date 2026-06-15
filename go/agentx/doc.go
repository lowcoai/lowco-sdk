// Package agentx is the Go client for the agentx backend, covering the
// agent-manager, agent-kb (knowledge-base) and agent-executor services.
//
// A single Client exposes three sub-clients – Manager, KB, Executor – that
// mirror the routes registered in each service's server.go. They share HTTP
// transport, the X-Org-Id tenancy header and request options. All three
// services live behind the fixed host DefaultBaseURL ("https://api.lowco.ai").
//
// Construction requires a token (a user token or an API key) that is sent as
// "Authorization: Bearer <token>" on every request:
//
//	client, err := agentx.NewClient("<token-or-api-key>",
//	    agentx.WithOrgID("org_123"),
//	)
//
// Enveloped responses ({success, data, error, message}) are unwrapped
// automatically; non-2xx responses surface as *RequestError. JSON-RPC level
// errors from the executor are returned inside JSONRPCResponse.Error.
package agentx
