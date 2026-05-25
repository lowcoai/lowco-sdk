// src/client.ts
var HEADER_ORG_ID = "X-Org-Id";
var HEADER_USER_ID = "X-User-Id";
var IntegrationsError = class extends Error {
  status;
  payload;
  constructor(message, status, payload) {
    super(message);
    this.name = "IntegrationsError";
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
        throw new IntegrationsError(
          `Request failed with status ${response.status}`,
          response.status,
          payload
        );
      }
      return this.unwrapEnvelope(payload);
    } catch (error) {
      if (error instanceof IntegrationsError) {
        throw error;
      }
      throw new IntegrationsError(error.message, 0, null);
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

// src/resources/actions.ts
var ActionsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/integrations/actions", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/integrations/actions/${id}`);
  }
  create(applicationId, payload) {
    return this.http.request("POST", `/v1/integrations/applications/${applicationId}/action`, payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/integrations/actions/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/integrations/actions/${id}`);
  }
  listByApplication(applicationId) {
    return this.http.request("GET", `/v1/integrations/applications/${applicationId}/actions`);
  }
  run(id, payload) {
    return this.http.request("POST", `/v1/integrations/actions/${id}/run`, payload);
  }
  resolveCredentials(actionIds) {
    return this.http.request("POST", "/v1/integrations/actions/allCredential", actionIds);
  }
};

// src/resources/applications.ts
var ApplicationsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/integrations/applications", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/integrations/applications/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/integrations/applications", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/integrations/applications/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/integrations/applications/${id}`);
  }
  patchTags(id, tags) {
    const body = { tags };
    return this.http.request("PATCH", `/v1/integrations/applications/${id}/tags`, body);
  }
  run(id, payload) {
    return this.http.request("POST", `/v1/integrations/applications/${id}/run`, payload);
  }
  loadActions(id, folder) {
    return this.http.request("POST", `/v1/integrations/applications/${id}/load-actions`, folder);
  }
  versions(id, query) {
    return this.http.request("GET", `/v1/integrations/applications/${id}/versions`, void 0, { query });
  }
  regenerateMcpKey(id) {
    return this.http.request("GET", `/v1/integrations/applications/${id}/regenerate-mcp-key`);
  }
  getMcpTools(id) {
    return this.http.request("GET", `/v1/integrations/applications/${id}/mcp/tools`);
  }
  getSubApplications() {
    return this.http.request("GET", "/v1/integrations/applications/types");
  }
  getApplicationsWithTriggers() {
    return this.http.request("GET", "/v1/integrations/applications/by-trigger");
  }
};

// src/resources/configurations.ts
var ConfigurationsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  get() {
    return this.http.request("GET", "/v1/integrations/configurations");
  }
};

// src/resources/connections.ts
var ConnectionsResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  list(query) {
    return this.http.request("GET", "/v1/integrations/connections", void 0, { query });
  }
  getById(id) {
    return this.http.request("GET", `/v1/integrations/connections/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/integrations/connections", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/integrations/connections/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/integrations/connections/${id}`);
  }
  listByApplication(applicationId) {
    return this.http.request("GET", `/v1/integrations/applications/${applicationId}/connections`);
  }
  setAsDefault(id, applicationId) {
    const body = { applicationId };
    return this.http.request("PATCH", `/v1/integrations/connections/${id}/setDefault`, body);
  }
};

// src/resources/mcp.ts
var McpResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  callPublished(key, payload) {
    return this.http.request("POST", `/v1/integrations/applications/published/${key}`, payload);
  }
  infoPublished(key) {
    return this.http.request("GET", `/v1/integrations/applications/published/${key}`);
  }
};

// src/resources/oauth.ts
var OAuthResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  login(applicationId, payload) {
    return this.http.request("POST", `/v1/integrations/oauth/${applicationId}/login`, payload);
  }
  callback(payload) {
    return this.http.request("POST", "/v1/integrations/oauth/callback", payload);
  }
  getTokenByCredentialId(credentialId) {
    return this.http.request("GET", `/v1/integrations/connections/${credentialId}/token`);
  }
  refreshTokenByCredentialId(credentialId) {
    return this.http.request("POST", `/v1/integrations/connections/${credentialId}/token/refresh`);
  }
  refreshExpiringTokens() {
    return this.http.request("POST", "/v1/integrations/oauth/tokens/refresh-expiring");
  }
};

// src/resources/triggers.ts
var TriggersResource = class {
  constructor(http) {
    this.http = http;
  }
  http;
  listByApplication(applicationId, query) {
    return this.http.request(
      "GET",
      `/v1/integrations/applications/${applicationId}/triggers`,
      void 0,
      { query }
    );
  }
  getById(id) {
    return this.http.request("GET", `/v1/integrations/triggers/${id}`);
  }
  create(payload) {
    return this.http.request("POST", "/v1/integrations/triggers", payload);
  }
  update(id, payload) {
    return this.http.request("PUT", `/v1/integrations/triggers/${id}`, payload);
  }
  delete(id) {
    return this.http.request("DELETE", `/v1/integrations/triggers/${id}`);
  }
  getState(id) {
    return this.http.request("GET", `/v1/integrations/triggers/${id}/state`);
  }
};

// src/index.ts
var IntegrationsClient = class {
  applications;
  actions;
  connections;
  triggers;
  oauth;
  configurations;
  mcp;
  constructor(config) {
    const http = new HttpClient(config);
    this.applications = new ApplicationsResource(http);
    this.actions = new ActionsResource(http);
    this.connections = new ConnectionsResource(http);
    this.triggers = new TriggersResource(http);
    this.oauth = new OAuthResource(http);
    this.configurations = new ConfigurationsResource(http);
    this.mcp = new McpResource(http);
  }
};
export {
  HEADER_ORG_ID,
  HEADER_USER_ID,
  HttpClient,
  IntegrationsClient,
  IntegrationsError
};
