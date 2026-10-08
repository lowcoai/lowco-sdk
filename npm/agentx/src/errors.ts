/**
 * Thrown for HTTP-level non-2xx responses from any agentx service.
 *
 * `statusCode` is always set. `message` and `code` are populated when the
 * service returns its standard JSON error envelope; otherwise `message`
 * falls back to the raw response text and `code` is undefined.
 *
 * JSON-RPC level errors from the executor are surfaced inside the `error`
 * field of [JSONRPCResponse], not thrown.
 */
export class AgentxError extends Error {
  readonly statusCode: number;
  readonly code?: string;
  readonly body: string;

  constructor(opts: { statusCode: number; message: string; code?: string; body: string }) {
    super(opts.message || `agentx: status=${opts.statusCode}`);
    this.name = "AgentxError";
    this.statusCode = opts.statusCode;
    this.code = opts.code;
    this.body = opts.body;
  }
}
