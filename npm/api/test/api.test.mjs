import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { ERROR_REASONS, Files, LowcoApi, LowcoApiError, LowcoJobError, LowcoTimeoutError, constructEvent, newIdempotencyKey, verifySignature } from "../dist/index.js";

const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452", "hex");
const env = (data) => JSON.stringify({ status: 1, data });
const job = (id, status, extra = {}) => ({ job_id: id, service: "docai", operation: "invoice", status, progress: null, input: {}, result: null, error: null, usage: null, attempts: 1, created_at: "2026-10-09T09:30:00Z", started_at: null, finished_at: null, expires_at: "2026-10-16T09:30:00Z", links: { self: `/v1/jobs/${id}`, cancel: `/v1/jobs/${id}/cancel` }, ...extra });

const seen = [];
let polls = 0;
let settingsCalls = 0;
let server;
let base;

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
  });
}

before(async () => {
  server = createServer(async (req, res) => {
    const body = await readBody(req);
    const url = new URL(req.url, "http://x");
    seen.push({ method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), headers: req.headers, body });
    const send = (status, payload, headers = {}) => {
      res.writeHead(status, { "content-type": "application/json", "x-request-id": "req_test", ...headers });
      res.end(payload);
    };
    if (req.headers.authorization !== "Bearer lc_test_sdk" && !url.pathname.startsWith("/v1/downloads/")) {
      return send(401, JSON.stringify({ status: 0, error: { code: 401, reason: "missing_key", message: "No key", doc_url: "https://docs.lowco.ai/api/errors#missing_key" } }));
    }
    switch (`${req.method} ${url.pathname}`) {
      case "POST /v1/qr/generate":
        if (req.headers.accept === "image/png") {
          res.writeHead(200, { "content-type": "image/png" });
          return res.end(PNG);
        }
        return send(200, env({ format: "png", width: 512, height: 512, file: { file_id: "file_out", url: `${base}/v1/downloads/tok` } }), { "x-lowco-credits-used": "0.0500" });
      case "POST /v1/docai/invoice":
        if (url.searchParams.get("mode") === "async") return send(202, env(job("job_inv", "queued")), { "retry-after": "0" });
        return send(200, env({ invoice_number: { value: "INV-1", confidence: 0.98, source: { page: 1 } } }));
      case "GET /v1/jobs/job_inv":
        polls++;
        if (polls < 3) return send(200, env(job("job_inv", "processing")), { "retry-after": "0" });
        return send(200, env(job("job_inv", "succeeded", { result: { invoice_number: { value: "INV-1", confidence: 0.98, source: { page: 1 } } } })));
      case "GET /v1/jobs/job_bad":
        return send(200, env(job("job_bad", "failed", { error: { code: 422, reason: "file_corrupt", message: "The file is not a readable PDF.", doc_url: "https://docs.lowco.ai/api/errors#file_corrupt" } })));
      case "GET /v1/jobs/job_slow":
        return send(200, env(job("job_slow", "processing")), { "retry-after": "0" });
      case "GET /v1/jobs":
        if (!url.searchParams.get("cursor")) return send(200, env({ items: [job("j1", "succeeded"), job("j2", "succeeded")], next_cursor: "c2" }));
        return send(200, env({ items: [job("j3", "failed")], next_cursor: null }));
      case "POST /v1/files":
        return send(201, env({ file_id: "file_uploaded", filename: "a.pdf", bytes: 3, mime_type: "application/pdf", sha256: "x", source: "upload", expires_at: null, created_at: "2026-10-09T09:30:00Z" }));
      case "POST /v1/pdf/merge":
        return send(200, env({ pages: 2, files_merged: 2, file: { file_id: "file_m", url: null } }));
      case "POST /v1/pdf/rotate":
        return send(400, JSON.stringify({ status: 0, error: { code: 400, reason: "invalid_param", message: "angle must be 90, 180 or 270.", param: "angle", request_id: "req_err", doc_url: "https://docs.lowco.ai/api/errors#invalid_param" } }));
      case "POST /v1/ocr/text":
        return send(202, env(job("job_ocr", "queued")), { "idempotent-replayed": "true" });
      case "GET /v1/settings":
        settingsCalls++;
        if (settingsCalls === 1) return send(429, JSON.stringify({ status: 0, error: { code: 429, reason: "rate_limited", message: "Slow down", doc_url: "x", retryable: true } }), { "retry-after": "0" });
        return send(200, env({ environment: "test", retention_input_hours: 24 }));
      case "GET /v1/files/file_x/content":
        res.writeHead(307, { location: `${base}/v1/downloads/tok_x` });
        return res.end();
      case "GET /v1/downloads/tok_x":
        res.writeHead(200, { "content-type": "application/pdf" });
        return res.end("%PDF-1.7");
    }
    send(404, JSON.stringify({ status: 0, error: { code: 404, reason: "route_not_found", message: "no route", doc_url: "x" } }));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const client = () => new LowcoApi({ apiKey: "lc_test_sdk", baseUrl: base });
const last = (path) => [...seen].reverse().find((s) => s.path === path);

test("an inline answer carries data, the request id and credits", async () => {
  const a = await client().qr.generate({ type: "upi", pa: "acme@okhdfcbank", pn: "Acme", am: "1499.00" });
  assert.equal(a.status, 200);
  assert.equal(a.data.width, 512);
  assert.equal(a.requestId, "req_test");
  assert.equal(a.creditsUsed, "0.0500");
  const sent = last("/v1/qr/generate");
  assert.equal(sent.headers["content-type"], "application/json");
  assert.deepEqual(JSON.parse(sent.body), { type: "upi", pa: "acme@okhdfcbank", pn: "Acme", am: "1499.00" });
  assert.match(sent.headers["x-client-user-agent"], /^lowcoai-api-node\//);
});

test("accept returns the output file's bytes", async () => {
  const a = await client().qr.generate({ content: "x" }, { accept: "image/png" });
  assert.equal(a.contentType, "image/png");
  assert.deepEqual(Buffer.from(a.bytes), PNG);
});

test("a local file goes as multipart with the options as JSON, then a job is waited for", async () => {
  const dir = mkdtempSync(join(tmpdir(), "lowco-"));
  writeFileSync(join(dir, "invoice.pdf"), "%PDF-1.7 test");
  const lowco = client();
  const a = await lowco.docai.invoice({ file: Files.path(join(dir, "invoice.pdf")), languages: ["eng", "hin"] }, { mode: "async" });
  assert.equal(a.status, 202);
  assert.equal(a.job.job_id, "job_inv");
  const sent = last("/v1/docai/invoice");
  assert.match(sent.headers["content-type"], /^multipart\/form-data/);
  const text = sent.body.toString();
  assert.match(text, /name="file"; filename="invoice.pdf"/);
  assert.match(text, /%PDF-1.7 test/);
  assert.match(text, /name="options"\r\n\r\n\{"languages":\["eng","hin"\]\}/);
  assert.equal(sent.query.mode, "async");
  const result = await lowco.waitForResult(a);
  assert.equal(result.invoice_number.value, "INV-1");
  assert.equal(polls, 3);
});

test("remote inputs go as JSON references; mixed inputs upload the local ones first", async () => {
  await client().pdf.merge({ files: [Files.id("file_a"), Files.url("https://example.com/b.pdf")], bookmarks: true });
  assert.deepEqual(JSON.parse(last("/v1/pdf/merge").body), { bookmarks: true, files: [{ file_id: "file_a" }, { file_url: "https://example.com/b.pdf" }] });
  await client().pdf.merge({ files: [Files.id("file_a"), new Uint8Array([37, 80, 68])] });
  assert.match(last("/v1/files").headers["content-type"], /^multipart\/form-data/);
  assert.deepEqual(JSON.parse(last("/v1/pdf/merge").body), { files: [{ file_id: "file_a" }, { file_id: "file_uploaded" }] });
});

test("an error envelope becomes a typed LowcoApiError", async () => {
  await assert.rejects(client().pdf.rotate({ file: Files.id("file_a"), angle: 45 }), (e) => {
    assert.ok(e instanceof LowcoApiError);
    assert.equal(e.status, 400);
    assert.equal(e.reason, "invalid_param");
    assert.equal(e.param, "angle");
    assert.equal(e.requestId, "req_err");
    assert.equal(e.docUrl, "https://docs.lowco.ai/api/errors#invalid_param");
    return true;
  });
  assert.equal(ERROR_REASONS.invalid_param.status, 400);
  assert.equal(Object.keys(ERROR_REASONS).length, 56);
});

test("Idempotency-Key is sent and a replay is reported", async () => {
  const key = newIdempotencyKey();
  const a = await client().ocr.text({ file: Files.id("file_a") }, { idempotencyKey: key, mode: "async" });
  assert.equal(last("/v1/ocr/text").headers["idempotency-key"], key);
  assert.equal(a.replayed, true);
});

test("GETs retry 429 after Retry-After", async () => {
  const s = await client().settings.get();
  assert.equal(s.environment, "test");
  assert.equal(settingsCalls, 2);
});

test("listAll follows next_cursor", async () => {
  const ids = [];
  for await (const j of client().jobs.listAll({ status: "succeeded" })) ids.push(j.job_id);
  assert.deepEqual(ids, ["j1", "j2", "j3"]);
  assert.equal(last("/v1/jobs").query.cursor, "c2");
});

test("a failed job throws LowcoJobError with its reason; a slow one times out", async () => {
  await assert.rejects(client().jobs.wait("job_bad"), (e) => e instanceof LowcoJobError && e.reason === "file_corrupt" && e.job.status === "failed");
  await assert.rejects(client().jobs.wait("job_slow", { timeoutMs: 50 }), (e) => e instanceof LowcoTimeoutError && e.jobId === "job_slow");
});

test("contentUrl returns the signed link and download fetches it without the key", async () => {
  const lowco = client();
  const link = await lowco.files.contentUrl("file_x");
  assert.equal(link, `${base}/v1/downloads/tok_x`);
  const bytes = await lowco.files.download(link);
  assert.equal(Buffer.from(bytes).toString(), "%PDF-1.7");
  assert.equal(last("/v1/downloads/tok_x").headers.authorization, undefined);
});

test("a missing key is refused before any request", () => {
  const saved = process.env.LOWCO_API_KEY;
  delete process.env.LOWCO_API_KEY;
  assert.throws(() => new LowcoApi({}), (e) => e instanceof LowcoApiError && e.reason === "missing_key");
  process.env.LOWCO_API_KEY = "lc_test_sdk";
  process.env.LOWCO_API_BASE_URL = base;
  assert.equal(new LowcoApi().jobs !== undefined, true);
  delete process.env.LOWCO_API_BASE_URL;
  if (saved === undefined) delete process.env.LOWCO_API_KEY; else process.env.LOWCO_API_KEY = saved;
});

test("webhook signatures: the vectors made by lowco-api core/webhooksig", () => {
  const { vectors } = JSON.parse(readFileSync(new URL("../../../specs/webhook-signature-vectors.json", import.meta.url)));
  assert.equal(vectors.length, 8);
  for (const v of vectors) {
    assert.equal(verifySignature(v.header, v.body, v.secret, { now: v.now }), v.valid, v.name);
    assert.equal(verifySignature(v.header, Buffer.from(v.body), v.secret, { now: v.now }), v.valid, v.name + " (bytes)");
  }
  const ok = vectors[0];
  assert.equal(constructEvent(ok.body, ok.header, ok.secret, { now: ok.now }).type, "job.succeeded");
  assert.throws(() => constructEvent(ok.body + " ", ok.header, ok.secret, { now: ok.now }), /does not match/);
});
