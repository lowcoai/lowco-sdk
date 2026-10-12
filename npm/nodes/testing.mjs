// @lowcoai/nodes/testing — run nodes locally, through the same pipeline the
// workflow engine runs in its sandbox (input -> validate -> run -> output).
//
//   import { runNode } from "@lowcoai/nodes/testing";
//   const res = await runNode(createCustomer, { email: "ada@example.com" }, {
//     http: (req) => ({ status: 200, json: { id: "cus_1" } }),
//   });
//   assert.equal(res.output.id, "cus_1");
//
// Differences from a real run, by design: HTTP goes straight out (or to your
// mock) instead of through the engine's relay, so private addresses are not
// refused here, and a connection is whatever headers you hand in.

import { describeLibrary, runNode as runPipeline } from "./runtime.mjs";
import { NodeError, collectNodes, isLibrary, isNode } from "./index.mjs";

/** Accept a node, a library, an array of nodes or a module namespace. */
function asModule(target) {
  if (isNode(target) || isLibrary(target) || Array.isArray(target)) return { default: target };
  return target || {};
}

/** The declarations the engine would read from a library (what a push publishes). */
export function describe(target) {
  return describeLibrary(asModule(target)).nodes;
}

/**
 * Run one node.
 *
 * options.node         the node's key, when target holds several
 * options.env          ctx.env (the org's environment variables)
 * options.context      { node, run } for ctx.node / ctx.run
 * options.http         a mock: (request) => response | Promise<response>, where
 *                      response is { status?, json?, body?, headers? }; or
 *                      "live" (the default) to make real requests
 * options.connections  for live requests, the stand-in for each connection
 *                      input: { [inputName]: { headers: {...} } }
 *
 * Resolves to { ok, output, error, logs, requests }; requests are the calls
 * ctx.http made, as the engine's relay would have received them.
 */
export async function runNode(target, inputs = {}, options = {}) {
  const mod = asModule(target);
  let key = options.node;
  if (!key) {
    const nodes = collectNodes(mod);
    if (nodes.length !== 1) {
      throw new TypeError(`pass options.node: the target has ${nodes.length} nodes (${nodes.map((n) => n.key).join(", ")})`);
    }
    key = nodes[0].key;
  }
  const requests = [];
  const send = typeof options.http === "function" ? mockTransport(options.http) : liveTransport(options.connections || {});
  const transport = async (call) => {
    const req = clean(call);
    if (req.json !== undefined && req.body !== undefined) {
      throw new NodeError("send either json or body, not both", { code: "http_invalid" });
    }
    requests.push(req);
    return send(req);
  };
  const res = await runPipeline(mod, { mode: "run", node: key, inputs, context: { ...(options.context || {}), env: options.env || {} } }, { transport });
  return { ...res, output: res.ok ? res.output : undefined, error: res.ok ? undefined : res.error, requests };
}

function clean(call) {
  const req = {};
  for (const [k, v] of Object.entries(call)) if (v !== undefined) req[k] = v;
  return req;
}

function mockTransport(fn) {
  return async (req) => {
    const r = (await fn(req)) || {};
    const json = r.json === undefined ? null : r.json;
    const body = r.body !== undefined ? String(r.body) : json !== null ? JSON.stringify(json) : "";
    return { status: r.status ?? 200, headers: lower(r.headers || {}), body, json };
  };
}

function liveTransport(connections) {
  return async (req) => {
    const url = new URL(req.url);
    for (const [k, v] of Object.entries(req.query || {})) {
      if (v === null || v === undefined) continue;
      if (Array.isArray(v)) v.forEach((x) => url.searchParams.append(k, String(x)));
      else url.searchParams.set(k, String(v));
    }
    const headers = { ...(req.headers || {}) };
    if (req.connection) {
      const c = connections[req.connection];
      if (!c) {
        throw new NodeError(
          `no local stand-in for connection "${req.connection}": pass connections: { ${req.connection}: { headers: { ... } } }`,
          { code: "unknown_connection" },
        );
      }
      Object.assign(headers, c.headers || {});
    }
    let body;
    if (req.json !== undefined) {
      body = JSON.stringify(req.json);
      if (!Object.keys(headers).some((h) => h.toLowerCase() === "content-type")) headers["content-type"] = "application/json";
    } else if (req.body !== undefined) {
      body = req.body;
    }
    let res;
    try {
      res = await fetch(url, { method: req.method, headers, body, signal: AbortSignal.timeout(req.timeoutMs || 30000) });
    } catch (e) {
      throw new NodeError(`${req.method} ${req.url}: ${e.message}`, { code: e.name === "TimeoutError" ? "http_timeout" : "http_transport" });
    }
    const text = await res.text();
    let json = null;
    if ((res.headers.get("content-type") || "").includes("json") && text) {
      try {
        json = JSON.parse(text);
      } catch {
        /* not JSON after all */
      }
    }
    return { status: res.status, headers: Object.fromEntries(res.headers), body: text, json };
  };
}

function lower(h) {
  return Object.fromEntries(Object.entries(h).map(([k, v]) => [k.toLowerCase(), String(v)]));
}
