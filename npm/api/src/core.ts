import { readFile } from "node:fs/promises";
import { basename } from "node:path";
import type { ErrorDetail, ErrorReason, Job } from "./generated.js";

/** The API host every request goes to unless `baseUrl` says otherwise. */
export const DEFAULT_BASE_URL = "https://api.lowco.ai";

/** This SDK's version; its major and minor follow the API document it was generated from. */
export const SDK_VERSION = "1.1.0";

const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_WAIT_MS = 300_000;

/** Thrown for every failed call: an error envelope, a network failure, a timeout or invalid input. */
export class LowcoApiError extends Error {
  /** HTTP status, or `0` when no response was received. */
  readonly status: number;
  /** The stable error code (`error.reason`): branch on this, not on `message`. */
  readonly reason: ErrorReason | (string & {});
  /** The parameter at fault. */
  readonly param?: string;
  /** Each failing item, for validation errors. */
  readonly details?: ErrorDetail[];
  /** Quote this to support. */
  readonly requestId?: string;
  /** The reason's entry on docs.lowco.ai/api/errors. */
  readonly docUrl?: string;
  /** Whether the same request may succeed later. */
  readonly retryable?: boolean;
  /** Seconds to wait before retrying (Retry-After), when the API said. */
  readonly retryAfter?: number;
  /** The parsed error body (JSON, else text), or null. */
  readonly payload: unknown;

  constructor(message: string, init: { status: number; reason: string; param?: string; details?: ErrorDetail[]; requestId?: string; docUrl?: string; retryable?: boolean; retryAfter?: number; payload?: unknown; cause?: unknown }) {
    super(message, init.cause === undefined ? undefined : { cause: init.cause });
    this.name = "LowcoApiError";
    this.status = init.status;
    this.reason = init.reason;
    this.param = init.param;
    this.details = init.details;
    this.requestId = init.requestId;
    this.docUrl = init.docUrl;
    this.retryable = init.retryable;
    this.retryAfter = init.retryAfter;
    this.payload = init.payload ?? null;
  }
}

/** Thrown by `jobs.wait` when a job failed or was cancelled; `job` is its last state. */
export class LowcoJobError extends LowcoApiError {
  readonly job: Job;
  constructor(message: string, job: Job, init: ConstructorParameters<typeof LowcoApiError>[1]) {
    super(message, init);
    this.name = "LowcoJobError";
    this.job = job;
  }
}

/** Thrown by `jobs.wait` when the job is still running at the timeout. */
export class LowcoTimeoutError extends Error {
  readonly jobId: string;
  constructor(jobId: string, ms: number) {
    super(`Job ${jobId} did not finish within ${ms} ms`);
    this.name = "LowcoTimeoutError";
    this.jobId = jobId;
  }
}

export interface ClientOptions {
  /** `lc_live_…` or `lc_test_…`; the key picks the environment. Defaults to the LOWCO_API_KEY environment variable. */
  apiKey?: string;
  /** Defaults to the LOWCO_API_BASE_URL environment variable, else https://api.lowco.ai. */
  baseUrl?: string;
  /** Per-request timeout (default 60 s). */
  timeoutMs?: number;
  /** Retries of retryable failures (429, 503, network) for requests safe to repeat: GETs and calls with an Idempotency-Key. Default 2. */
  maxRetries?: number;
  /** A fetch implementation (default the global fetch, Node 18+). */
  fetch?: typeof fetch;
}

export interface RequestOptions {
  /** Your own request id, echoed in X-Request-Id and the request log. */
  requestId?: string;
  /** Make a submission safe to retry for 24 hours (see newIdempotencyKey). */
  idempotencyKey?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

export interface CallOptions extends RequestOptions {
  /** `async` always answers 202 with a job. */
  mode?: "sync" | "async";
  /** The output's own type (`application/pdf`, `image/png`, `image/svg+xml`) to receive the single output file itself in `bytes`. */
  accept?: string;
}

export interface WaitOptions {
  /** Give up after this long (default 5 minutes). */
  timeoutMs?: number;
  /** The longest pause between polls (default 10 s). */
  maxIntervalMs?: number;
  signal?: AbortSignal;
}

/** An operation's answer: the result inline (200), a job (202), or the output file's bytes. */
export interface Answer<T> {
  status: number;
  /** The result, when the operation finished in the request. */
  data?: T;
  /** The job, when the operation was accepted as one (status 202). */
  job?: Job;
  /** The output file, when `accept` asked for its type. */
  bytes?: Uint8Array;
  contentType?: string;
  requestId?: string;
  /** True when an Idempotency-Key replayed an earlier submission. */
  replayed: boolean;
  /** Credits this call consumed (live, metered calls). */
  creditsUsed?: string;
}

/** A file input: build one with the `Files` helpers, or pass bytes or a Blob. */
export type FileInput = FileRef | Uint8Array | ArrayBuffer | Blob;

/** One file input, local (sent as a multipart part) or remote (sent by reference). */
export type FileRef =
  | { kind: "path"; path: string; filename?: string; mimeType?: string; password?: string }
  | { kind: "bytes"; data: Uint8Array | ArrayBuffer | Blob; filename?: string; mimeType?: string; password?: string }
  | { kind: "stream"; stream: AsyncIterable<Uint8Array> | ReadableStream<Uint8Array>; filename?: string; mimeType?: string; password?: string }
  | { kind: "url"; url: string; password?: string }
  | { kind: "id"; fileId: string; password?: string }
  | { kind: "base64"; data: string; filename?: string; password?: string };

interface FileSpec {
  input: string;
  extra: string[];
}

type Json = Record<string, unknown>;

interface Raw {
  status: number;
  headers: Headers;
  body: unknown;
  bytes?: Uint8Array;
  contentType: string;
}

const TERMINAL = new Set(["succeeded", "failed", "cancelled"]);

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(t);
      reject(signal.reason);
    }, { once: true });
  });
}

function normalise(input: FileInput): FileRef {
  if (input instanceof Uint8Array || input instanceof ArrayBuffer || (typeof Blob !== "undefined" && input instanceof Blob)) {
    return { kind: "bytes", data: input };
  }
  return input as FileRef;
}

const isLocal = (f: FileRef) => f.kind === "path" || f.kind === "bytes" || f.kind === "stream";

async function toBlob(f: FileRef): Promise<{ blob: Blob; filename: string }> {
  switch (f.kind) {
    case "path": {
      const data = await readFile(f.path);
      return { blob: new Blob([data], { type: f.mimeType ?? "" }), filename: f.filename ?? basename(f.path) };
    }
    case "bytes": {
      const blob = f.data instanceof Blob ? f.data : new Blob([(f.data instanceof ArrayBuffer ? new Uint8Array(f.data) : f.data) as BlobPart], { type: f.mimeType ?? "" });
      const name = f.filename ?? ((typeof File !== "undefined" && f.data instanceof File) ? f.data.name : "file");
      return { blob, filename: name };
    }
    case "stream": {
      const chunks: Uint8Array[] = [];
      for await (const chunk of f.stream as AsyncIterable<Uint8Array>) chunks.push(chunk);
      return { blob: new Blob(chunks as BlobPart[], { type: f.mimeType ?? "" }), filename: f.filename ?? "file" };
    }
  }
  throw new LowcoApiError(`A ${f.kind} input is not local`, { status: 0, reason: "invalid_param" });
}

function reference(f: FileRef): Json {
  const out: Json = {};
  switch (f.kind) {
    case "url":
      out.file_url = f.url;
      break;
    case "id":
      out.file_id = f.fileId;
      break;
    case "base64":
      out.file_base64 = f.data;
      if (f.filename) out.filename = f.filename;
      break;
    default:
      throw new LowcoApiError(`A ${f.kind} input must be uploaded`, { status: 0, reason: "invalid_param" });
  }
  if (f.password) out.password = f.password;
  return out;
}

/** The transport every generated method calls. */
export class Core {
  readonly baseUrl: string;
  private readonly apiKey: string;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly fetchImpl: typeof fetch;

  constructor(options: ClientOptions = {}) {
    const envVars = typeof process !== "undefined" ? process.env : {};
    const apiKey = options.apiKey ?? envVars.LOWCO_API_KEY;
    if (!apiKey) {
      throw new LowcoApiError("apiKey is required (lc_live_… or lc_test_…): pass it or set LOWCO_API_KEY", { status: 0, reason: "missing_key" });
    }
    this.apiKey = apiKey;
    this.baseUrl = (options.baseUrl ?? envVars.LOWCO_API_BASE_URL ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxRetries = options.maxRetries ?? 2;
    const f = options.fetch ?? globalThis.fetch;
    if (!f) throw new LowcoApiError("No fetch implementation: use Node 18+ or pass options.fetch", { status: 0, reason: "invalid_param" });
    this.fetchImpl = f.bind(globalThis);
  }

  private url(path: string, query?: Json): string {
    const u = new URL(path.startsWith("http") ? path : this.baseUrl + path);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v === undefined || v === null) continue;
      u.searchParams.set(k, String(v));
    }
    return u.toString();
  }

  private async send(method: string, url: string, init: { body?: BodyInit; headers?: Record<string, string>; auth?: boolean; redirect?: RequestRedirect }, options?: RequestOptions, retrySafe = method === "GET"): Promise<Raw> {
    const headers: Record<string, string> = { "X-Client-User-Agent": `lowcoai-api-node/${SDK_VERSION}`, ...init.headers };
    if (init.auth !== false) headers.Authorization = `Bearer ${this.apiKey}`;
    if (options?.requestId) headers["X-Request-Id"] = options.requestId;
    if (options?.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;
    const safe = retrySafe || !!options?.idempotencyKey;
    for (let attempt = 0; ; attempt++) {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(new Error("timeout")), options?.timeoutMs ?? this.timeoutMs);
      const onAbort = () => ctl.abort(options?.signal?.reason);
      options?.signal?.addEventListener("abort", onAbort, { once: true });
      let res: Response;
      try {
        res = await this.fetchImpl(url, { method, headers, body: init.body, signal: ctl.signal, redirect: init.redirect });
      } catch (err) {
        clearTimeout(timer);
        options?.signal?.removeEventListener("abort", onAbort);
        if (options?.signal?.aborted) throw err;
        if (safe && attempt < this.maxRetries) {
          await sleep(500 * 2 ** attempt);
          continue;
        }
        throw new LowcoApiError(ctl.signal.aborted ? `Request timed out: ${method} ${url}` : `Network error: ${(err as Error).message}`, { status: 0, reason: "service_unavailable", cause: err, retryable: true });
      }
      clearTimeout(timer);
      options?.signal?.removeEventListener("abort", onAbort);
      const contentType = res.headers.get("content-type") ?? "";
      let body: unknown = null;
      let bytes: Uint8Array | undefined;
      if (res.status >= 300 && res.status < 400) {
        // a redirect asked not to be followed: the Location is the answer
      } else if (contentType.includes("json")) {
        const text = await res.text();
        try {
          body = text ? JSON.parse(text) : null;
        } catch {
          body = text;
        }
      } else {
        bytes = new Uint8Array(await res.arrayBuffer());
      }
      if (res.status >= 400) {
        const err = this.error(res, body, bytes);
        if (safe && attempt < this.maxRetries && (res.status === 429 || res.status === 503)) {
          await sleep(Math.min((err.retryAfter ?? 1) * 1000, 30_000), options?.signal);
          continue;
        }
        throw err;
      }
      return { status: res.status, headers: res.headers, body, bytes, contentType };
    }
  }

  private error(res: Response, body: unknown, bytes?: Uint8Array): LowcoApiError {
    const retryAfterHeader = res.headers.get("retry-after");
    const retryAfter = retryAfterHeader && /^\d+$/.test(retryAfterHeader) ? Number(retryAfterHeader) : undefined;
    const e = (body as { error?: Record<string, unknown> } | null)?.error;
    const requestId = (e?.request_id as string | undefined) ?? res.headers.get("x-request-id") ?? undefined;
    if (e && typeof e === "object") {
      return new LowcoApiError(String(e.message ?? `Request failed with status ${res.status}`), {
        status: res.status, reason: String(e.reason ?? "internal_error"), param: e.param as string | undefined,
        details: e.details as ErrorDetail[] | undefined, requestId, docUrl: e.doc_url as string | undefined,
        retryable: e.retryable as boolean | undefined, retryAfter, payload: body,
      });
    }
    const text = typeof body === "string" ? body : bytes ? new TextDecoder().decode(bytes) : "";
    return new LowcoApiError(text || `Request failed with status ${res.status}`, { status: res.status, reason: res.status >= 500 ? "internal_error" : "invalid_param", requestId, retryAfter, payload: body ?? text });
  }

  private data<T>(raw: Raw): T {
    const env = raw.body as { status?: number; data?: T } | null;
    if (!env || env.status !== 1) {
      throw new LowcoApiError("The API answered without a success envelope", { status: raw.status, reason: "internal_error", payload: raw.body });
    }
    return env.data as T;
  }

  /** A resource call: the envelope's data. */
  async call<T>(method: string, path: string, input: { query?: Json; json?: unknown }, options?: RequestOptions): Promise<T> {
    const init: { body?: BodyInit; headers?: Record<string, string> } = {};
    if (input.json !== undefined) {
      init.body = JSON.stringify(input.json);
      init.headers = { "Content-Type": "application/json" };
    }
    return this.data<T>(await this.send(method, this.url(path, input.query), init, options));
  }

  /** POST /v1/files and the like: one multipart file. */
  async upload<T>(path: string, file: FileInput, options?: RequestOptions): Promise<T> {
    const f = normalise(file);
    if (!isLocal(f)) throw new LowcoApiError("upload takes a local file (path, bytes or stream)", { status: 0, reason: "invalid_param", param: "file" });
    const form = new FormData();
    const { blob, filename } = await toBlob(f);
    form.append("file", blob, filename);
    if (f.password) form.append("password", f.password);
    return this.data<T>(await this.send("POST", this.url(path), { body: form }, options));
  }

  /** A route answering 307: the Location (a signed link). */
  async redirect(path: string, options?: RequestOptions): Promise<string> {
    const raw = await this.send("GET", this.url(path), { redirect: "manual" }, options);
    const loc = raw.headers.get("location");
    if (!loc) throw new LowcoApiError("The API answered without a Location", { status: raw.status, reason: "internal_error" });
    return loc;
  }

  /** Downloads a signed link (no API key is sent). */
  async download(url: string, options?: RequestOptions): Promise<Uint8Array> {
    const raw = await this.send("GET", url, { auth: false }, options);
    return raw.bytes ?? new TextEncoder().encode(typeof raw.body === "string" ? raw.body : JSON.stringify(raw.body));
  }

  /** An operation call: picks JSON or multipart from the file inputs. */
  async operation<T>(path: string, params: Json, spec: FileSpec, options?: CallOptions): Promise<Answer<T>> {
    const rest: Json = { ...params };
    const named: Array<{ field: string; ref: FileRef }> = [];
    let many: FileRef[] | undefined;
    if (spec.input === "file") {
      if (rest.file === undefined) throw new LowcoApiError("file is required", { status: 0, reason: "missing_param", param: "file" });
      named.push({ field: "file", ref: normalise(rest.file as FileInput) });
      delete rest.file;
    } else if (spec.input === "files") {
      if (!Array.isArray(rest.files) || rest.files.length === 0) throw new LowcoApiError("files is required", { status: 0, reason: "missing_param", param: "files" });
      many = (rest.files as FileInput[]).map(normalise);
      delete rest.files;
    }
    for (const x of spec.extra) {
      if (rest[x] !== undefined) {
        named.push({ field: x, ref: normalise(rest[x] as FileInput) });
        delete rest[x];
      }
    }
    const all = [...named.map((n) => n.ref), ...(many ?? [])];
    const local = all.filter(isLocal).length;
    // Mixed local and remote inputs: upload the local ones first.
    if (local > 0 && local < all.length) {
      const up = async (ref: FileRef): Promise<FileRef> => {
        if (!isLocal(ref)) return ref;
        const stored = await this.upload<{ file_id: string }>("/v1/files", ref, { signal: options?.signal });
        return { kind: "id", fileId: stored.file_id, password: ref.password };
      };
      for (const n of named) n.ref = await up(n.ref);
      if (many) many = await Promise.all(many.map(up));
    }
    const multipart = local > 0 && local === all.length;
    const headers: Record<string, string> = {};
    if (options?.accept) headers.Accept = options.accept;
    let body: BodyInit;
    if (multipart) {
      const form = new FormData();
      for (const n of named) {
        const { blob, filename } = await toBlob(n.ref);
        form.append(n.field, blob, filename);
        if (n.field === "file" && n.ref.password) form.append("password", n.ref.password);
      }
      for (const ref of many ?? []) {
        const { blob, filename } = await toBlob(ref);
        form.append("files[]", blob, filename);
      }
      if (rest.callback_url !== undefined) {
        form.append("callback_url", String(rest.callback_url));
        delete rest.callback_url;
      }
      form.append("options", JSON.stringify(rest));
      body = form;
    } else {
      const json: Json = { ...rest };
      for (const n of named) {
        if (n.field === "file") Object.assign(json, reference(n.ref));
        else json[n.field] = reference(n.ref);
      }
      if (many) json.files = many.map(reference);
      body = JSON.stringify(json);
      headers["Content-Type"] = "application/json";
    }
    const raw = await this.send("POST", this.url(path, options?.mode ? { mode: options.mode } : undefined), { body, headers }, options, false);
    const answer: Answer<T> = {
      status: raw.status,
      requestId: raw.headers.get("x-request-id") ?? undefined,
      replayed: raw.headers.get("idempotent-replayed") === "true",
      creditsUsed: raw.headers.get("x-lowco-credits-used") ?? undefined,
    };
    if (raw.bytes) {
      answer.bytes = raw.bytes;
      answer.contentType = raw.contentType;
    } else if (raw.status === 202) {
      answer.job = this.data<Job>(raw);
    } else {
      answer.data = this.data<T>(raw);
    }
    return answer;
  }

  /** Every item of a list route, following next_cursor. */
  async *paginate<T>(path: string, query?: Json, options?: RequestOptions): AsyncGenerator<T> {
    let cursor: string | null | undefined;
    do {
      const page = await this.call<{ items: T[]; next_cursor: string | null }>("GET", path, { query: { ...query, cursor: cursor ?? undefined } }, options);
      for (const item of page.items) yield item;
      cursor = page.next_cursor;
    } while (cursor);
  }

  /** Polls a job until it is terminal, honouring Retry-After. */
  async waitForJob(jobId: string, options?: WaitOptions): Promise<Job> {
    const timeout = options?.timeoutMs ?? DEFAULT_WAIT_MS;
    const maxInterval = options?.maxIntervalMs ?? 10_000;
    const deadline = Date.now() + timeout;
    for (;;) {
      const raw = await this.send("GET", this.url(`/v1/jobs/${encodeURIComponent(jobId)}`), {}, { signal: options?.signal });
      const job = this.data<Job>(raw);
      if (TERMINAL.has(job.status)) {
        if (job.status === "succeeded") return job;
        const e = job.error;
        throw new LowcoJobError(e?.message ?? `Job ${jobId} was ${job.status}`, job, {
          status: e?.code ?? 409, reason: e?.reason ?? "invalid_state", param: e?.param, details: e?.details,
          docUrl: e?.doc_url, retryable: e?.retryable, requestId: raw.headers.get("x-request-id") ?? undefined, payload: job,
        });
      }
      const ra = Number(raw.headers.get("retry-after") ?? "2");
      const left = deadline - Date.now();
      if (left <= 0) throw new LowcoTimeoutError(jobId, timeout);
      await sleep(Math.max(0, Math.min((Number.isFinite(ra) ? ra : 2) * 1000, maxInterval, left)), options?.signal);
    }
  }

  /** The result of an answer: inline data, or the job's result once it finishes. */
  async waitForResult<T>(answer: Answer<T>, options?: WaitOptions): Promise<T> {
    if (answer.data !== undefined) return answer.data;
    if (answer.job) {
      const job = await this.waitForJob(answer.job.job_id, options);
      return job.result as T;
    }
    throw new LowcoApiError("The answer carries bytes, not a result", { status: answer.status, reason: "invalid_param" });
  }
}
