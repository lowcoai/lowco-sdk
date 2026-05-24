import { HttpClient } from "../client.js";
import type { Environment, PaginationQuery } from "../types.js";

export class EnvironmentsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<Environment[]> {
    return this.http.request("GET", "/v1/wf/environments", undefined, { query });
  }

  getById(id: string): Promise<Environment> {
    return this.http.request("GET", `/v1/wf/environments/${id}`);
  }

  create(payload: Environment): Promise<Environment> {
    return this.http.request("POST", "/v1/wf/environments", payload);
  }

  update(id: string, payload: Environment): Promise<Environment> {
    return this.http.request("PUT", `/v1/wf/environments/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/wf/environments/${id}`);
  }

  setDefault(id: string): Promise<Environment> {
    return this.http.request("PATCH", `/v1/wf/environments/${id}/default`);
  }
}
