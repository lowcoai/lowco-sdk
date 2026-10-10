# @lowcoai/api

Official Node/TypeScript client for the **Lowco API**: PDF, render, OCR, Document AI, QR codes and barcodes, with jobs, file inputs, webhooks and typed errors. Generated from the API's OpenAPI document (`specs/lowco-api.json`) with hand-written helpers. Node 18+, no runtime dependencies.

```bash
npm install @lowcoai/api
```

## Quick start

```ts
import { Files, LowcoApi } from "@lowcoai/api";

const lowco = new LowcoApi(); // LOWCO_API_KEY: lc_test_… or lc_live_…

// Answers inline (200) …
const qr = await lowco.qr.generate({ type: "upi", pa: "acme@okhdfcbank", pn: "Acme Traders", am: "1499.00" }, { accept: "image/png" });
// qr.bytes is the PNG

// … or as a job (202): waitForResult polls it, honouring Retry-After
const answer = await lowco.docai.invoice({ file: Files.path("invoice.pdf") }, { mode: "async" });
const invoice = await lowco.waitForResult(answer);
console.log(invoice.invoice_number.value, invoice.invoice_number.confidence);
```

`examples/quickstart.mjs` is the full program; CI runs it against the test environment.

## Operations

`lowco.<service>.<operation>(params, options?)` for every operation: `pdf` (merge, split, arrange, compress, rotate, watermark, protect, unlock, toImages, fromImages, info, extractText, toDocx), `render` (html, template, docx, docxTemplate), `ocr` (text, handwriting), `docai` (classify, invoice, receipt, tables, extract), `qr` (generate, decode), `barcode` (generate, decode). Params and results are typed (`PdfMergeParams`, `PdfMergeResult`, …); field names are the API's.

Each returns an `Answer<T>`: `data` when the operation finished in the request, `job` when it was accepted as one (status 202), `bytes` and `contentType` when `accept` asked for the output's own type. `requestId`, `replayed` (Idempotency-Key replay) and `creditsUsed` come from the headers.

Call options: `mode` (`"sync"` or `"async"`), `accept`, `idempotencyKey`, `requestId`, `signal`, `timeoutMs`.

## Files

```ts
Files.path("scan.pdf", { password: "…" })      // read when the call is made
Files.bytes(buffer, { filename: "a.pdf" })      // Uint8Array, ArrayBuffer or Blob (also accepted bare)
Files.stream(readable, { filename: "a.pdf" })   // Node or web stream
Files.url("https://example.com/a.pdf")          // the API fetches it (file_url)
Files.id("file_01J…")                           // a stored file (lowco.files.upload or an earlier output)
Files.base64(b64, { filename: "a.pdf" })
```

Local inputs go as multipart parts (options as a JSON `options` field); remote ones as JSON references; when a call mixes both, the local ones are uploaded with `files.upload` first. Output files are `Output` objects with a signed `url` valid one hour: `lowco.files.download(url)`.

## Jobs, pagination, errors

```ts
const job = await lowco.jobs.wait("job_01J…", { timeoutMs: 120_000 }); // LowcoJobError if it failed, LowcoTimeoutError at the timeout
for await (const j of lowco.jobs.listAll({ status: "failed" })) { … }   // follows next_cursor

try { … } catch (e) {
  if (e instanceof LowcoApiError) {
    e.reason;    // "file_too_large", … (ErrorReason; ERROR_REASONS says when and what to do)
    e.status; e.param; e.details; e.requestId; e.docUrl; e.retryable; e.retryAfter;
  }
}
```

GETs and calls with an `idempotencyKey` (see `newIdempotencyKey()`) are retried on 429, 503 and network failures, honouring `Retry-After` (`maxRetries`, default 2).

## Webhooks

```ts
import { constructEvent, verifySignature } from "@lowcoai/api";

const event = constructEvent(rawBody, req.headers["lowco-signature"], process.env.LOWCO_WEBHOOK_SECRET!); // throws LowcoSignatureError
```

Pass the **raw** body. Timestamps more than 5 minutes off are refused; during a secret rotation any matching `v1` verifies.

## Resources

`files` (upload, get, delete, contentUrl, download), `jobs` (list, listAll, get, cancel, wait), `webhooks` (create, list, listAll, get, update, delete, ping, listDeliveries, listDeliveriesAll, retryDelivery, rollCallbackSecret), `templates` (create, list, listAll, get, update, delete, listVersions, listVersionsAll), `settings` (get, update, purge), `usage` (get), `audit` (list, listAll).

## Configuration

`new LowcoApi({ apiKey, baseUrl, timeoutMs, maxRetries, fetch })`; `apiKey` defaults to `LOWCO_API_KEY` and `baseUrl` to `LOWCO_API_BASE_URL`, else `https://api.lowco.ai`.

The version follows the API document (`API_VERSION`); see CHANGELOG.md. Reference: https://docs.lowco.ai/api/
