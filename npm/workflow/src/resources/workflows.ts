import { HttpClient } from "../client.js";
import type { PaginationQuery, RunWorkflowRequest, Workflow, WorkflowPublish, WorkflowUpdateRequest } from "../types.js";

export class WorkflowsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<Workflow[]> {
    return this.http.request("GET", "/v1/wf/workflows", undefined, { query });
  }

  count(query?: PaginationQuery): Promise<number | Record<string, unknown>> {
    return this.http.request("GET", "/v1/wf/workflows/count", undefined, { query });
  }

  getById(id: string): Promise<Workflow> {
    return this.http.request("GET", `/v1/wf/workflows/${id}`);
  }

  create(payload: WorkflowUpdateRequest): Promise<Workflow> {
    return this.http.request("POST", "/v1/wf/workflows", payload);
  }

  update(id: string, payload: WorkflowUpdateRequest): Promise<Workflow> {
    return this.http.request("PUT", `/v1/wf/workflows/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/wf/workflows/${id}`);
  }

  run(payload: RunWorkflowRequest): Promise<Record<string, unknown>> {
    return this.http.request("POST", "/v1/wf/workflows/run", payload);
  }

  versions(id: string, query?: PaginationQuery): Promise<Workflow[]> {
    return this.http.request("GET", `/v1/wf/workflows/${id}/versions`, undefined, { query });
  }

  publish(id: string, payload: { category: string; longDescription: string }): Promise<WorkflowPublish> {
    return this.http.request("POST", `/v1/wf/workflows/${id}/publish`, payload);
  }

  published(query?: PaginationQuery): Promise<WorkflowPublish[]> {
    return this.http.request("GET", "/v1/wf/workflows/published", undefined, { query });
  }

  publishedCount(query?: PaginationQuery): Promise<number | Record<string, unknown>> {
    return this.http.request("GET", "/v1/wf/workflows/published/count", undefined, { query });
  }

  getPublishedById(id: string): Promise<WorkflowPublish> {
    return this.http.request("GET", `/v1/wf/workflows/published/${id}`);
  }

  updatePublished(id: string, payload: { category: string; longDescription: string }): Promise<WorkflowPublish> {
    return this.http.request("PUT", `/v1/wf/workflows/published/${id}`, payload);
  }

  deletePublished(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/wf/workflows/published/${id}`);
  }

  webPublished(query?: PaginationQuery): Promise<WorkflowPublish[]> {
    return this.http.request("GET", "/v1/wf/workflows/published/web", undefined, { query });
  }

  webPublishedById(id: string): Promise<WorkflowPublish> {
    return this.http.request("GET", `/v1/wf/workflows/published/web/${id}`);
  }

  searchPublishedTemplates(params: {
    q?: string;
    category?: string;
    limit?: number;
  }): Promise<WorkflowPublish[]> {
    return this.http.request("GET", "/v1/wf/workflows/published/web/search", undefined, { query: params });
  }
}
