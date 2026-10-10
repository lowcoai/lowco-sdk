# go/api

Official Go client for the **Lowco API**: PDF, render, OCR, Document AI, QR codes and barcodes, with jobs, file inputs, webhooks and typed errors. Generated from the API's OpenAPI document (`zz_generated.go`) with hand-written helpers. Standard library only.

```bash
go get github.com/lowcoai/lowco-sdk/go/api
```

## Quick start

```go
client, err := api.NewClient(api.Config{}) // LOWCO_API_KEY

qr, err := client.QR.Generate(ctx, api.QrGenerateParams{Type: api.String("upi"), Pa: api.String("acme@okhdfcbank"),
	Pn: api.String("Acme Traders"), Am: api.String("1499.00")}, api.WithAccept("image/png"))
// qr.Bytes is the PNG

answer, err := client.DocAI.Invoice(ctx, api.DocaiInvoiceParams{File: api.FilePath("invoice.pdf")}, api.WithMode("async"))
invoice, err := answer.Result(ctx) // waits for the job, honouring Retry-After
fmt.Println(invoice.InvoiceNumber.Value, invoice.InvoiceNumber.Confidence)
```

`examples/quickstart` is the full program; CI runs it against the test environment.

## Operations

`client.<Service>.<Operation>(ctx, params, opts...)`: `PDF`, `Render`, `OCR`, `DocAI`, `QR`, `Barcode`. Optional parameters are pointers (`api.String`, `api.Int`, `api.Float`, `api.Bool`). Each returns `*api.Answer[T]`: `Data` (200), `Job` (202) or `Bytes`/`ContentType` (with `WithAccept`), plus `RequestID`, `Replayed`, `CreditsUsed`; `Answer.Result` returns the data or waits for the job. Options: `WithMode`, `WithAccept`, `WithIdempotencyKey`, `WithRequestID`.

## Files

`api.FilePath`, `api.FileBytes`, `api.FileReader`, `api.FileURL`, `api.FileID`, `api.FileBase64`, with `api.WithFilename`, `api.WithMimeType`, `api.WithPassword`. Local inputs go as multipart parts, remote ones by reference; mixed calls upload the local ones first. `client.Files.Download(ctx, url)` fetches a signed link.

## Jobs, pagination, errors

```go
job, err := client.Jobs.Wait(ctx, "job_01J…", api.WithWaitTimeout(2*time.Minute))
p := client.Jobs.ListAll(ctx, &api.JobsListQuery{Status: api.String("failed")})
for p.Next(ctx) { job := p.Item(); … }

var e *api.Error
if errors.As(err, &e) && e.Reason == api.ReasonFileTooLarge { … } // *api.JobFailedError for failed jobs, *api.TimeoutError at the timeout
```

`api.ErrorReasons` describes every reason. GETs and calls with an Idempotency-Key (`api.NewIdempotencyKey()`) are retried on 429, 503 and network failures.

## Webhooks

```go
ev, err := api.ConstructEvent(rawBody, r.Header.Get(api.SignatureHeader), secret) // api.ErrSignature when it does not verify
```

## Calls by path

Tools that build calls from the API document (`lowco api` in lowco-cli) use the two untyped entry points, which share the typed services' file handling, retries, errors and job waiting:

```go
ans, err := client.Operation(ctx, "/v1/pdf/merge", api.OperationInput{
	Files:  []api.FileInput{api.FilePath("a.pdf"), api.FilePath("b.pdf")},
	Params: map[string]any{"bookmarks": true},
})
raw, err := client.Request(ctx, http.MethodGet, "/v1/jobs", url.Values{"status": {"failed"}}, nil)
```

`ans.Data` is the result as `json.RawMessage`; `ans.Result(ctx)` waits for a job. Applications should prefer the typed services.

## Configuration

`api.Config{APIKey, BaseURL, HTTPClient, Timeout, MaxRetries}`; the key defaults to `LOWCO_API_KEY` and the base URL to `LOWCO_API_BASE_URL`, else `https://api.lowco.ai`. Reference: https://docs.lowco.ai/api/
