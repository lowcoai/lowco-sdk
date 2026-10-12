# Changelog

## 1.1.0

- First release, generated from Lowco API 1.1.0: every Phase 1 operation (PDF, render, OCR, Document AI, QR and barcodes) and resource (files, jobs, webhooks, templates, settings, usage, audit log).
- File inputs from paths, bytes, streams, URLs, file ids and base64; multipart or references chosen per call.
- `wait_for_result` and `jobs.wait` (Retry-After, timeout), `list_all` iterators, `LowcoApiError` with typed `reason`, retries on 429/503, `new_idempotency_key`, raw bytes with `accept`, webhook `verify_signature` and `construct_event`; standard library only.
