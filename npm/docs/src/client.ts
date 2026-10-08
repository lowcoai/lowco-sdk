import type {
  ApiEnvelope,
  ArchiveRestoring,
  Binary,
  DocsClientConfig,
  HttpMethod,
  NodeFileResult,
  RequestOptions,
  UploadInput
} from "./types.js";

const BASE_URL = "https://api.lowco.ai";

/** Route prefix of the document API. */
export const API_PREFIX = "/v1/documents";

export const HEADER_ORG_ID = "X-Org-Id";

const DEFAULT_TIMEOUT_MS = 30_000;
/** Platform error codes (e.g. `AAS-00106`) the service puts in `error.message`. */
const PLATFORM_CODE = /^[A-Z]{2,}-\d+$/;

/** Error thrown for every failed call: non-2xx responses, network failures, timeouts and invalid input. */
export class DocsError extends Error {
  /** HTTP status, or `0` when no response was received (network error, timeout, invalid input). */
  readonly status: number;
  /** Parsed response body (JSON, else text), or `null`. */
  readonly payload: unknown;
  /** Platform error code (e.g. `AAS-00106`) when the response carried one. */
  readonly code?: string;

  constructor(message: string, status: number, payload: unknown, options?: { code?: string; cause?: unknown }) {
    super(message, options?.cause === undefined ? undefined : { cause: options.cause });
    this.name = "DocsError";
    this.status = status;
    this.payload = payload;
    if (options?.code !== undefined) {
      this.code = options.code;
    }
  }
}

/** Percent-encodes a single-segment path parameter (`/` included). */
export function encodeSegment(value: string): string {
  return encodeURIComponent(value);
}

/** Percent-encodes each segment of a wildcard path parameter, keeping `/` separators and dropping a leading `/`. */
export function encodePath(path: string): string {
  return path.replace(/^\/+/, "").split("/").map(encodeURIComponent).join("/");
}

/** Builds the multipart part for one upload input. */
export function appendFile(form: FormData, field: string, input: UploadInput): void {
  if (isBlob(input)) {
    const name = (input as { name?: unknown }).name;
    if (typeof name === "string" && name.length > 0) {
      form.append(field, input, name);
    } else {
      form.append(field, input);
    }
    return;
  }
  const { data, fileName, contentType } = input;
  let blob: Blob;
  if (isBlob(data)) {
    blob = contentType && contentType !== data.type ? new Blob([data], { type: contentType }) : data;
  } else if (typeof data === "string") {
    blob = new Blob([data], { type: contentType ?? "text/plain;charset=utf-8" });
  } else {
    const bytes = ArrayBuffer.isView(data)
      ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
      : new Uint8Array(data);
    blob = new Blob([bytes as unknown as BlobPart], { type: contentType ?? "application/octet-stream" });
  }
  form.append(field, blob, fileName);
}

function isBlob(value: unknown): value is Blob {
  return typeof Blob !== "undefined" && value instanceof Blob;
}

interface SendOptions extends RequestOptions {
  json?: unknown;
  form?: FormData;
  accept: string;
  redirect?: RequestRedirect;
}

/** Low-level transport: auth and org headers, timeouts, envelope unwrapping and error mapping. */
export class HttpClient {
  private readonly token: string;
  private readonly orgId: string;
  private readonly timeoutMs: number;
  private readonly extraHeaders: Record<string, string>;
  private readonly fetchImpl: typeof globalThis.fetch;

  constructor(config: DocsClientConfig) {
    if (!config || typeof config.token !== "string" || config.token.trim() === "") {
      throw new Error("`token` is required. Pass a user token or API key in SDK config.");
    }
    if (typeof config.orgId !== "string" || config.orgId.trim() === "") {
      throw new Error("`orgId` is required. The document service rejects requests without an X-Org-Id header.");
    }
    this.token = config.token;
    this.orgId = config.orgId;
    this.timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.extraHeaders = config.headers ?? {};
    this.fetchImpl = config.fetch ?? globalThis.fetch;

    if (!this.fetchImpl) {
      throw new Error("No fetch implementation found. Pass `fetch` in SDK config.");
    }
  }

  /** Sends a JSON request and returns the unwrapped `data` of the success envelope. */
  request<T>(method: HttpMethod, path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.send(method, path, { ...options, json: body, accept: "application/json" }, async (response) => {
      if (!response.ok) {
        throw await toError(response);
      }
      return parseEnvelope<T>(response);
    });
  }

  /** Sends a multipart request and returns the unwrapped `data` of the success envelope. */
  upload<T>(path: string, form: FormData, options?: RequestOptions): Promise<T> {
    return this.send("POST", path, { ...options, form, accept: "application/json" }, async (response) => {
      if (!response.ok) {
        throw await toError(response);
      }
      return parseEnvelope<T>(response);
    });
  }

  /** Sends a request and returns the response body as text. */
  requestText(method: HttpMethod, path: string, options?: RequestOptions): Promise<string> {
    return this.send(method, path, { ...options, accept: "text/plain, */*" }, async (response) => {
      if (!response.ok) {
        throw await toError(response);
      }
      return response.text();
    });
  }

  /** Sends a request and returns the response body as bytes. */
  requestBinary(method: HttpMethod, path: string, options?: RequestOptions): Promise<Binary> {
    return this.send(method, path, { ...options, accept: "*/*" }, async (response) => {
      if (!response.ok) {
        throw await toError(response);
      }
      return readBinary(response);
    });
  }

  /** Sends a request without following redirects and returns the `Location` URL. */
  requestRedirectUrl(method: HttpMethod, path: string, options?: RequestOptions): Promise<string> {
    return this.send(
      method,
      path,
      { ...options, accept: "application/json", redirect: "manual" },
      async (response, url) => {
        assertNotOpaque(response);
        if (isRedirect(response.status)) {
          return redirectTarget(response, url);
        }
        if (!response.ok) {
          throw await toError(response);
        }
        const payload = await readPayload(response);
        throw new DocsError(
          `Expected a redirect (Location header) but received status ${response.status}`,
          response.status,
          payload
        );
      }
    );
  }

  /**
   * Fetches a node endpoint that answers 307 (URL), 200 (bytes) or 202 (restore
   * from cold storage in progress). Redirects are never followed.
   */
  requestNodeFile(path: string, options?: RequestOptions): Promise<NodeFileResult> {
    return this.send(
      "GET",
      path,
      { ...options, accept: "*/*", redirect: "manual" },
      async (response, url) => {
        assertNotOpaque(response);
        if (isRedirect(response.status)) {
          return { url: redirectTarget(response, url) };
        }
        if (!response.ok) {
          throw await toError(response);
        }
        if (response.status === 202) {
          const restoring = (await parseEnvelope<ArchiveRestoring | undefined>(response)) ?? {};
          const retryAfter = parseRetryAfter(response.headers.get("retry-after")) ?? restoring.retryAfterSeconds;
          return retryAfter === undefined ? { restoring } : { restoring, retryAfter };
        }
        return { content: await readBinary(response) };
      }
    );
  }

  private async send<R>(
    method: HttpMethod,
    path: string,
    options: SendOptions,
    handle: (response: Response, url: string) => Promise<R>
  ): Promise<R> {
    // URL parsers collapse "." and ".." segments (even percent-encoded), which
    // would silently send the request to another route.
    if (path.split("/").some((segment) => segment === "." || segment === "..")) {
      throw new DocsError(`Path segments "." and ".." are not allowed: ${path}`, 0, null);
    }
    const url = this.buildUrl(path, options.query);
    const headers = this.buildHeaders(options);

    let body: BodyInit | undefined;
    if (options.form !== undefined) {
      body = options.form;
    } else if (options.json !== undefined) {
      body = JSON.stringify(options.json);
    }

    const controller = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);
    const external = options.signal;
    const onAbort = () => controller.abort(external?.reason);
    if (external) {
      if (external.aborted) {
        controller.abort(external.reason);
      } else {
        external.addEventListener("abort", onAbort, { once: true });
      }
    }

    try {
      const init: RequestInit = { method, headers, body, signal: controller.signal };
      if (options.redirect) {
        init.redirect = options.redirect;
      }
      const response = await this.fetchImpl(url, init);
      return await handle(response, url);
    } catch (error) {
      if (error instanceof DocsError) {
        throw error;
      }
      if (timedOut) {
        throw new DocsError(`Request timed out after ${this.timeoutMs}ms`, 0, null, { cause: error });
      }
      const message = error instanceof Error ? error.message : String(error);
      throw new DocsError(message, 0, null, { cause: error });
    } finally {
      clearTimeout(timeout);
      external?.removeEventListener("abort", onAbort);
    }
  }

  private buildHeaders(options: SendOptions): Record<string, string> {
    const headers: Record<string, string> = { ...this.extraHeaders, ...options.headers };
    if (!hasHeader(headers, "accept")) {
      headers.Accept = options.accept;
    }
    if (options.form === undefined && options.json !== undefined) {
      headers["Content-Type"] = "application/json";
    }
    if (!hasHeader(headers, "authorization")) {
      headers.Authorization = `Bearer ${this.token}`;
    }
    if (!hasHeader(headers, HEADER_ORG_ID)) {
      headers[HEADER_ORG_ID] = this.orgId;
    }
    return headers;
  }

  private buildUrl(path: string, query?: Record<string, unknown>): string {
    const normalized = path.startsWith("/") ? path : `/${path}`;
    const url = new URL(`${BASE_URL}${normalized}`);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value === undefined || value === null) continue;
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
          url.searchParams.set(key, String(value));
          continue;
        }
        url.searchParams.set(key, JSON.stringify(value));
      }
    }
    return url.toString();
  }
}

function hasHeader(headers: Record<string, string>, name: string): boolean {
  const lower = name.toLowerCase();
  return Object.keys(headers).some((key) => key.toLowerCase() === lower);
}

function isRedirect(status: number): boolean {
  return status >= 300 && status < 400;
}

function assertNotOpaque(response: Response): void {
  if (response.type === "opaqueredirect" || response.status === 0) {
    throw new DocsError(
      "The server answered with a redirect whose Location this runtime hides (browser fetch returns an " +
        "opaque redirect). Methods that return a URL need a server runtime such as Node.js 18+.",
      0,
      null
    );
  }
}

function redirectTarget(response: Response, requestUrl: string): string {
  const location = response.headers.get("location");
  if (!location) {
    throw new DocsError(`Redirect (status ${response.status}) without a Location header`, response.status, null);
  }
  // Absolute URLs (presigned or CDN) are returned untouched so their signature survives.
  return /^[a-z][a-z0-9+.-]*:/i.test(location) ? location : new URL(location, requestUrl).toString();
}

async function readPayload(response: Response): Promise<unknown> {
  let text: string;
  try {
    text = await response.text();
  } catch {
    return null;
  }
  if (text.length === 0) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

async function parseEnvelope<T>(response: Response): Promise<T> {
  const text = await response.text();
  if (text.trim().length === 0) {
    return undefined as T;
  }
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch (error) {
    throw new DocsError(`Invalid JSON in response (status ${response.status})`, response.status, text, {
      cause: error
    });
  }
  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    const envelope = payload as ApiEnvelope<T> & { error?: unknown };
    if (envelope.status === 0 && envelope.error) {
      throw errorFromPayload(response.status, payload);
    }
    if ("data" in envelope) {
      return envelope.data as T;
    }
  }
  return payload as T;
}

async function toError(response: Response): Promise<DocsError> {
  return errorFromPayload(response.status, await readPayload(response));
}

function errorFromPayload(status: number, payload: unknown): DocsError {
  let message: string | undefined;
  let code: string | undefined;

  if (payload && typeof payload === "object") {
    const body = payload as { message?: unknown; error?: unknown };
    if (body.error && typeof body.error === "object") {
      // { "status": 0, "error": { "message", "code", "details" } }
      const err = body.error as { message?: unknown; details?: unknown };
      const errMessage = typeof err.message === "string" ? err.message.trim() : "";
      const details = typeof err.details === "string" ? err.details.trim() : "";
      if (PLATFORM_CODE.test(errMessage)) {
        code = errMessage;
        message = details || errMessage;
      } else {
        message = errMessage || details || undefined;
      }
    } else if (typeof body.error === "string" && body.error.trim()) {
      message = body.error.trim();
    }
    if (!message && typeof body.message === "string" && body.message.trim()) {
      // { "message": "..." }
      message = body.message.trim();
    }
  } else if (typeof payload === "string" && payload.trim()) {
    const text = payload.trim();
    message = text.length > 300 ? `${text.slice(0, 300)}...` : text;
  }

  return new DocsError(message ?? `Request failed with status ${status}`, status, payload, { code });
}

async function readBinary(response: Response): Promise<Binary> {
  const data = new Uint8Array(await response.arrayBuffer());
  const contentType = response.headers.get("content-type") ?? "application/octet-stream";
  const fileName = fileNameOf(response.headers);
  return fileName === undefined ? { data, contentType } : { data, contentType, fileName };
}

function fileNameOf(headers: Headers): string | undefined {
  const explicit = headers.get("x-file-name");
  if (explicit) {
    return fromLatin1(explicit);
  }
  const disposition = headers.get("content-disposition");
  if (!disposition) {
    return undefined;
  }
  const extended = /filename\*\s*=\s*([^']*)'[^']*'([^;]+)/i.exec(disposition);
  if (extended?.[2]) {
    try {
      return decodeURIComponent(extended[2].trim());
    } catch {
      // fall through to the plain filename
    }
  }
  const quoted = /filename\s*=\s*"((?:[^"\\]|\\.)*)"/i.exec(disposition);
  if (quoted?.[1] !== undefined) {
    return fromLatin1(quoted[1].replace(/\\(.)/g, "$1"));
  }
  const bare = /filename\s*=\s*([^;\s]+)/i.exec(disposition);
  return bare?.[1] ? fromLatin1(bare[1]) : undefined;
}

/** Header values arrive latin1-decoded; recover UTF-8 names sent as raw bytes. */
function fromLatin1(value: string): string {
  if (!/[\u0080-ÿ]/.test(value) || /[^\u0000-ÿ]/.test(value)) {
    return value;
  }
  try {
    const bytes = Uint8Array.from(value, (ch) => ch.charCodeAt(0));
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return value;
  }
}

function parseRetryAfter(value: string | null): number | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  if (/^\d+$/.test(trimmed)) {
    return Number.parseInt(trimmed, 10);
  }
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return undefined;
  return Math.max(0, Math.ceil((date - Date.now()) / 1000));
}
