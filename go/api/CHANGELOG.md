# Changelog

## 2.0.0

- Generated from Lowco API 2.0.0. Breaking: every route moved under `/v1/lowco-api` (for example `POST /v1/lowco-api/qr/generate`); this version calls only the new paths, and 1.x calls 404 once the API moves. Paths passed to `Client.Operation`, `Client.Request` and `Client.RequestRaw` must carry the prefix.
- The module path is now `github.com/lowcoai/lowco-sdk/go/api/v2`.
- New: `Usage.Analytics` (traffic analytics) and `Requests.List` (the API request log).

## 1.1.0

- First release, generated from Lowco API 1.1.0: every Phase 1 operation (PDF, render, OCR, Document AI, QR and barcodes) and resource (files, jobs, webhooks, templates, settings, usage, audit log).
- File inputs from paths, bytes, streams, URLs, file ids and base64; multipart or references chosen per call.
- `Answer.Result` and `Jobs.Wait` (Retry-After, timeout), `ListAll` pagers, `*api.Error` with typed `Reason`, retries on 429/503, `NewIdempotencyKey`, raw bytes with `WithAccept`, webhook `VerifySignature` and `ConstructEvent`; standard library only.
- `Client.Operation`, `Client.Request` and `Client.RequestRaw` call any operation or route by path, for tools built from the API document (lowco-cli).
