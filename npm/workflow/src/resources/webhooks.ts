import { HttpClient } from "../client.js";
import type { WebhookCreateRequest } from "../types.js";

export class WebhooksResource {
  constructor(private readonly http: HttpClient) {}

  trigger(
    workflowId: string,
    payload?: Record<string, unknown>,
    query?: { env?: string; triggeredBy?: string; async?: boolean }
  ): Promise<Record<string, unknown>> {
    return this.http.request("POST", `/v1/wf/webhook/${workflowId}`, payload ?? {}, { query });
  }

  listByWorkflow(workflowId: string): Promise<Record<string, unknown>[]> {
    return this.http.request("GET", `/v1/wf/webhook/${workflowId}`);
  }

  create(workflowId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>> {
    return this.http.request("POST", `/v1/wf/webhook/${workflowId}`, payload);
  }

  update(webhookId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>> {
    return this.http.request("PUT", `/v1/wf/webhook/${webhookId}`, payload);
  }

  delete(workflowId: string): Promise<Record<string, unknown>> {
    return this.http.request("DELETE", `/v1/wf/webhook/${workflowId}`);
  }
}
