// Package lowcodb is the Go client for the lowcodb manager service.
//
// It mirrors every endpoint registered in lowcodb/manager/server/server.go,
// unwraps the standard response envelope ({ success, data, error, message })
// and surfaces non-2xx responses as *RequestError.
//
// Every request is sent to the fixed host DefaultBaseURL
// ("https://api.lowco.ai"). NewClient requires a token (a user token or an
// API key) that is sent as "Authorization: Bearer <token>" on every request.
// Tenancy is identified through the X-Org-Id header; set it with WithOrgID at
// construction or SetOrgID later.
package lowcodb
