import { ExecutorClient } from "./executor.js";
import { KBClient } from "./kb.js";
import { ManagerClient } from "./manager.js";
import { Transport, type ServiceTarget } from "./transport.js";
import {
  DEFAULT_EXECUTOR_API_BASE_PATH,
  DEFAULT_KB_API_BASE_PATH,
  DEFAULT_MANAGER_API_BASE_PATH,
  HEADER_ORG_ID,
  HEADER_USER_ID,
} from "./types.js";

export { ExecutorClient, KBClient, ManagerClient };
export { tryParseMessage, type StreamEvent } from "./executor.js";

export interface AgentxClientOptions {
  /**
   * Base URL applied to all three services (e.g. "http://localhost:8080").
   * When the services live on different hosts, omit this and use the
   * `managerURL` / `kbURL` / `executorURL` per-service overrides.
   */
  baseURL?: string;
  /** Override the agent-manager base URL. */
  managerURL?: string;
  /** Override the agent-kb base URL. */
  kbURL?: string;
  /** Override the agent-executor base URL. */
  executorURL?: string;
  /** Override the agent-manager route prefix (default "/v1/agentx/manager"). */
  managerApiBasePath?: string;
  /** Override the agent-kb route prefix (default "/v1/agentx/kb"). */
  kbApiBasePath?: string;
  /** Override the agent-executor route prefix (default "/v1/agentx/executors"). */
  executorApiBasePath?: string;
  /** X-Org-Id header value. */
  orgId?: string;
  /** X-User-Id header value. */
  userId?: string;
  /** Extra headers added to every request. */
  defaultHeaders?: Record<string, string>;
  /** Custom fetch implementation (defaults to global fetch). */
  fetch?: typeof fetch;
  /**
   * Per-request timeout in milliseconds for non-streaming calls
   * (default 30 000; `0` disables). Executor `streamMessage` ignores this –
   * pass an AbortSignal to cancel a stream instead.
   */
  timeoutMs?: number;
}

/**
 * Unified agentx client.
 *
 * Wraps three sub-clients – [Manager], [KB], [Executor] – that share HTTP
 * transport, tenancy headers and request options. Pass a single `baseURL`
 * for a unified deployment, or per-service URLs when the services live on
 * different hosts.
 */
export class AgentxClient {
  private readonly headers: Record<string, string>;

  /** Agent-manager sub-client. */
  readonly Manager: ManagerClient;
  /** Agent-kb (knowledge-base) sub-client. */
  readonly KB: KBClient;
  /** Agent-executor sub-client. */
  readonly Executor: ExecutorClient;

  constructor(opts: AgentxClientOptions) {
    const managerURL = opts.managerURL ?? opts.baseURL;
    const kbURL = opts.kbURL ?? opts.baseURL;
    const executorURL = opts.executorURL ?? opts.baseURL;

    if (!managerURL || !kbURL || !executorURL) {
      throw new Error(
        "AgentxClient: every service needs a base URL – set baseURL or managerURL/kbURL/executorURL",
      );
    }

    this.headers = { ...(opts.defaultHeaders ?? {}) };
    if (opts.orgId) this.headers[HEADER_ORG_ID] = opts.orgId;
    if (opts.userId) this.headers[HEADER_USER_ID] = opts.userId;

    const transport = new Transport({
      fetch: opts.fetch ?? fetch,
      headers: this.headers,
      timeoutMs: opts.timeoutMs ?? 30_000,
    });

    const managerTarget: ServiceTarget = {
      baseURL: managerURL,
      apiBasePath: normalizePrefix(opts.managerApiBasePath ?? DEFAULT_MANAGER_API_BASE_PATH),
    };
    const kbTarget: ServiceTarget = {
      baseURL: kbURL,
      apiBasePath: normalizePrefix(opts.kbApiBasePath ?? DEFAULT_KB_API_BASE_PATH),
    };
    const executorTarget: ServiceTarget = {
      baseURL: executorURL,
      apiBasePath: normalizePrefix(opts.executorApiBasePath ?? DEFAULT_EXECUTOR_API_BASE_PATH),
    };

    this.Manager = new ManagerClient(transport, managerTarget);
    this.KB = new KBClient(transport, kbTarget);
    this.Executor = new ExecutorClient(transport, executorTarget);
  }

  setOrgId(orgId: string | null): void {
    if (orgId) this.headers[HEADER_ORG_ID] = orgId;
    else delete this.headers[HEADER_ORG_ID];
  }

  setUserId(userId: string | null): void {
    if (userId) this.headers[HEADER_USER_ID] = userId;
    else delete this.headers[HEADER_USER_ID];
  }

  /** Sets / overwrites an arbitrary default header. Pass null to delete. */
  setHeader(key: string, value: string | null): void {
    if (value === null) delete this.headers[key];
    else this.headers[key] = value;
  }
}

function normalizePrefix(p: string): string {
  return "/" + p.replace(/^\/+|\/+$/g, "");
}
