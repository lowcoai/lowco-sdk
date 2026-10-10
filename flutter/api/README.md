# lowcoai_api

Official Dart and Flutter client for the **Lowco API**: PDF, render, OCR, Document AI, QR codes and barcodes, with jobs, file inputs, webhooks and typed errors. Generated from the API's OpenAPI document with hand-written helpers. Pure Dart (`package:http`, `package:crypto`); file paths need `dart:io` (VM, mobile, desktop).

```bash
dart pub add lowcoai_api
```

## Quick start

```dart
final lowco = LowcoApi(); // LOWCO_API_KEY

final qr = await lowco.qr.generate(const QrGenerateParams(type: 'upi', pa: 'acme@okhdfcbank', pn: 'Acme Traders', am: '1499.00'),
    const CallOptions(accept: 'image/png'));
// qr.bytes is the PNG

final answer = await lowco.docai.invoice(DocaiInvoiceParams(file: FileInput.path('invoice.pdf')), const CallOptions(mode: 'async'));
final invoice = await lowco.waitForResult(answer, InvoiceResult.fromJson); // polls, honouring Retry-After
print('${invoice.invoiceNumber?.value} ${invoice.invoiceNumber?.confidence}');
```

`example/quickstart.dart` is the full program; CI runs it against the test environment.

## Operations

`lowco.<service>.<operation>(params, [options])`: `pdf`, `render`, `ocr`, `docai`, `qr`, `barcode`. Params and results are generated classes (`PdfMergeParams`, `PdfMergeResult`, …) with camelCase fields mapped to the API's names. Each returns `Answer<T>`: `data` (200), `job` (202) or `bytes`/`contentType` (with `accept`), plus `requestId`, `replayed`, `creditsUsed`. `CallOptions(mode:, accept:, idempotencyKey:, requestId:, timeout:)`.

## Files

`FileInput.path`, `FileInput.bytes`, `FileInput.stream`, `FileInput.url`, `FileInput.id`, `FileInput.base64` (each with `password:`). Local inputs go as multipart parts, remote ones by reference; mixed calls upload the local ones first. `lowco.files.download(url)` fetches a signed link.

## Jobs, pagination, errors

```dart
final job = await lowco.jobs.wait('job_01J…', timeout: const Duration(minutes: 2)); // LowcoJobError / LowcoTimeoutError
await for (final j in lowco.jobs.listAll(const JobsListQuery(status: 'failed'))) { … }

try { … } on LowcoApiError catch (e) {
  if (e.reason == ErrorReason.fileTooLarge) { … } // errorReasons says when and what to do
}
```

GETs and calls with an idempotency key (`newIdempotencyKey()`) are retried on 429, 503 and network failures.

## Webhooks

```dart
final event = constructEvent(rawBodyBytes, request.headers['lowco-signature'], secret); // throws LowcoSignatureError
```

## Configuration

`LowcoApi(apiKey:, baseUrl:, httpClient:, timeout:, maxRetries:)`; the key defaults to `LOWCO_API_KEY` and the base URL to `LOWCO_API_BASE_URL`, else `https://api.lowco.ai`. Reference: https://docs.lowco.ai/api/
