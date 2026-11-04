// Types for @lowcoai/nodes. The runtime is index.mjs (shared with the workflow
// engine's sandbox); keep these in step with it.

export type NodeInputType =
  | "string" | "textarea" | "number" | "boolean" | "options" | "radio" | "code"
  | "object" | "array" | "password" | "date" | "hidden"
  /** A connection picker: the value is a connection id, usable with ctx.http({ connection: "<input name>" }). */
  | "connection";

/** One field of a node's form, as in the Studio node builder. */
export interface NodeInputField {
  name: string;
  displayName?: string;
  type: NodeInputType;
  required?: boolean;
  default?: unknown;
  description?: string;
  placeholder?: string;
  /** A regular expression the value must match. */
  pattern?: string;
  /** For "options" and "radio". */
  options?: Array<{ id: string; label: string }>;
  /** For "connection": only connections of this application. */
  applicationId?: string;
  /** For "object": its fields. */
  schema?: Record<string, NodeInputField>;
  /** For "array": its items. */
  itemType?: { type: NodeInputType; schema?: Record<string, NodeInputField> };
  typeOptions?: Record<string, unknown>;
  visibility?: Record<string, unknown>;
  sequence?: number;
  /** Whether the designer offers {{ }} expressions for the field (default true). */
  expression?: boolean;
}

export type JSONSchema = Record<string, unknown>;

export interface HttpRequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD" | "OPTIONS" | string;
  url: string;
  headers?: Record<string, string>;
  query?: Record<string, string | number | boolean | Array<string | number | boolean> | null | undefined>;
  /** A JSON body. */
  json?: unknown;
  /** A text body (not with a connection). */
  body?: string;
  /**
   * The name of an input of type "connection": the engine adds that
   * connection's credentials outside the sandbox. Your code never sees them.
   */
  connection?: string;
  timeoutMs?: number;
  /** Default true: a non-2xx status throws a NodeError with code "http_status". */
  throwOnError?: boolean;
}

export interface HttpResponse<T = any> {
  status: number;
  ok: boolean;
  headers: Record<string, string>;
  text: string;
  json: T | null;
}

export interface NodeHttp {
  request<T = any>(opts: HttpRequestOptions): Promise<HttpResponse<T>>;
  get<T = any>(url: string, opts?: Omit<HttpRequestOptions, "url" | "method">): Promise<HttpResponse<T>>;
  delete<T = any>(url: string, opts?: Omit<HttpRequestOptions, "url" | "method">): Promise<HttpResponse<T>>;
  post<T = any>(url: string, json?: unknown, opts?: Omit<HttpRequestOptions, "url" | "method" | "json">): Promise<HttpResponse<T>>;
  put<T = any>(url: string, json?: unknown, opts?: Omit<HttpRequestOptions, "url" | "method" | "json">): Promise<HttpResponse<T>>;
  patch<T = any>(url: string, json?: unknown, opts?: Omit<HttpRequestOptions, "url" | "method" | "json">): Promise<HttpResponse<T>>;
}

export interface NodeLog {
  debug(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}

export interface NodeContext {
  /** key, version, definitionId, library, libraryVersion */
  readonly node: Readonly<Record<string, unknown>>;
  /** executionId, workflowId, activityId, label, orgId */
  readonly run: Readonly<Record<string, unknown>>;
  /** The org's environment variables (private libraries only; public ones get none). */
  readonly env: Readonly<Record<string, unknown>>;
  /** Lines land in the workflow run's trace (at most 200 per run). */
  readonly log: NodeLog;
  /** Outbound HTTP through the engine, which refuses private and cluster addresses. */
  readonly http: NodeHttp;
  /** Fail the node with a message (throws NodeError). */
  fail(message: string, opts?: NodeErrorOptions): never;
}

export type Awaitable<T> = T | Promise<T>;

export interface NodeDefinition<I = Record<string, any>, R = any, O = R> {
  /** 2-64 lowercase letters, digits and underscores, starting with a letter. Unique in your org. */
  key: string;
  name: string;
  description?: string;
  category?: string;
  icon?: string;
  color?: string;
  /** Markdown shown in the designer. */
  docs?: string;
  inputs?: NodeInputField[];
  /** JSON Schema of the output: drives designer autocomplete and run-time checks. */
  outputSchema?: JSONSchema;
  /** Fail the node (instead of warning) when the output does not match `outputSchema`. */
  strictOutput?: boolean;

  /** Normalise the inputs; return the new inputs (or nothing to keep them). */
  input?(inputs: I, ctx: NodeContext): Awaitable<I | void>;
  /** Return a problem or a list of problems to reject the inputs. */
  validate?(inputs: I, ctx: NodeContext): Awaitable<string | string[] | void | null | undefined>;
  /** Do the work. */
  run(inputs: I, ctx: NodeContext): Awaitable<R>;
  /** Shape run's result into the node's output. */
  output?(result: R, inputs: I, ctx: NodeContext): Awaitable<O>;
}

export type Node<I = Record<string, any>, R = any, O = R> = Readonly<NodeDefinition<I, R, O> & { inputs: NodeInputField[] }>;

export interface Library {
  readonly nodes: Node[];
}

export function defineNode<I = Record<string, any>, R = any, O = R>(def: NodeDefinition<I, R, O>): Node<I, R, O>;
export function defineLibrary(def: { nodes: Node<any, any, any>[] }): Library;
export function isNode(v: unknown): v is Node;
export function isLibrary(v: unknown): v is Library;
/** The nodes a library module exports (default library, default array, default node, named exports). */
export function collectNodes(mod: Record<string, unknown>): Node[];

export interface NodeErrorOptions {
  code?: string;
  details?: unknown;
  retryable?: boolean;
  cause?: unknown;
}

/** A failure the node reports; the workflow node fails with this message. */
export class NodeError extends Error {
  constructor(message: string, opts?: NodeErrorOptions);
  readonly lowcoKind: "node" | "validation";
  code?: string;
  details?: unknown;
  retryable: boolean;
}

/** Inputs that cannot be used. */
export class ValidationError extends NodeError {
  constructor(message: string, opts?: { problems?: string[]; details?: unknown });
  problems: string[];
}
