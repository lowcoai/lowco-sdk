import { HttpClient } from "./client.js";
import { ActionsResource } from "./resources/actions.js";
import { ApplicationsResource } from "./resources/applications.js";
import { ConfigurationsResource } from "./resources/configurations.js";
import { ConnectionsResource } from "./resources/connections.js";
import { McpResource } from "./resources/mcp.js";
import { OAuthResource } from "./resources/oauth.js";
import { TriggersResource } from "./resources/triggers.js";
import type { SDKConfig } from "./types.js";

export class IntegrationsClient {
  readonly applications: ApplicationsResource;
  readonly actions: ActionsResource;
  readonly connections: ConnectionsResource;
  readonly triggers: TriggersResource;
  readonly oauth: OAuthResource;
  readonly configurations: ConfigurationsResource;
  readonly mcp: McpResource;

  constructor(config: SDKConfig) {
    const http = new HttpClient(config);
    this.applications = new ApplicationsResource(http);
    this.actions = new ActionsResource(http);
    this.connections = new ConnectionsResource(http);
    this.triggers = new TriggersResource(http);
    this.oauth = new OAuthResource(http);
    this.configurations = new ConfigurationsResource(http);
    this.mcp = new McpResource(http);
  }
}

export { HttpClient, IntegrationsError, HEADER_ORG_ID } from "./client.js";
export * from "./types.js";
