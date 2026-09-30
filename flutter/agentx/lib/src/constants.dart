/// The fixed API host every lowco SDK talks to.
const String lowcoBaseUrl = 'https://api.lowco.ai';

/// Header carrying the organization id.
const String headerOrgId = 'X-Org-Id';

/// Default route prefix of the agent-manager service.
const String defaultManagerApiBasePath = '/v1/agentx/manager';

/// Default route prefix of the agent-kb (knowledge-base) service.
const String defaultKbApiBasePath = '/v1/agentx/kb';

/// Default route prefix of the agent-executor service.
const String defaultExecutorApiBasePath = '/v1/agentx/executors';

/// The only JSON-RPC method handled by the executor today.
const String methodMessageSend = 'message/send';
