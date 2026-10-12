# Lowco API SDKs

The four Lowco API packages (`go/api`, `npm/api` → `@lowcoai/api`, `python/api` → `lowcoai-api`, `flutter/api` → `lowcoai_api`) are generated from the API's OpenAPI 3 document and share one design. The REST reference is https://docs.lowco.ai/api/.

## Generation

- `specs/lowco-api.json` is a copy of lowco-api's `services/api/docs/swagger.json`. Update it with `make api-sync LOWCO_API=../lowco-api`, which runs the compatibility gate first.
- `tools/apigen` (Go, stdlib only) reads it into one model: 28 operations, the resource routes, 172 types and the 56 `error.reason` values with their descriptions. It writes `npm/api/src/generated.ts`, `python/api/src/lowcoai/api/_generated.py`, `go/api/zz_generated.go` and `flutter/api/lib/src/generated.dart`. Run it with `make api-gen`.
- The rest of each package is hand-written:
  - transport: auth, the envelope, typed errors and retries;
  - file inputs;
  - job waiting and pagination;
  - webhook verification.
- `make api-check` fails when the generated files are stale.

## Compatibility gate

`go run ./tools/apigen -compat old.json new.json` (`make api-compat`) fails, naming each change, when a client built from `old` could break against `new`:

- a removed route or method;
- a removed, newly required or retyped request field;
- a removed enum value;
- a removed or newly required query parameter;
- a removed, retyped, newly optional or newly nullable response field;
- a removed error reason.

Additions are listed but pass. `tools/apigen` tests every rule. CI runs the gate against lowco-api's current document before anything is generated or published.

## Tests

| Where | What |
| --- | --- |
| each package | unit tests against an in-process mock API: envelope, typed errors, multipart and reference file inputs (and the upload of local inputs in mixed calls), job waiting with Retry-After, failed and timed-out jobs, pagination, 429 retries, Idempotency-Key, raw bytes, signed downloads |
| each package | webhook verification against `specs/webhook-signature-vectors.json`, eight vectors made by lowco-api's own signer (`core/webhooksig`): valid, rotation, tampered, stale, future, wrong secret, malformed, empty |
| lowco-api `tests/e2e` `TestSDKQuickstartsRun` | every package's quickstart example (`qr/generate` as PNG bytes, then `docai/invoice` as a job, waited for) against the real Lowco API stack in the test environment |
| CI (`.github/workflows/api.yml`) | the same examples against the hosted test environment with a test key |

## Versions

A package's major and minor follow the API document's `info.version` (`API_VERSION`); the patch number is for SDK-only fixes. A breaking API change is a new major, which the compatibility gate forces to be deliberate.
