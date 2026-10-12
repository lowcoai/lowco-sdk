import type { Library, Node, NodeInputField, JSONSchema } from "./index.js";

export interface NodeDeclaration {
  key: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  color: string;
  docs: string;
  inputs: NodeInputField[];
  output: JSONSchema | null;
  strictOutput: boolean;
  handlers: Array<"input" | "validate" | "output">;
}

export interface RelayedRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
  query: Record<string, unknown>;
  json?: unknown;
  body?: string;
  connection?: string;
  timeoutMs?: number;
}

export interface MockResponse {
  status?: number;
  json?: unknown;
  body?: string;
  headers?: Record<string, string>;
}

export interface RunOptions {
  /** The node's key, when the target holds several. */
  node?: string;
  env?: Record<string, unknown>;
  context?: { node?: Record<string, unknown>; run?: Record<string, unknown> };
  /** A mock for ctx.http, or "live" (default) for real requests. */
  http?: ((req: RelayedRequest) => MockResponse | void | Promise<MockResponse | void>) | "live";
  /** Live requests: the headers standing in for each connection input. */
  connections?: Record<string, { headers?: Record<string, string> }>;
}

export interface RunFailure {
  kind: "validation" | "node" | "internal";
  message: string;
  code: string | null;
  details: any;
  retryable: boolean;
}

export interface RunResult<O = any> {
  ok: boolean;
  output?: O;
  error?: RunFailure;
  logs: Array<{ level: string; message: string; fields?: Record<string, unknown> }>;
  requests: RelayedRequest[];
}

type Target = Node<any, any, any> | Library | Node<any, any, any>[] | Record<string, unknown>;

export function describe(target: Target): NodeDeclaration[];
export function runNode<O = any>(target: Target, inputs?: Record<string, unknown>, options?: RunOptions): Promise<RunResult<O>>;
