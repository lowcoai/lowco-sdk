# lowcoai-api

Official Python client for the **Lowco API**: PDF, render, OCR, Document AI, QR codes and barcodes, with jobs, file inputs, webhooks and typed errors. Generated from the API's OpenAPI document with hand-written helpers. Python 3.9+, standard library only.

```bash
pip install lowcoai-api
```

## Quick start

```python
from lowcoai.api import Files, LowcoApi

lowco = LowcoApi()  # LOWCO_API_KEY: lc_test_… or lc_live_…

qr = lowco.qr.generate(type="upi", pa="acme@okhdfcbank", pn="Acme Traders", am="1499.00", accept="image/png")
open("qr.png", "wb").write(qr.bytes)

answer = lowco.docai.invoice(file=Files.path("invoice.pdf"), mode="async")  # 202 with a job
invoice = lowco.wait_for_result(answer)                                       # polls, honouring Retry-After
print(invoice["invoice_number"]["value"], invoice["invoice_number"]["confidence"])
```

`examples/quickstart.py` is the full program; CI runs it against the test environment.

## Operations

`lowco.<service>.<operation>(**params)` for every operation: `pdf` (merge, split, arrange, compress, rotate, watermark, protect, unlock, to_images, from_images, info, extract_text, to_docx), `render` (html, template, docx, docx_template), `ocr` (text, handwriting), `docai` (classify, invoice, receipt, tables, extract), `qr` (generate, decode), `barcode` (generate, decode). Parameters are keyword-only and named like the API's fields; results are typed dicts (`PdfMergeResult`, …).

Each returns an `Answer`: `data` when finished in the request, `job` when accepted as one (status 202), `bytes`/`content_type` when `accept` asked for the output's own type; plus `request_id`, `replayed` and `credits_used`. Every operation also takes `mode`, `accept`, `idempotency_key`, `request_id` and `timeout`.

## Files

`Files.path(p, password=…)`, `Files.bytes(b, filename=…)`, `Files.stream(fileobj)`, `Files.url(u)`, `Files.id("file_…")`, `Files.base64(s)`; bytes and binary file objects are accepted bare. Local inputs go as multipart parts, remote ones by reference; mixed calls upload the local ones first. `lowco.files.download(url)` fetches an output's signed link.

## Jobs, pagination, errors

```python
job = lowco.jobs.wait("job_01J…", timeout=120)          # LowcoJobError if it failed, LowcoTimeoutError at the timeout
for j in lowco.jobs.list_all(status="failed"): ...       # follows next_cursor

try:
    ...
except LowcoApiError as e:
    e.reason, e.status, e.param, e.details, e.request_id, e.doc_url, e.retryable, e.retry_after
```

`ERROR_REASONS` says when each reason is answered and what to do. GETs and calls with an `idempotency_key` (`new_idempotency_key()`) are retried on 429, 503 and network failures. A parameter named like a Python keyword takes a trailing underscore (`usage.get(from_="2026-10-01")`).

## Webhooks

```python
from lowcoai.api import construct_event

event = construct_event(raw_body, request.headers.get("Lowco-Signature"), secret)  # raises LowcoSignatureError
```

## Configuration

`LowcoApi(api_key=None, *, base_url=None, timeout=60.0, max_retries=2)`; the key defaults to `LOWCO_API_KEY` and the base URL to `LOWCO_API_BASE_URL`, else `https://api.lowco.ai`. Tests: `python -m unittest discover -s tests`. Reference: https://docs.lowco.ai/api/
