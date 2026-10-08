import { HttpClient } from "./client.js";
import { ActivitiesResource } from "./resources/activities.js";
import { AnalyticsResource } from "./resources/analytics.js";
import { DryRunResource } from "./resources/dryRun.js";
import { EnvironmentsResource } from "./resources/environments.js";
import { ExecutionsResource } from "./resources/executions.js";
import { FunctionsResource } from "./resources/functions.js";
import { HumanTasksResource } from "./resources/humanTasks.js";
import { WebhooksResource } from "./resources/webhooks.js";
import { WorkflowsResource } from "./resources/workflows.js";
import type { SDKConfig } from "./types.js";

export class WorkflowClient {
  readonly workflows: WorkflowsResource;
  readonly environments: EnvironmentsResource;
  readonly functions: FunctionsResource;
  readonly executions: ExecutionsResource;
  readonly activities: ActivitiesResource;
  readonly humanTasks: HumanTasksResource;
  readonly analytics: AnalyticsResource;
  readonly dryRun: DryRunResource;
  readonly webhooks: WebhooksResource;

  constructor(config: SDKConfig) {
    const http = new HttpClient(config);
    this.workflows = new WorkflowsResource(http);
    this.environments = new EnvironmentsResource(http);
    this.functions = new FunctionsResource(http);
    this.executions = new ExecutionsResource(http);
    this.activities = new ActivitiesResource(http);
    this.humanTasks = new HumanTasksResource(http);
    this.analytics = new AnalyticsResource(http);
    this.dryRun = new DryRunResource(http);
    this.webhooks = new WebhooksResource(http);
  }
}

export { HttpClient, WorkflowError, HEADER_ORG_ID } from "./client.js";
export * from "./types.js";
