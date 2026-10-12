// Package api is the official Go client for the Lowco API: PDF, render, OCR,
// Document AI, QR codes and barcodes, with jobs, file inputs, webhooks and
// typed errors.
//
//	client, err := api.NewClient(api.Config{}) // LOWCO_API_KEY
//	answer, err := client.DocAI.Invoice(ctx, api.DocaiInvoiceParams{File: api.FilePath("invoice.pdf")}, api.WithMode("async"))
//	invoice, err := answer.Result(ctx) // waits for the job, honouring Retry-After
//
// Operation methods return an *Answer: Data when the operation finished in
// the request (200), Job when it was accepted as one (202), Bytes when
// WithAccept asked for the output file's own type. Answer.Result waits for a
// job and decodes its result. Every failure is an *Error with a typed Reason
// (ErrorReasons describes each); a failed job is a *JobFailedError.
//
// The operation and resource types are generated from the API's OpenAPI
// document by tools/apigen (zz_generated.go); the transport, file inputs,
// waiting, pagination and webhook verification are hand-written.
package api
