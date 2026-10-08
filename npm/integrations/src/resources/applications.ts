import type { HttpClient } from "../client.js";
import type {
  Application,
  ApplicationAction,
  ApplicationHistory,
  ApplicationWithCount,
  McpToolsResponse,
  PaginationQuery,
  PatchTagsRequest,
  PostmanFolder,
  RunApplicationRequest,
  SubApplicationConfig
} from "../types.js";

export class ApplicationsResource {
  constructor(private readonly http: HttpClient) {}

  list(query?: PaginationQuery): Promise<ApplicationWithCount[]> {
    return this.http.request("GET", "/v1/integrations/applications", undefined, { query });
  }

  getById(id: string): Promise<Application> {
    return this.http.request("GET", `/v1/integrations/applications/${id}`);
  }

  create(payload: Application): Promise<Application> {
    return this.http.request("POST", "/v1/integrations/applications", payload);
  }

  update(id: string, payload: Application): Promise<Application> {
    return this.http.request("PUT", `/v1/integrations/applications/${id}`, payload);
  }

  delete(id: string): Promise<void> {
    return this.http.request("DELETE", `/v1/integrations/applications/${id}`);
  }

  patchTags(id: string, tags: string[]): Promise<Application> {
    const body: PatchTagsRequest = { tags };
    return this.http.request("PATCH", `/v1/integrations/applications/${id}/tags`, body);
  }

  run(id: string, payload: RunApplicationRequest): Promise<unknown> {
    return this.http.request("POST", `/v1/integrations/applications/${id}/run`, payload);
  }

  loadActions(id: string, folder: PostmanFolder): Promise<ApplicationAction[]> {
    return this.http.request("POST", `/v1/integrations/applications/${id}/load-actions`, folder);
  }

  versions(id: string, query?: PaginationQuery): Promise<ApplicationHistory[]> {
    return this.http.request("GET", `/v1/integrations/applications/${id}/versions`, undefined, { query });
  }

  regenerateMcpKey(id: string): Promise<Application> {
    return this.http.request("GET", `/v1/integrations/applications/${id}/regenerate-mcp-key`);
  }

  getMcpTools(id: string): Promise<McpToolsResponse> {
    return this.http.request("GET", `/v1/integrations/applications/${id}/mcp/tools`);
  }

  getSubApplications(): Promise<SubApplicationConfig> {
    return this.http.request("GET", "/v1/integrations/applications/types");
  }

  getApplicationsWithTriggers(): Promise<Application[]> {
    return this.http.request("GET", "/v1/integrations/applications/by-trigger");
  }
}
