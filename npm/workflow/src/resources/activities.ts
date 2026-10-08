import { HttpClient } from "../client.js";
import type { ActivityHistoryResponse, PaginationQuery } from "../types.js";

export class ActivitiesResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<ActivityHistoryResponse[]> {
    return this.http.request("GET", "/v1/wf/activities", undefined, { query });
  }

  count(query?: PaginationQuery): Promise<number | Record<string, unknown>> {
    return this.http.request("GET", "/v1/wf/activities/count", undefined, { query });
  }

  getById(id: string): Promise<ActivityHistoryResponse> {
    return this.http.request("GET", `/v1/wf/activities/${id}`);
  }

  logs(id: string): Promise<unknown[]> {
    return this.http.request("GET", `/v1/wf/activities/${id}/logs`);
  }
}
