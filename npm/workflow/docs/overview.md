# Overview

## Purpose

`@lowcoai/workflow` is the TypeScript client for the **workflow-orchestrator** product. It wraps every controller in `workflow-orchestrator/api` with typed methods and a consistent request lifecycle, served under `/v1/wf/*`.

## SDK surface

- `workflows`: workflow CRUD, run, versions, publish, template search
- `environments`: environment CRUD and default environment selection
- `functions`: function CRUD, versions, and execute
- `executions`: execution list/get/count/logs
- `activities`: activity list/get/count/logs
- `humanTasks`: list/get/complete
- `analytics`: metrics endpoints
- `dryRun`: expression evaluation for debugging execution context
- `webhooks`: webhook-trigger and webhook management routes

## Transport behavior

- JSON request/response by default
- Supports `Authorization: Bearer <token>`
- Supports `X-Org-Id` and `X-User-Id` headers
- Optional per-request query params and abort signal
- Envelope-aware response parser (`{ data: ... }` unwrapped automatically)
- Throws `WorkflowError` with HTTP status and raw payload on failures

## Compatibility assumptions

- Base API URL serves endpoints under `/v1/wf`
- Runtime supports `fetch` (Node 18+ or browser), or a custom fetch is injected
