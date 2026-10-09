# Changelog

## 1.1.0

- First release, generated from Lowco API 1.1.0: every Phase 1 operation (PDF, render, OCR, Document AI, QR and barcodes) and resource (files, jobs, webhooks, templates, settings, usage, audit log).
- File inputs from paths, bytes, streams, URLs, file ids and base64; multipart or references chosen per call.
- `waitForResult` and `jobs.wait` (Retry-After, timeout), `listAll` iterators, `LowcoApiError` with typed `reason`, retries on 429/503, `newIdempotencyKey`, raw bytes with `accept`, webhook `verifySignature` and `constructEvent`.
