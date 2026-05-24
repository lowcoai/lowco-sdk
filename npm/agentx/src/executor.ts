import { AgentxError } from "./errors.js";
import { buildHttpError, type ServiceTarget, type Transport } from "./transport.js";
import {
  METHOD_MESSAGE_SEND,
  type A2AMessage,
  type JSONRPCRequest,
  type JSONRPCResponse,
  type MessageSendParams,
} from "./types.js";

/**
 * A single SSE event delivered by [ExecutorClient.streamMessage]. `data` is
 * the raw JSON payload of the event, which is typically an [A2AMessage] but
 * may also be a tool/status frame. Call [tryParseMessage] for a Message-typed view.
 */
export interface StreamEvent {
  data: string;
}

export function tryParseMessage(ev: StreamEvent): A2AMessage | null {
  try {
    return JSON.parse(ev.data) as A2AMessage;
  } catch {
    return null;
  }
}

/** Exposes the agent-executor service routes. */
export class ExecutorClient {
  constructor(
    private readonly transport: Transport,
    private readonly target: ServiceTarget,
  ) {}

  private path(...parts: string[]): string {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }

  // --- Health ------------------------------------------------------------

  async health(): Promise<void> {
    const resp = await this.transport.sendRaw(this.target, {
      method: "GET",
      path: "/health",
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw buildHttpError(resp.status, text);
    }
  }

  // --- Synchronous send -------------------------------------------------

  /**
   * Performs a synchronous `message/send` call. The JSON-RPC id doubles as
   * the target agent identifier (matching the service convention).
   */
  async sendMessage<T = unknown>(agentId: string, params: MessageSendParams): Promise<JSONRPCResponse<T>> {
    const req: JSONRPCRequest = {
      jsonrpc: "2.0",
      method: METHOD_MESSAGE_SEND,
      params,
      id: agentId,
    };
    const resp = await this.transport.sendRaw(this.target, {
      method: "POST",
      path: this.path("execute"),
      body: req,
    });
    const text = await resp.text();
    if (!resp.ok) {
      throw buildHttpError(resp.status, text);
    }
    if (resp.status === 204 || text.trim().length === 0) {
      return { jsonrpc: "2.0", id: agentId } as JSONRPCResponse<T>;
    }
    return JSON.parse(text) as JSONRPCResponse<T>;
  }

  // --- Streaming send ---------------------------------------------------

  /**
   * Streams a `message/send` call, yielding one [StreamEvent] per SSE event
   * the server emits. Pass an AbortSignal to cancel mid-stream.
   *
   * ```ts
   * for await (const ev of client.Executor.streamMessage(agentId, params)) {
   *   const msg = tryParseMessage(ev);
   *   if (msg) console.log("delta:", msg);
   *   else console.log("raw:", ev.data);
   * }
   * ```
   */
  async *streamMessage(
    agentId: string,
    params: MessageSendParams,
    options: { signal?: AbortSignal } = {},
  ): AsyncGenerator<StreamEvent, void, void> {
    const req: JSONRPCRequest = {
      jsonrpc: "2.0",
      method: METHOD_MESSAGE_SEND,
      params,
      id: agentId,
    };
    const resp = await this.transport.sendRaw(this.target, {
      method: "POST",
      path: this.path("execute"),
      body: req,
      accept: "text/event-stream",
      signal: options.signal,
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw buildHttpError(resp.status, text);
    }
    if (!resp.body) {
      throw new AgentxError({
        statusCode: resp.status,
        message: "streamMessage: response has no body",
        body: "",
      });
    }

    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          const trailing = collectDataLines(buffer);
          if (trailing !== null) yield { data: trailing };
          return;
        }
        buffer += decoder.decode(value, { stream: true });

        let idx: number;
        while ((idx = indexOfEventBoundary(buffer)) !== -1) {
          const rawEvent = buffer.slice(0, idx);
          buffer = buffer.slice(idx).replace(/^(\r?\n){2}/, "");
          const data = collectDataLines(rawEvent);
          if (data !== null) yield { data };
        }
      }
    } finally {
      try {
        reader.releaseLock();
      } catch {
        /* ignore */
      }
    }
  }
}

function indexOfEventBoundary(buf: string): number {
  const a = buf.indexOf("\n\n");
  const b = buf.indexOf("\r\n\r\n");
  if (a === -1) return b;
  if (b === -1) return a;
  return Math.min(a, b);
}

function collectDataLines(eventChunk: string): string | null {
  const lines = eventChunk.split(/\r?\n/);
  const data: string[] = [];
  for (const line of lines) {
    if (line.startsWith("data:")) {
      const stripped = line.slice(5).replace(/^\s/, "");
      data.push(stripped);
    }
  }
  if (data.length === 0) return null;
  return data.join("\n");
}
