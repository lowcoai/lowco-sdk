// The code-node runtime: what the workflow engine runs inside the sandbox
// (agentx js-executor) for a node library. It is shipped with every run, next
// to the library's own files; the library's nodes see only `inputs` and `ctx`.
//
//   describe  ->  { nodes: [static declaration of each node] }
//   run       ->  { ok: true, output, logs } | { ok: false, error, logs }
//
// A run never throws to the harness: every outcome, including a failure, is a
// value, so the engine can tell a node's own failure (kind "node"/"validation")
// from the sandbox's (a js-executor error).

import http from "node:http";
import { collectNodes, NodeError, ValidationError } from "./index.mjs";

const MAX_LOGS = 200;
const MAX_LOG_CHARS = 4000;
const MAX_ERROR_BODY = 2000;

export function describeLibrary(mod) {
  return {
    nodes: collectNodes(mod).map((n) => ({
      key: n.key,
      name: n.name,
      description: n.description ?? "",
      category: n.category ?? "",
      icon: n.icon ?? "",
      color: n.color ?? "",
      docs: n.docs ?? "",
      inputs: n.inputs ?? [],
      output: n.outputSchema ?? null,
      strictOutput: !!n.strictOutput,
      handlers: ["input", "validate", "output"].filter((h) => typeof n[h] === "function"),
    })),
  };
}

// runNode runs one node's handlers. options.transport replaces how ctx.http
// calls go out (the SDK's local test harness); in the sandbox they go to the
// engine's relay.
export async function runNode(mod, args, options = {}) {
  const logs = [];
  const node = collectNodes(mod).find((n) => n.key === args.node);
  if (!node) {
    return { ok: false, logs, error: { kind: "internal", message: `node "${args.node}" is not exported by the library` } };
  }
  const ctx = makeContext(args.context || {}, logs, options.transport || relayTransport);
  try {
    let inputs = args.inputs ?? {};
    if (node.input) {
      const next = await node.input(inputs, ctx);
      if (next !== undefined) inputs = next;
    }
    if (node.validate) {
      const problems = await node.validate(inputs, ctx);
      const list = typeof problems === "string" ? [problems] : Array.isArray(problems) ? problems.filter(Boolean) : [];
      if (list.length) throw new ValidationError(list.join("; "), { problems: list });
    }
    let result = await node.run(inputs, ctx);
    if (node.output) result = await node.output(result, inputs, ctx);
    return { ok: true, output: result === undefined ? null : result, logs };
  } catch (e) {
    return { ok: false, logs, error: toError(e) };
  }
}

function toError(e) {
  if (e && (e.lowcoKind === "validation" || e.lowcoKind === "node")) {
    return {
      kind: e.lowcoKind,
      message: String(e.message || e.name),
      code: e.code ?? null,
      details: e.lowcoKind === "validation" ? { problems: e.problems ?? [] } : e.details ?? null,
      retryable: !!e.retryable,
    };
  }
  const message = e && e.message ? String(e.message) : String(e);
  return { kind: "node", message, code: "uncaught", details: { name: e && e.name, stack: trimStack(e && e.stack) } };
}

function trimStack(stack) {
  if (!stack) return null;
  return String(stack).split("\n").slice(0, 8).join("\n");
}

function makeContext(c, logs, transport) {
  const log = (level) => (message, fields) => {
    if (logs.length >= MAX_LOGS) return;
    const entry = { level, message: String(message).slice(0, MAX_LOG_CHARS) };
    if (fields !== undefined) entry.fields = fields;
    logs.push(entry);
  };
  return Object.freeze({
    node: Object.freeze({ ...(c.node || {}) }),
    run: Object.freeze({ ...(c.run || {}) }),
    // The org's environment variables, for its own libraries only; a public
    // (platform) library gets none.
    env: Object.freeze({ ...(c.env || {}) }),
    log: Object.freeze({ debug: log("debug"), info: log("info"), warn: log("warn"), error: log("error") }),
    http: makeHttp(transport),
    fail(message, opts) {
      throw new NodeError(message, opts);
    },
  });
}

// ---- outbound HTTP, through the engine's relay ----
//
// The sandbox has no network. The engine passes a relay to the run, which the
// sandbox exposes as a unix socket (LOWCO_SOCKET); the engine checks every
// destination (no private or cluster addresses) and, for `connection`, adds
// the credentials of the connection the workflow author picked for that
// input. Credentials never enter the sandbox.

function relayCall(path, payload) {
  const socketPath = process.env.LOWCO_SOCKET;
  if (!socketPath) {
    return Promise.reject(new NodeError("outbound HTTP is not available in this run", { code: "http_unavailable" }));
  }
  return new Promise((resolve, reject) => {
    const body = Buffer.from(JSON.stringify(payload));
    const req = http.request(
      { socketPath, path, method: "POST", headers: { "content-type": "application/json", "content-length": body.length } },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let data = null;
          try {
            data = JSON.parse(text);
          } catch {
            /* not JSON */
          }
          if (res.statusCode !== 200) {
            const err = (data && data.error) || {};
            reject(new NodeError(err.message || `relay answered ${res.statusCode}`, { code: err.code || "relay_error" }));
            return;
          }
          resolve(data);
        });
      },
    );
    req.on("error", (e) => reject(new NodeError(`relay unreachable: ${e.message}`, { code: "relay_unreachable" })));
    req.end(body);
  });
}

const relayTransport = (call) => relayCall("/http", call);

function makeHttp(transport) {
  const request = async (opts) => {
    if (!opts || !opts.url) throw new TypeError("ctx.http.request needs { url }");
    const method = String(opts.method || "GET").toUpperCase();
    const res = await transport({
      method,
      url: String(opts.url),
      headers: opts.headers || {},
      query: opts.query || {},
      json: opts.json,
      body: opts.body === undefined ? undefined : String(opts.body),
      connection: opts.connection,
      timeoutMs: opts.timeoutMs,
    });
    const out = {
      status: res.status,
      ok: res.status >= 200 && res.status < 300,
      headers: res.headers || {},
      text: res.body ?? "",
      json: res.json ?? null,
    };
    if (opts.throwOnError !== false && !out.ok) {
      throw new NodeError(`HTTP ${out.status} from ${method} ${opts.url}`, {
        code: "http_status",
        details: { status: out.status, body: String(out.text).slice(0, MAX_ERROR_BODY) },
        retryable: out.status >= 500 || out.status === 429,
      });
    }
    return out;
  };
  const verb = (method) => (url, opts = {}) => request({ ...opts, url, method });
  const withJson = (method) => (url, json, opts = {}) => request({ ...opts, url, method, json });
  return Object.freeze({
    request,
    get: verb("GET"),
    delete: verb("DELETE"),
    post: withJson("POST"),
    put: withJson("PUT"),
    patch: withJson("PATCH"),
  });
}
