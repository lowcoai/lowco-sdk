// src/client.ts
var HEADER_ORG_ID = "X-Org-Id";
var HEADER_USER_ID = "X-User-Id";
var WorkflowError = class extends Error {
  status;
  payload;
  constructor(message, status, payload) {
    super(message);
    this.name = "WorkflowError";
    this.status = status;
    this.payload = payload;
  }
};
var HttpClient = class {
  baseUrl;
  token;
  orgId;
  userId;
  timeoutMs;
  extraHeaders;
  fetchImpl;
  constructor(config) {
    this.baseUrl = config.baseUrl.replace(/\/$/, "");
    this.token = config.token;
    this.orgId = config.orgId;
    this.userId = config.userId;
    this.timeoutMs = config.timeoutMs ?? 3e4;
    this.extraHeaders = config.headers ?? {};
    this.fetchImpl = config.fetch ?? globalThis.fetch;
    if (!this.fetchImpl) {
      throw new Error("No fetch implementation found. Pass `fetch` in SDK config.");
    }
  }
  async request(method, path, body, options) {
    const url = this.buildUrl(path, options?.query);
    const headers = {
      Accept: "application/json",
      ...this.extraHeaders,
      ...options?.headers
    };
    if (body !== void 0) {
      headers["Content-Type"] = "application/json";
    }
    if (this.token && !headers.Authorization) {
      headers.Authorization = `Bearer ${this.token}`;
    }
    if (this.orgId && !headers[HEADER_ORG_ID]) {
      headers[HEADER_ORG_ID] = this.orgId;
    }
    if (this.userId && !headers[HEADER_USER_ID]) {
      headers[HEADER_USER_ID] = this.userId;
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    const signal = options?.signal ?? controller.signal;
    try {
      const response = await this.fetchImpl(url, {
        method,
        headers,
        body: body === void 0 ? void 0 : JSON.stringify(body),
        signal
      });
      const text = await response.text();
      const payload = text.length > 0 ? JSON.parse(text) : null;
      if (!response.ok) {
        throw new WorkflowError(`Request failed with status ${response.status}`, response.status, payload);
      }
      return this.unwrapEnvelope(payload);
    } catch (error) {
      if (error instanceof WorkflowError) {
        throw error;
      }
      throw new WorkflowError(error.message, 0, null);
    } finally {
      clearTimeout(timeout);
    }
  }
  buildUrl(path, query) {
    const normalized = path.startsWith("/") ? path : `/${path}`;
    const url = new URL(`${this.baseUrl}${normalized}`);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value === void 0 || value === null) continue;
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
          url.searchParams.set(key, String(value));
          continue;
        }
        url.searchParams.set(key, JSON.stringify(value));
      }
    }
    return url.toString();
  }
  unwrapEnvelope(payload) {
    if (payload && typeof payload === "object" && "data" in payload) {
      return payload.data;
    }
    return payload;
  }
};

// src/resources/activities.ts
var ActivitiesResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/activities", void 0, { query });
  }
  count(query) {
    return this.http.request("GET", "/v1/wf/activities/count", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/activities/${id}`);
  }
  logs(id) {
    return this.http.request("GET", `/v1/wf/activities/${id}/logs`);
  }
};

// src/resources/analytics.ts
var AnalyticsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  default() {
    return this.http.request("GET", "/v1/wf/analytics");
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/analytics/${id}`);
  }
};

// src/resources/dryRun.ts
var DryRunResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  execute(payload) {
    return this.http.request("POST", "/v1/wf/dryrun", payload);
  }
};

// src/resources/environments.ts
var EnvironmentsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/environments", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/environments/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/wf/environments", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/wf/environments/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/wf/environments/${id}`);
  }
  setDefault(id) {
    return this.http.request("PATCH", `/v1/wf/environments/${id}/default`);
  }
};

// src/resources/executions.ts
var ExecutionsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/executions", void 0, { query });
  }
  count(query) {
    return this.http.request("GET", "/v1/wf/executions/count", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/executions/${id}`);
  }
  logs(id) {
    return this.http.request("GET", `/v1/wf/executions/${id}/logs`);
  }
};

// src/resources/functions.ts
var FunctionsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/functions", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/functions/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/wf/functions", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/wf/functions/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/wf/functions/${id}`);
  }
  versions(id, query) {
    return this.http.request("GET", `/v1/wf/functions/${id}/versions`, void 0, { query });
  }
  execute(id, params) {
    return this.http.request("POST", `/v1/wf/functions/${id}/execute`, params ?? {});
  }
};

// src/resources/humanTasks.ts
var HumanTasksResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/human-tasks", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/human-tasks/${id}`);
  }
  complete(id, action) {
    return this.http.request("PATCH", `/v1/wf/human-tasks/${id}/complete`, { action });
  }
};

// src/resources/webhooks.ts
var WebhooksResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  trigger(workflowId, payload, query) {
    return this.http.request("POST", `/v1/wf/webhook/${workflowId}`, payload ?? {}, { query });
  }
  listByWorkflow(workflowId) {
    return this.http.request("GET", `/v1/wf/webhook/${workflowId}`);
  }
  create(workflowId, payload) {
    return this.http.request("POST", `/v1/wf/webhook/${workflowId}`, payload);
  }
  update(webhookId, payload) {
    return this.http.request("PUT", `/v1/wf/webhook/${webhookId}`, payload);
  }
  delete(workflowId) {
    return this.http.request("DELETE", `/v1/wf/webhook/${workflowId}`);
  }
};

// src/resources/workflows.ts
var WorkflowsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/wf/workflows", void 0, { query });
  }
  count(query) {
    return this.http.request("GET", "/v1/wf/workflows/count", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/wf/workflows/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/wf/workflows", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/wf/workflows/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/wf/workflows/${id}`);
  }
  run(payload) {
    return this.http.request("POST", "/v1/wf/workflows/run", payload);
  }
  versions(id, query) {
    return this.http.request("GET", `/v1/wf/workflows/${id}/versions`, void 0, { query });
  }
  publish(id, payload) {
    return this.http.request("POST", `/v1/wf/workflows/${id}/publish`, payload);
  }
  published(query) {
    return this.http.request("GET", "/v1/wf/workflows/published", void 0, { query });
  }
  publishedCount(query) {
    return this.http.request("GET", "/v1/wf/workflows/published/count", void 0, { query });
  }
  getPublishedById(id) {
    return this.http.request("GET", `/v1/wf/workflows/published/${id}`);
  }
  updatePublished(id, payload) {
    return this.http.request("PUT", `/v1/wf/workflows/published/${id}`, payload);
  }
  deletePublished(id) {
    return this.http.request("DELETE", `/v1/wf/workflows/published/${id}`);
  }
  webPublished(query) {
    return this.http.request("GET", "/v1/wf/workflows/published/web", void 0, { query });
  }
  webPublishedById(id) {
    return this.http.request("GET", `/v1/wf/workflows/published/web/${id}`);
  }
  searchPublishedTemplates(params) {
    return this.http.request("GET", "/v1/wf/workflows/published/web/search", void 0, { query: params });
  }
};

// src/index.ts
var WorkflowClient = class {
  workflows;
  environments;
  functions;
  executions;
  activities;
  humanTasks;
  analytics;
  dryRun;
  webhooks;
  constructor(config) {
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
};
export {
  HEADER_ORG_ID,
  HEADER_USER_ID,
  HttpClient,
  WorkflowClient,
  WorkflowError
};
