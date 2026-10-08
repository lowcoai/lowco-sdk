import { AgentxError } from "./errors.js";
import type { APIErrorPayload, ListParams } from "./types.js";

const BASE_URL = "https://api.lowco.ai";

/** Per-service route prefix, shared by all three sub-clients. */
export interface ServiceTarget {
  apiBasePath: string;
}

export interface TransportOptions {
  fetch: typeof fetch;
  /** Mutable header bag – the parent Client owns it. */
  headers: Record<string, string>;
  /** Per-request timeout for non-streaming calls; 0 disables. */
  timeoutMs: number;
}

export interface RequestOptions {
  method: string;
  path: string;
  query?: URLSearchParams | null;
  body?: unknown;
  enveloped?: boolean;
}

/**
 * Shared HTTP transport used by every sub-client.
 * Pass the target service to each request.
 */
export class Transport {
  private readonly fetchFn: typeof fetch;
  readonly headers: Record<string, string>;
  private readonly timeoutMs: number;

  constructor(opts: TransportOptions) {
    this.fetchFn = opts.fetch;
    this.headers = opts.headers;
    this.timeoutMs = opts.timeoutMs;
  }

  joinPath(apiBasePath: string, ...parts: string[]): string {
    const segs = [apiBasePath.replace(/^\/+|\/+$/g, "")];
    for (const p of parts) segs.push(encodeURIComponent(p.replace(/^\/+|\/+$/g, "")));
    return "/" + segs.join("/");
  }

  listQuery(params?: ListParams): URLSearchParams | null {
    if (!params) return null;
    const q = new URLSearchParams();
    if (params.pageNo !== undefined) q.set("pageNo", String(params.pageNo));
    if (params.size !== undefined) q.set("size", String(params.size));
    if (params.filter !== undefined) q.set("filter", params.filter);
    if (params.sort !== undefined) q.set("sort", params.sort);
    return q;
  }

  /** Send a JSON request and decode (optionally enveloped) JSON response. */
  async request<T>(target: ServiceTarget, opts: RequestOptions): Promise<T> {
    const resp = await this.send(target, opts, "application/json");
    const text = await resp.text();
    if (!resp.ok) {
      throw buildHttpError(resp.status, text);
    }
    if (resp.status === 204 || text.trim().length === 0) {
      return undefined as T;
    }
    if (opts.enveloped) {
      return decodeEnvelope<T>(text);
    }
    return JSON.parse(text) as T;
  }

  /**
   * Send a request and return the raw Response, without decoding.
   * Used by the executor's SSE stream.
   */
  async sendRaw(
    target: ServiceTarget,
    opts: RequestOptions & { accept?: string; signal?: AbortSignal },
  ): Promise<Response> {
    return this.send(target, opts, opts.accept ?? "application/json", opts.signal);
  }

  private async send(
    _target: ServiceTarget,
    opts: RequestOptions,
    accept: string,
    signal?: AbortSignal,
  ): Promise<Response> {
    const url = new URL(BASE_URL + opts.path);
    if (opts.query) {
      opts.query.forEach((v, k) => url.searchParams.append(k, v));
    }

    const headers: Record<string, string> = {
      Accept: accept,
      ...this.headers,
    };
    let body: string | undefined;
    if (opts.body !== undefined && opts.body !== null) {
      body = JSON.stringify(opts.body);
      headers["Content-Type"] = "application/json";
    }

    // External signal takes precedence; otherwise use the request timeout.
    let controller: AbortController | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    let effectiveSignal: AbortSignal | undefined = signal;
    if (!signal && this.timeoutMs > 0) {
      controller = new AbortController();
      timer = setTimeout(() => controller!.abort(), this.timeoutMs);
      effectiveSignal = controller.signal;
    }

    try {
      return await this.fetchFn(url.toString(), {
        method: opts.method,
        headers,
        body,
        signal: effectiveSignal,
      });
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}

export function buildHttpError(status: number, text: string): AgentxError {
  let message = text.trim();
  let code: string | undefined;
  try {
    const parsed = JSON.parse(text) as { message?: string; error?: APIErrorPayload };
    if (parsed.error?.message?.trim()) {
      message = parsed.error.message;
      code = parsed.error.code;
    } else if (parsed.message) {
      message = parsed.message;
    }
  } catch {
    /* keep raw text */
  }
  return new AgentxError({ statusCode: status, message, code, body: text });
}

function decodeEnvelope<T>(text: string): T {
  let env: { success?: boolean; data?: unknown; message?: string; error?: APIErrorPayload };
  try {
    env = JSON.parse(text);
  } catch {
    return JSON.parse(text) as T;
  }
  if (env && typeof env === "object" && "data" in env) {
    if (env.data === undefined || env.data === null) return undefined as T;
    return env.data as T;
  }
  return env as T;
}
