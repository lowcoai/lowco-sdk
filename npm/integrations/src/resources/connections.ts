import type { HttpClient } from "../client.js";
import type { Connection, ConnectionResponse, PaginationQuery, SetAsDefaultRequest } from "../types.js";

export class ConnectionsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<Connection[]> {
    return this.http.request("GET", "/v1/integrations/connections", undefined, { query });
  }

  getById(id: string): Promise<ConnectionResponse> {
    return this.http.request("GET", `/v1/integrations/connections/${id}`);
  }

  create(payload: Connection): Promise<Connection> {
    return this.http.request("POST", "/v1/integrations/connections", payload);
  }

  update(id: string, payload: Connection): Promise<Connection> {
    return this.http.request("PUT", `/v1/integrations/connections/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/integrations/connections/${id}`);
  }

  listByApplication(applicationId: string): Promise<Connection[]> {
    return this.http.request("GET", `/v1/integrations/applications/${applicationId}/connections`);
  }

  setAsDefault(id: string, applicationId: string): Promise<Connection> {
    const body: SetAsDefaultRequest = { applicationId };
    return this.http.request("PATCH", `/v1/integrations/connections/${id}/setDefault`, body);
  }
}
