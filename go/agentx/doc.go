// Package agentx is the Go client for the agentx backend, covering the
// agent-manager, agent-kb (knowledge-base) and agent-executor services.
//
// A single Client exposes three sub-clients – Manager, KB, Executor – that
// mirror the routes registered in each service's server.go. They share HTTP
// transport, tenancy headers (X-Org-Id / X-User-Id) and request options.
//
// Construction:
//
//	client, err := agentx.NewClient("http://localhost:8080",
//	    agentx.WithOrgID("org_123"),
//	    agentx.WithUserID("user_123"),
//	)
//
// When the three services live behind different hosts, override individual
// base URLs with WithManagerURL / WithKBURL / WithExecutorURL.
//
// Enveloped responses ({success, data, error, message}) are unwrapped
// automatically; non-2xx responses surface as *RequestError. JSON-RPC level
// errors from the executor are returned inside JSONRPCResponse.Error.
package agentx
