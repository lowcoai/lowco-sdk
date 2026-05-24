import type { HttpClient } from "../client.js";
import type { ApplicationTrigger, PaginationQuery, TriggerState } from "../types.js";

export class TriggersResource {
  constructor(private readonly http: HttpClient) {}

  listByApplication(applicationId: string, query?: PaginationQuery): Promise<ApplicationTrigger[]> {
    return this.http.request(
      "GET",
      `/v1/integrations/applications/${applicationId}/triggers`,
      undefined,
      { query }
    );
  }

  getById(id: string): Promise<ApplicationTrigger> {
    return this.http.request("GET", `/v1/integrations/triggers/${id}`);
  }

  create(payload: ApplicationTrigger): Promise<ApplicationTrigger> {
    return this.http.request("POST", "/v1/integrations/triggers", payload);
  }

  update(id: string, payload: ApplicationTrigger): Promise<ApplicationTrigger> {
    return this.http.request("PUT", `/v1/integrations/triggers/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/integrations/triggers/${id}`);
  }

  getState(id: string): Promise<TriggerState> {
    return this.http.request("GET", `/v1/integrations/triggers/${id}/state`);
  }
}
