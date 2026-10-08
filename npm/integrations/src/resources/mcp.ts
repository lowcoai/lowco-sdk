import type { HttpClient } from "../client.js";
import type { JsonRpcRequest, JsonRpcResponse } from "../types.js";

export class McpResource {
  constructor(private readonly http: HttpClient) {}

  callPublished(key: string, payload: JsonRpcRequest): Promise<JsonRpcResponse> {
    return this.http.request("POST", `/v1/integrations/applications/published/${key}`, payload);
  }

  infoPublished(key: string): Promise<Record<string, unknown>> {
    return this.http.request("GET", `/v1/integrations/applications/published/${key}`);
  }
}
