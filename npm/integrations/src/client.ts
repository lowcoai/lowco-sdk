import type { ApiEnvelope, HttpMethod, RequestOptions, SDKConfig } from "./types.js";

const BASE_URL = "https://api.lowco.ai";

export const HEADER_ORG_ID = "X-Org-Id";

export class IntegrationsError extends Error {
  readonly status: number;
  readonly payload: unknown;

  constructor(message: string, status: number, payload: unknown) {
    super(message);
    this.name = "IntegrationsError";
    this.status = status;
    this.payload = payload;
  }
}

export class HttpClient {
  private readonly token: string;
  private readonly orgId?: string;
  private readonly timeoutMs: number;
  private readonly extraHeaders: Record<string, string>;
  private readonly fetchImpl: typeof globalThis.fetch;

  constructor(config: SDKConfig) {
    if (!config.token) {
      throw new Error("`token` is required. Pass a user token or API key in SDK config.");
    }
    this.token = config.token;
    this.orgId = config.orgId;
    this.timeoutMs = config.timeoutMs ?? 30_000;
    this.extraHeaders = config.headers ?? {};
    this.fetchImpl = config.fetch ?? globalThis.fetch;

    if (!this.fetchImpl) {
      throw new Error("No fetch implementation found. Pass `fetch` in SDK config.");
    }
  }

  async request<T>(
    method: HttpMethod,
    path: string,
    body?: unknown,
    options?: RequestOptions
  ): Promise<T> {
    const url = this.buildUrl(path, options?.query);
    const headers: Record<string, string> = {
      Accept: "application/json",
      ...this.extraHeaders,
      ...options?.headers
    };

    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
    }
    if (!headers.Authorization) {
      headers.Authorization = `Bearer ${this.token}`;
    }
    if (this.orgId && !headers[HEADER_ORG_ID]) {
      headers[HEADER_ORG_ID] = this.orgId;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    const signal = options?.signal ?? controller.signal;

    try {
      const response = await this.fetchImpl(url, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal
      });

      const text = await response.text();
      const payload = text.length > 0 ? (JSON.parse(text) as unknown) : null;

      if (!response.ok) {
        throw new IntegrationsError(
          `Request failed with status ${response.status}`,
          response.status,
          payload
        );
      }

      return this.unwrapEnvelope<T>(payload);
    } catch (error) {
      if (error instanceof IntegrationsError) {
        throw error;
      }
      throw new IntegrationsError((error as Error).message, 0, null);
    } finally {
      clearTimeout(timeout);
    }
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

  private unwrapEnvelope<T>(payload: unknown): T {
    if (payload && typeof payload === "object" && "data" in (payload as ApiEnvelope<T>)) {
      return (payload as ApiEnvelope<T>).data as T;
    }
    return payload as T;
  }
}
