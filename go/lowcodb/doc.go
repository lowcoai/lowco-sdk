// Package lowcodb is the Go client for the lowcodb manager service.
//
// It mirrors every endpoint registered in lowcodb/manager/server/server.go,
// unwraps the standard response envelope ({ success, data, error, message })
// and surfaces non-2xx responses as *RequestError.
//
// Tenancy is identified through the X-Org-Id / X-User-Id headers; set them
// with WithOrgID / WithUserID at construction or SetOrgID / SetUserID later.
package lowcodb
