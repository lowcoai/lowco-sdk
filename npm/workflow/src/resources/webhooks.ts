import { HttpClient, WorkflowError } from "../client.js";
import type { WebhookCreateRequest } from "../types.js";

// The workflow API serves only `POST /v1/wf/webhook/:id`, which triggers the
// workflow. Listing, registering, updating and deleting webhooks are not
// routed; registration is handled by the integrations service when a workflow
// is saved with an application trigger. The deprecated methods below reject
// locally so they never reach the trigger route.
function unsupported(operation: string, detail: string): Promise<never> {
  return Promise.reject(
    new WorkflowError(
      `webhooks.${operation} is not supported and no request was sent: ${detail} ` +
        "Webhook registration is handled by the integrations service. " +
        "Use webhooks.trigger(workflowId, payload) to run a workflow.",
      0,
      { code: "unsupported_operation", operation: `webhooks.${operation}` }
    )
  );
}

export class WebhooksResource {
  constructor(private readonly http: HttpClient) {}

  /** Runs the workflow with `payload` as its input (`POST /v1/wf/webhook/:id`). */
  trigger(
    workflowId: string,
    payload?: Record<string, unknown>,
    query?: { env?: string; triggeredBy?: string; async?: boolean }
  ): Promise<Record<string, unknown>> {
    return this.http.request("POST", `/v1/wf/webhook/${workflowId}`, payload ?? {}, { query });
  }

  /**
   * @deprecated The workflow API does not serve `GET /v1/wf/webhook/:id`, and
   * webhook registration is handled by the integrations service. Always rejects
   * with a `WorkflowError` without sending a request. Will be removed in a
   * future major version.
   */
  listByWorkflow(workflowId: string): Promise<Record<string, unknown>[]> {
    return unsupported("listByWorkflow", "the workflow API does not serve GET /v1/wf/webhook/{id}.");
  }

  /**
   * @deprecated `POST /v1/wf/webhook/:id` triggers the workflow, so this call
   * used to run the workflow with the webhook config as its input. Webhook
   * registration is handled by the integrations service. Always rejects with a
   * `WorkflowError` without sending a request; use
   * {@link WebhooksResource.trigger} to run a workflow. Will be removed in a
   * future major version.
   */
  create(workflowId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>> {
    return unsupported(
      "create",
      "POST /v1/wf/webhook/{id} triggers the workflow, so the webhook config would have run as workflow input."
    );
  }

  /**
   * @deprecated The workflow API does not serve `PUT /v1/wf/webhook/:id`, and
   * webhook registration is handled by the integrations service. Always rejects
   * with a `WorkflowError` without sending a request. Will be removed in a
   * future major version.
   */
  update(webhookId: string, payload: WebhookCreateRequest): Promise<Record<string, unknown>> {
    return unsupported("update", "the workflow API does not serve PUT /v1/wf/webhook/{id}.");
  }

  /**
   * @deprecated The workflow API does not serve `DELETE /v1/wf/webhook/:id`, and
   * webhook registration is handled by the integrations service. Always rejects
   * with a `WorkflowError` without sending a request. Will be removed in a
   * future major version.
   */
  delete(workflowId: string): Promise<Record<string, unknown>> {
    return unsupported("delete", "the workflow API does not serve DELETE /v1/wf/webhook/{id}.");
  }
}
