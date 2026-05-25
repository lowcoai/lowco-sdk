"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/index.ts
var index_exports = {};
__export(index_exports, {
  A2A_ERROR_CODES: () => A2A_ERROR_CODES,
  AgentxClient: () => AgentxClient,
  AgentxError: () => AgentxError,
  DEFAULT_EXECUTOR_API_BASE_PATH: () => DEFAULT_EXECUTOR_API_BASE_PATH,
  DEFAULT_KB_API_BASE_PATH: () => DEFAULT_KB_API_BASE_PATH,
  DEFAULT_MANAGER_API_BASE_PATH: () => DEFAULT_MANAGER_API_BASE_PATH,
  ExecutorClient: () => ExecutorClient,
  HEADER_ORG_ID: () => HEADER_ORG_ID,
  HEADER_USER_ID: () => HEADER_USER_ID,
  JSONRPC_ERROR_CODES: () => JSONRPC_ERROR_CODES,
  KBClient: () => KBClient,
  METHOD_MESSAGE_SEND: () => METHOD_MESSAGE_SEND,
  ManagerClient: () => ManagerClient,
  tryParseMessage: () => tryParseMessage
});
module.exports = __toCommonJS(index_exports);

// src/types.ts
var HEADER_ORG_ID = "X-Org-Id";
var HEADER_USER_ID = "X-User-Id";
var DEFAULT_MANAGER_API_BASE_PATH = "/v1/agentx/manager";
var DEFAULT_KB_API_BASE_PATH = "/v1/agentx/kb";
var DEFAULT_EXECUTOR_API_BASE_PATH = "/v1/agentx/executors";
var METHOD_MESSAGE_SEND = "message/send";
var JSONRPC_ERROR_CODES = {
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603
};
var A2A_ERROR_CODES = {
  TaskNotFound: -32001,
  TaskNotCancelable: -32002,
  PushNotificationNotSupported: -32003,
  UnsupportedOperation: -32004,
  ContentTypeNotSupported: -32005,
  InvalidAgentResponse: -32006
};

// src/errors.ts
var AgentxError = class extends Error {
  statusCode;
  code;
  body;
  constructor(opts) {
    super(opts.message || `agentx: status=${opts.statusCode}`);
    this.name = "AgentxError";
    this.statusCode = opts.statusCode;
    this.code = opts.code;
    this.body = opts.body;
  }
};

// src/transport.ts
var Transport = class {
  fetchFn;
  headers;
  timeoutMs;
  constructor(opts) {
    this.fetchFn = opts.fetch;
    this.headers = opts.headers;
    this.timeoutMs = opts.timeoutMs;
  }
  joinPath(apiBasePath, ...parts) {
    const segs = [apiBasePath.replace(/^\/+|\/+$/g, "")];
    for (const p of parts) segs.push(encodeURIComponent(p.replace(/^\/+|\/+$/g, "")));
    return "/" + segs.join("/");
  }
  listQuery(params) {
    if (!params) return null;
    const q = new URLSearchParams();
    if (params.pageNo !== void 0) q.set("pageNo", String(params.pageNo));
    if (params.size !== void 0) q.set("size", String(params.size));
    if (params.filter !== void 0) q.set("filter", params.filter);
    if (params.sort !== void 0) q.set("sort", params.sort);
    return q;
  }
  /** Send a JSON request and decode (optionally enveloped) JSON response. */
  async request(target, opts) {
    const resp = await this.send(target, opts, "application/json");
    const text = await resp.text();
    if (!resp.ok) {
      throw buildHttpError(resp.status, text);
    }
    if (resp.status === 204 || text.trim().length === 0) {
      return void 0;
    }
    if (opts.enveloped) {
      return decodeEnvelope(text);
    }
    return JSON.parse(text);
  }
  /**
   * Send a request and return the raw Response, without decoding.
   * Used by the executor's SSE stream.
   */
  async sendRaw(target, opts) {
    return this.send(target, opts, opts.accept ?? "application/json", opts.signal);
  }
  async send(target, opts, accept, signal) {
    const baseURL = target.baseURL.replace(/\/+$/, "");
    const url = new URL(baseURL + opts.path);
    if (opts.query) {
      opts.query.forEach((v, k) => url.searchParams.append(k, v));
    }
    const headers = {
      Accept: accept,
      ...this.headers
    };
    let body;
    if (opts.body !== void 0 && opts.body !== null) {
      body = JSON.stringify(opts.body);
      headers["Content-Type"] = "application/json";
    }
    let controller = null;
    let timer = null;
    let effectiveSignal = signal;
    if (!signal && this.timeoutMs > 0) {
      controller = new AbortController();
      timer = setTimeout(() => controller.abort(), this.timeoutMs);
      effectiveSignal = controller.signal;
    }
    try {
      return await this.fetchFn(url.toString(), {
        method: opts.method,
        headers,
        body,
        signal: effectiveSignal
      });
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
};
function buildHttpError(status, text) {
  let message = text.trim();
  let code;
  try {
    const parsed = JSON.parse(text);
    if (parsed.error?.message?.trim()) {
      message = parsed.error.message;
      code = parsed.error.code;
    } else if (parsed.message) {
      message = parsed.message;
    }
  } catch {
  }
  return new AgentxError({ statusCode: status, message, code, body: text });
}
function decodeEnvelope(text) {
  let env;
  try {
    env = JSON.parse(text);
  } catch {
    return JSON.parse(text);
  }
  if (env && typeof env === "object" && "data" in env) {
    if (env.data === void 0 || env.data === null) return void 0;
    return env.data;
  }
  return env;
}

// src/executor.ts
function tryParseMessage(ev) {
  try {
    return JSON.parse(ev.data);
  } catch {
    return null;
  }
}
var ExecutorClient = class {
  constructor(transport, target) {
    this.transport = transport;
    this.target = target;
  }
  transport;
  target;
  path(...parts) {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }
  // --- Health ------------------------------------------------------------
  async health() {
    const resp = await this.transport.sendRaw(this.target, {
      method: "GET",
      path: "/health"
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw buildHttpError(resp.status, text);
    }
  }
  // --- Synchronous send -------------------------------------------------
  /**
   * Performs a synchronous `message/send` call. The JSON-RPC id doubles as
   * the target agent identifier (matching the service convention).
   */
  async sendMessage(agentId, params) {
    const req = {
      jsonrpc: "2.0",
      method: METHOD_MESSAGE_SEND,
      params,
      id: agentId
    };
    const resp = await this.transport.sendRaw(this.target, {
      method: "POST",
      path: this.path("execute"),
      body: req
    });
    const text = await resp.text();
    if (!resp.ok) {
      throw buildHttpError(resp.status, text);
    }
    if (resp.status === 204 || text.trim().length === 0) {
      return { jsonrpc: "2.0", id: agentId };
    }
    return JSON.parse(text);
  }
  // --- Streaming send ---------------------------------------------------
  /**
   * Streams a `message/send` call, yielding one [StreamEvent] per SSE event
   * the server emits. Pass an AbortSignal to cancel mid-stream.
   *
   * ```ts
   * for await (const ev of client.Executor.streamMessage(agentId, params)) {
   *   const msg = tryParseMessage(ev);
   *   if (msg) console.log("delta:", msg);
   *   else console.log("raw:", ev.data);
   * }
   * ```
   */
  async *streamMessage(agentId, params, options = {}) {
    const req = {
      jsonrpc: "2.0",
      method: METHOD_MESSAGE_SEND,
      params,
      id: agentId
    };
    const resp = await this.transport.sendRaw(this.target, {
      method: "POST",
      path: this.path("execute"),
      body: req,
      accept: "text/event-stream",
      signal: options.signal
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw buildHttpError(resp.status, text);
    }
    if (!resp.body) {
      throw new AgentxError({
        statusCode: resp.status,
        message: "streamMessage: response has no body",
        body: ""
      });
    }
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          const trailing = collectDataLines(buffer);
          if (trailing !== null) yield { data: trailing };
          return;
        }
        buffer += decoder.decode(value, { stream: true });
        let idx;
        while ((idx = indexOfEventBoundary(buffer)) !== -1) {
          const rawEvent = buffer.slice(0, idx);
          buffer = buffer.slice(idx).replace(/^(\r?\n){2}/, "");
          const data = collectDataLines(rawEvent);
          if (data !== null) yield { data };
        }
      }
    } finally {
      try {
        reader.releaseLock();
      } catch {
      }
    }
  }
};
function indexOfEventBoundary(buf) {
  const a = buf.indexOf("\n\n");
  const b = buf.indexOf("\r\n\r\n");
  if (a === -1) return b;
  if (b === -1) return a;
  return Math.min(a, b);
}
function collectDataLines(eventChunk) {
  const lines = eventChunk.split(/\r?\n/);
  const data = [];
  for (const line of lines) {
    if (line.startsWith("data:")) {
      const stripped = line.slice(5).replace(/^\s/, "");
      data.push(stripped);
    }
  }
  if (data.length === 0) return null;
  return data.join("\n");
}

// src/kb.ts
var KBClient = class {
  constructor(transport, target) {
    this.transport = transport;
    this.target = target;
  }
  transport;
  target;
  path(...parts) {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }
  // --- Health ------------------------------------------------------------
  async health() {
    await this.transport.request(this.target, {
      method: "GET",
      path: "/health",
      enveloped: false
    });
  }
  // --- Knowledge bases ---------------------------------------------------
  listKnowledgeBases(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  createKnowledgeBase(kb) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("knowledges"),
      body: kb,
      enveloped: true
    });
  }
  getKnowledgeBase(id) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges", id),
      enveloped: true
    });
  }
  updateKnowledgeBase(id, kb) {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("knowledges", id),
      body: kb,
      enveloped: true
    });
  }
  /** The /knowledges/count endpoint returns a raw integer, not an envelope. */
  getKnowledgeBaseCount(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges", "count"),
      query: this.transport.listQuery(params),
      enveloped: false
    });
  }
  // --- Datasets ----------------------------------------------------------
  listDatasets(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  createDataset(dataset) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("datasets"),
      body: dataset,
      enveloped: true
    });
  }
  getDataset(id) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets", id),
      enveloped: true
    });
  }
  updateDataset(id, dataset) {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("datasets", id),
      body: dataset,
      enveloped: true
    });
  }
  async deleteDataset(id) {
    await this.transport.request(this.target, {
      method: "DELETE",
      path: this.path("datasets", id),
      enveloped: false
    });
  }
  /** The /datasets/count endpoint returns a raw integer, not an envelope. */
  getDatasetCount(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets", "count"),
      query: this.transport.listQuery(params),
      enveloped: false
    });
  }
  // --- Embeddings --------------------------------------------------------
  /** Persists embeddings into the vector store; returns the service's success message. */
  storeEmbeddings(req) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("embeddings"),
      body: req,
      enveloped: true
    });
  }
};

// src/manager.ts
var ManagerClient = class {
  constructor(transport, target) {
    this.transport = transport;
    this.target = target;
  }
  transport;
  target;
  path(...parts) {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }
  // --- Health ------------------------------------------------------------
  async health() {
    await this.transport.request(this.target, {
      method: "GET",
      path: "/health",
      enveloped: false
    });
  }
  // --- Agents ------------------------------------------------------------
  listAgents(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  getAgent(id) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", id),
      enveloped: true
    });
  }
  createAgent(agent) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("agents"),
      body: agent,
      enveloped: true
    });
  }
  updateAgent(id, agent) {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("agents", id),
      body: agent,
      enveloped: true
    });
  }
  patchAgent(id, patch) {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("agents", id),
      body: patch,
      enveloped: true
    });
  }
  /** The /agents/count endpoint returns a raw integer, not an envelope. */
  getAgentCount(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "count"),
      query: this.transport.listQuery(params),
      enveloped: false
    });
  }
  async deleteAgent(id) {
    await this.transport.request(this.target, {
      method: "DELETE",
      path: this.path("agents", id),
      enveloped: false
    });
  }
  async bulkDeleteAgents(ids) {
    await this.transport.request(this.target, {
      method: "POST",
      path: this.path("agents", "bulk-delete"),
      body: { ids },
      enveloped: false
    });
  }
  getAgentVersions(id, params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", id, "versions"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  // --- Published agents -------------------------------------------------
  publishAgent(agentId, req) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("agents", agentId, "publish"),
      body: req,
      enveloped: true
    });
  }
  getPublishedAgent(id) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "published", id),
      enveloped: true
    });
  }
  updatePublishedAgent(id, req) {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("agents", "published", id),
      body: req,
      enveloped: true
    });
  }
  async deletePublishedAgent(id) {
    await this.transport.request(this.target, {
      method: "DELETE",
      path: this.path("agents", "published", id),
      enveloped: false
    });
  }
  listPublishedAgents(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("agents", "published"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  // --- LLM models -------------------------------------------------------
  createModel(model) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("models"),
      body: model,
      enveloped: true
    });
  }
  getModel(id) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("models", id),
      enveloped: true
    });
  }
  updateModel(id, model) {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("models", id),
      body: model,
      enveloped: true
    });
  }
  listModels(params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("models"),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  async deleteModel(id) {
    await this.transport.request(this.target, {
      method: "DELETE",
      path: this.path("models", id),
      enveloped: false
    });
  }
  enableModel(id, properties) {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("models", id, "enable"),
      body: { properties },
      enveloped: true
    });
  }
  disableModel(id) {
    return this.transport.request(this.target, {
      method: "PATCH",
      path: this.path("models", id, "disable"),
      enveloped: true
    });
  }
  // --- Conversations ----------------------------------------------------
  listConversationsByAgent(agentId, params) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("conversations", agentId),
      query: this.transport.listQuery(params),
      enveloped: true
    });
  }
  createConversation(agentId) {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("conversations"),
      body: { agentId },
      enveloped: true
    });
  }
  async deleteConversation(id) {
    await this.transport.request(this.target, {
      method: "DELETE",
      path: this.path("conversations", id),
      enveloped: true
    });
  }
  getConversationMessages(conversationId) {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("conversations", conversationId, "messages"),
      enveloped: true
    });
  }
};

// src/client.ts
var AgentxClient = class {
  headers;
  /** Agent-manager sub-client. */
  Manager;
  /** Agent-kb (knowledge-base) sub-client. */
  KB;
  /** Agent-executor sub-client. */
  Executor;
  constructor(opts) {
    const managerURL = opts.managerURL ?? opts.baseURL;
    const kbURL = opts.kbURL ?? opts.baseURL;
    const executorURL = opts.executorURL ?? opts.baseURL;
    if (!managerURL || !kbURL || !executorURL) {
      throw new Error(
        "AgentxClient: every service needs a base URL \u2013 set baseURL or managerURL/kbURL/executorURL"
      );
    }
    this.headers = { ...opts.defaultHeaders ?? {} };
    if (opts.orgId) this.headers[HEADER_ORG_ID] = opts.orgId;
    if (opts.userId) this.headers[HEADER_USER_ID] = opts.userId;
    const transport = new Transport({
      fetch: opts.fetch ?? fetch,
      headers: this.headers,
      timeoutMs: opts.timeoutMs ?? 3e4
    });
    const managerTarget = {
      baseURL: managerURL,
      apiBasePath: normalizePrefix(opts.managerApiBasePath ?? DEFAULT_MANAGER_API_BASE_PATH)
    };
    const kbTarget = {
      baseURL: kbURL,
      apiBasePath: normalizePrefix(opts.kbApiBasePath ?? DEFAULT_KB_API_BASE_PATH)
    };
    const executorTarget = {
      baseURL: executorURL,
      apiBasePath: normalizePrefix(opts.executorApiBasePath ?? DEFAULT_EXECUTOR_API_BASE_PATH)
    };
    this.Manager = new ManagerClient(transport, managerTarget);
    this.KB = new KBClient(transport, kbTarget);
    this.Executor = new ExecutorClient(transport, executorTarget);
  }
  setOrgId(orgId) {
    if (orgId) this.headers[HEADER_ORG_ID] = orgId;
    else delete this.headers[HEADER_ORG_ID];
  }
  setUserId(userId) {
    if (userId) this.headers[HEADER_USER_ID] = userId;
    else delete this.headers[HEADER_USER_ID];
  }
  /** Sets / overwrites an arbitrary default header. Pass null to delete. */
  setHeader(key, value) {
    if (value === null) delete this.headers[key];
    else this.headers[key] = value;
  }
};
function normalizePrefix(p) {
  return "/" + p.replace(/^\/+|\/+$/g, "");
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  A2A_ERROR_CODES,
  AgentxClient,
  AgentxError,
  DEFAULT_EXECUTOR_API_BASE_PATH,
  DEFAULT_KB_API_BASE_PATH,
  DEFAULT_MANAGER_API_BASE_PATH,
  ExecutorClient,
  HEADER_ORG_ID,
  HEADER_USER_ID,
  JSONRPC_ERROR_CODES,
  KBClient,
  METHOD_MESSAGE_SEND,
  ManagerClient,
  tryParseMessage
});
