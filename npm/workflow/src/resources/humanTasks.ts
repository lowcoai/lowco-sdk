import { HttpClient } from "../client.js";
import type { HumanTask, PaginationQuery } from "../types.js";

export class HumanTasksResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<HumanTask[]> {
    return this.http.request("GET", "/v1/wf/human-tasks", undefined, { query });
  }

  getById(id: string): Promise<HumanTask> {
    return this.http.request("GET", `/v1/wf/human-tasks/${id}`);
  }

  complete(id: string, action: string): Promise<HumanTask> {
    return this.http.request("PATCH", `/v1/wf/human-tasks/${id}/complete`, { action });
  }
}
