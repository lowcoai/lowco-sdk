import type { HttpClient } from "../client.js";
import { API_PREFIX, encodeSegment } from "../client.js";
import type { PageOptions, Webhook, WebhookRequest } from "../types.js";

/** Webhooks: call a URL when an object event happens under a prefix. */
export class WebhooksResource {
  constructor(private readonly http: HttpClient) {}

  /** The org's webhooks visible to the caller (`GET /webhooks?page=&limit=`). */
  list(options?: PageOptions): Promise<Webhook[]> {
    return this.http.request("GET", `${API_PREFIX}/webhooks`, undefined, {
      query: { page: options?.page, limit: options?.limit }
    });
  }

  /** Creates a webhook; `url`, `method`, `prefix` and one event type are required (`POST /webhooks`). */
  create(body: WebhookRequest): Promise<Webhook> {
    return this.http.request("POST", `${API_PREFIX}/webhooks`, body);
  }

  /** Returns one webhook (`GET /webhooks/{id}`). */
  get(id: string): Promise<Webhook> {
    return this.http.request("GET", `${API_PREFIX}/webhooks/${encodeSegment(id)}`);
  }

  /** Replaces every field of a webhook (`PUT /webhooks/{id}`). */
  update(id: string, body: WebhookRequest): Promise<Webhook> {
    return this.http.request("PUT", `${API_PREFIX}/webhooks/${encodeSegment(id)}`, body);
  }

  /** Deletes a webhook (`DELETE /webhooks/{id}`, 204). */
  async delete(id: string): Promise<void> {
    await this.http.request<unknown>("DELETE", `${API_PREFIX}/webhooks/${encodeSegment(id)}`);
  }
}
