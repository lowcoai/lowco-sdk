import type { HttpClient } from "../client.js";
import type {
  ApplicationAction,
  ApplicationWithConnection,
  PaginationQuery,
  RunActionRequest
} from "../types.js";

export class ActionsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<ApplicationAction[]> {
    return this.http.request("GET", "/v1/integrations/actions", undefined, { query });
  }

  getById(id: string): Promise<ApplicationAction> {
    return this.http.request("GET", `/v1/integrations/actions/${id}`);
  }

  create(applicationId: string, payload: ApplicationAction): Promise<ApplicationAction> {
    return this.http.request("POST", `/v1/integrations/applications/${applicationId}/action`, payload);
  }

  update(id: string, payload: ApplicationAction): Promise<ApplicationAction> {
    return this.http.request("PUT", `/v1/integrations/actions/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/integrations/actions/${id}`);
  }

  listByApplication(applicationId: string): Promise<ApplicationAction[]> {
    return this.http.request("GET", `/v1/integrations/applications/${applicationId}/actions`);
  }

  run(id: string, payload: RunActionRequest): Promise<unknown> {
    return this.http.request("POST", `/v1/integrations/actions/${id}/run`, payload);
  }

  resolveCredentials(actionIds: string[]): Promise<ApplicationWithConnection[]> {
    return this.http.request("POST", "/v1/integrations/actions/allCredential", actionIds);
  }
}
