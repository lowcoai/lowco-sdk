import { HttpClient } from "../client.js";
import type { FunctionEntity, FunctionVersionRequest, PaginationQuery } from "../types.js";

export class FunctionsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<FunctionEntity[]> {
    return this.http.request("GET", "/v1/wf/functions", undefined, { query });
  }

  getById(id: string): Promise<FunctionEntity> {
    return this.http.request("GET", `/v1/wf/functions/${id}`);
  }

  create(payload: FunctionEntity): Promise<FunctionEntity> {
    return this.http.request("POST", "/v1/wf/functions", payload);
  }

  update(id: string, payload: FunctionVersionRequest): Promise<FunctionEntity> {
    return this.http.request("PUT", `/v1/wf/functions/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/wf/functions/${id}`);
  }

  versions(id: string, query?: PaginationQuery): Promise<FunctionEntity[]> {
    return this.http.request("GET", `/v1/wf/functions/${id}/versions`, undefined, { query });
  }

  execute(id: string, params?: Record<string, unknown>): Promise<Record<string, unknown>> {
    return this.http.request("POST", `/v1/wf/functions/${id}/execute`, params ?? {});
  }
}
