import { HttpClient } from "../client.js";
import type { Execution, PaginationQuery } from "../types.js";

export class ExecutionsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery & { full?: boolean }): Promise<Execution[]> {
    return this.http.request("GET", "/v1/wf/executions", undefined, { query });
  }

  count(query?: PaginationQuery): Promise<number | Record<string, unknown>> {
    return this.http.request("GET", "/v1/wf/executions/count", undefined, { query });
  }

  getById(id: string): Promise<Execution> {
    return this.http.request("GET", `/v1/wf/executions/${id}`);
  }

  logs(id: string): Promise<unknown[]> {
    return this.http.request("GET", `/v1/wf/executions/${id}/logs`);
  }
}
