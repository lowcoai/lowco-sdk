import { test } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { defineNode, defineLibrary, collectNodes, NodeError, ValidationError } from "../index.mjs";
import { describe, runNode } from "../testing.mjs";

const echo = defineNode({ key: "echo", name: "Echo", run: (inputs) => inputs });

test("defineNode checks its declaration", () => {
  assert.throws(() => defineNode({ key: "Bad Key", name: "x", run() {} }), /lowercase/);
  assert.throws(() => defineNode({ key: "no_name", run() {} }), /needs a name/);
  assert.throws(() => defineNode({ key: "no_run", name: "x" }), /run\(inputs, ctx\)/);
  assert.throws(() => defineNode({ key: "schema", name: "x", run() {}, output: { type: "object" } }), /outputSchema/);
  assert.throws(() => defineNode({ key: "schema", name: "x", run() {}, outputSchema: [] }), /JSON Schema object/);
  assert.throws(() => defineNode({ key: "inputs", name: "x", run() {}, inputs: {} }), /inputs must be an array/);
});

test("collectNodes finds every export style and refuses duplicate keys", () => {
  const a = defineNode({ key: "a_node", name: "A", run() {} });
  const b = defineNode({ key: "b_node", name: "B", run() {} });
  assert.deepEqual(collectNodes({ default: defineLibrary({ nodes: [a] }), b }).map((n) => n.key), ["a_node", "b_node"]);
  assert.deepEqual(collectNodes({ default: [a, b] }).map((n) => n.key), ["a_node", "b_node"]);
  assert.deepEqual(collectNodes({ default: a, a }).map((n) => n.key), ["a_node"]); // the same node twice is fine
  const a2 = defineNode({ key: "a_node", name: "A again", run() {} });
  assert.throws(() => collectNodes({ a, a2 }), /two nodes use the key "a_node"/);
});

test("describe keeps the output schema next to an output handler", () => {
  const n = defineNode({
    key: "shaped", name: "Shaped",
    outputSchema: { type: "object", properties: { id: { type: "string" } } },
    run: () => ({ raw: 1 }),
    output: (r) => ({ id: String(r.raw) }),
  });
  const [d] = describe(n);
  assert.deepEqual(d.output, { type: "object", properties: { id: { type: "string" } } });
  assert.deepEqual(d.handlers, ["output"]);
});

test("handlers run in order: input, validate, run, output", async () => {
  const order = [];
  const n = defineNode({
    key: "ordered", name: "Ordered",
    input: (i) => { order.push("input"); return { ...i, n: Number(i.n) }; },
    validate: (i) => { order.push("validate"); return i.n > 0 ? undefined : ["n must be positive"]; },
    run: (i, ctx) => { order.push("run"); ctx.log.info("ran", { n: i.n }); return i.n * 2; },
    output: (r, i) => { order.push("output"); return { doubled: r, from: i.n }; },
  });
  const ok = await runNode(n, { n: "21" });
  assert.deepEqual(order, ["input", "validate", "run", "output"]);
  assert.deepEqual(ok.output, { doubled: 42, from: 21 });
  assert.deepEqual(ok.logs, [{ level: "info", message: "ran", fields: { n: 21 } }]);

  const bad = await runNode(n, { n: "0" });
  assert.equal(bad.ok, false);
  assert.deepEqual(bad.error, { kind: "validation", message: "n must be positive", code: "validation", details: { problems: ["n must be positive"] }, retryable: false });
});

test("failures become values: NodeError, ValidationError, ctx.fail and stray throws", async () => {
  const thrower = (fn) => defineNode({ key: "thrower", name: "T", run: fn });
  const nodeErr = await runNode(thrower(() => { throw new NodeError("quota", { code: "rate_limited", retryable: true, details: { left: 0 } }); }), {});
  assert.deepEqual(nodeErr.error, { kind: "node", message: "quota", code: "rate_limited", details: { left: 0 }, retryable: true });
  const valErr = await runNode(thrower(() => { throw new ValidationError("bad", { problems: ["x", "y"] }); }), {});
  assert.deepEqual(valErr.error.details, { problems: ["x", "y"] });
  const failed = await runNode(defineNode({ key: "fails", name: "F", run: (i, ctx) => ctx.fail("nope", { code: "no" }) }), {});
  assert.equal(failed.error.code, "no");
  const stray = await runNode(thrower(() => null.x), {});
  assert.equal(stray.error.kind, "node");
  assert.equal(stray.error.code, "uncaught");
  assert.match(stray.error.details.stack, /TypeError/);
});

test("ctx exposes env and context, frozen", async () => {
  const n = defineNode({
    key: "ctx_node", name: "Ctx",
    run: (i, ctx) => {
      assert.throws(() => { ctx.env.API_KEY = "x"; });
      return { key: ctx.env.API_KEY, exec: ctx.run.executionId, node: ctx.node.key };
    },
  });
  const res = await runNode(n, {}, { env: { API_KEY: "k" }, context: { run: { executionId: "e1" }, node: { key: "ctx_node" } } });
  assert.deepEqual(res.output, { key: "k", exec: "e1", node: "ctx_node" });
});

test("runNode needs options.node when the target has several nodes", async () => {
  const lib = defineLibrary({ nodes: [echo, defineNode({ key: "other", name: "O", run: () => 1 })] });
  await assert.rejects(runNode(lib, {}), /pass options.node/);
  assert.deepEqual((await runNode(lib, { a: 1 }, { node: "echo" })).output, { a: 1 });
  const missing = await runNode(lib, {}, { node: "nope" });
  assert.equal(missing.error.kind, "internal");
});

test("ctx.http with a mock: the request as the relay sees it, and non-2xx throws", async () => {
  const n = defineNode({
    key: "caller", name: "Caller",
    run: async (i, ctx) => {
      const created = await ctx.http.post("https://api.example.test/things", { a: 1 }, { connection: "api", query: { dry: true } });
      const soft = await ctx.http.get("https://api.example.test/missing", { throwOnError: false });
      await ctx.http.get("https://api.example.test/boom");
      return { created: created.json, soft: soft.status };
    },
  });
  const res = await runNode(n, {}, {
    http: (req) => (req.url.endsWith("/things") ? { status: 201, json: { id: 7 } } : req.url.endsWith("/missing") ? { status: 404 } : { status: 500, body: "down" }),
  });
  assert.equal(res.ok, false);
  assert.deepEqual(res.error, { kind: "node", message: "HTTP 500 from GET https://api.example.test/boom", code: "http_status", details: { status: 500, body: "down" }, retryable: true });
  assert.deepEqual(res.requests[0], { method: "POST", url: "https://api.example.test/things", headers: {}, query: { dry: true }, json: { a: 1 }, connection: "api" });
  assert.equal(res.requests.length, 3);
});

test("ctx.http live: real requests, connection stand-ins", async () => {
  let seen;
  const server = http.createServer((req, res) => {
    seen = { url: req.url, auth: req.headers.authorization, method: req.method };
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ ok: true }));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const n = defineNode({ key: "live", name: "Live", run: async (i, ctx) => (await ctx.http.get(`${base}/x`, { connection: "api", query: { q: ["a", "b"] } })).json });
    const res = await runNode(n, {}, { connections: { api: { headers: { authorization: "Bearer local" } } } });
    assert.deepEqual(res.output, { ok: true });
    assert.deepEqual(seen, { url: "/x?q=a&q=b", auth: "Bearer local", method: "GET" });
    const noStandIn = await runNode(n, {});
    assert.equal(noStandIn.error.code, "unknown_connection");
  } finally {
    server.close();
  }
});
