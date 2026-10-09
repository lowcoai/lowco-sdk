# Changelog

## 1.1.0

- First release, generated from Lowco API 1.1.0: every Phase 1 operation (PDF, render, OCR, Document AI, QR and barcodes) and resource (files, jobs, webhooks, templates, settings, usage, audit log).
- File inputs from paths, bytes, streams, URLs, file ids and base64; multipart or references chosen per call.
- `Answer.Result` and `Jobs.Wait` (Retry-After, timeout), `ListAll` pagers, `*api.Error` with typed `Reason`, retries on 429/503, `NewIdempotencyKey`, raw bytes with `WithAccept`, webhook `VerifySignature` and `ConstructEvent`; standard library only.
- `Client.Operation`, `Client.Request` and `Client.RequestRaw` call any operation or route by path, for tools built from the API document (lowco-cli).
