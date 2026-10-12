# Changelog

## 2.0.0

- Generated from Lowco API 2.0.0. Breaking: every route moved under `/v1/lowco-api` (for example `POST /v1/lowco-api/qr/generate`); this version calls only the new paths, and 1.x calls 404 once the API moves.
- New: `usage.analytics` (traffic analytics) and `requests.list` (the API request log).

## 1.1.0

- First release, generated from Lowco API 1.1.0: every Phase 1 operation (PDF, render, OCR, Document AI, QR and barcodes) and resource (files, jobs, webhooks, templates, settings, usage, audit log).
- File inputs from paths, bytes, streams, URLs, file ids and base64; multipart or references chosen per call.
- `waitForResult` and `jobs.wait` (Retry-After, timeout), `listAll` iterators, `LowcoApiError` with typed `reason`, retries on 429/503, `newIdempotencyKey`, raw bytes with `accept`, webhook `verifySignature` and `constructEvent`.
