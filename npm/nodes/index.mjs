// @lowcoai/nodes — define custom workflow nodes in code.
//
// This file is both the module node libraries import (`import { defineNode }
// from "@lowcoai/nodes"`, supplied to every sandbox run) and the published npm
// package's entry. Keep it dependency-free.

const NODE = Symbol.for("lowco.node");
const LIBRARY = Symbol.for("lowco.library");
const KEY_RE = /^[a-z][a-z0-9_]{1,63}$/;
const HANDLERS = ["input", "validate", "run", "output"];

/**
 * Declare a node. `key`, `name` and `run` are required; `inputs` is the node's
 * form (same field format as the Studio node builder) and `outputSchema` the
 * JSON Schema of what it returns.
 *
 * Handlers, in the order they run:
 *   input(inputs, ctx)            normalise inputs; return the new inputs
 *   validate(inputs, ctx)         return a message or a list of messages
 *                                 (or throw ValidationError) to reject inputs
 *   run(inputs, ctx)              do the work; return the result
 *   output(result, inputs, ctx)   shape the result into the node's output
 */
export function defineNode(def) {
  if (!def || typeof def !== "object") throw new TypeError("defineNode needs an object");
  if (!KEY_RE.test(def.key || "")) {
    throw new TypeError(`node key "${def.key}" must be 2-64 lowercase letters, digits and underscores, starting with a letter`);
  }
  if (!def.name) throw new TypeError(`node ${def.key} needs a name`);
  if (typeof def.run !== "function") throw new TypeError(`node ${def.key} needs a run(inputs, ctx) handler`);
  for (const h of HANDLERS) {
    if (def[h] !== undefined && typeof def[h] !== "function") {
      const hint = h === "output" ? " (the output's JSON Schema goes in outputSchema)" : "";
      throw new TypeError(`node ${def.key}: ${h} must be a handler function${hint}`);
    }
  }
  if (def.inputs !== undefined && !Array.isArray(def.inputs)) throw new TypeError(`node ${def.key}: inputs must be an array`);
  if (def.outputSchema !== undefined && (def.outputSchema === null || typeof def.outputSchema !== "object" || Array.isArray(def.outputSchema))) {
    throw new TypeError(`node ${def.key}: outputSchema must be a JSON Schema object`);
  }
  return Object.freeze({ ...def, inputs: def.inputs ?? [], [NODE]: true });
}

/** Group nodes into the library a module exports by default. */
export function defineLibrary(def) {
  const nodes = (def && def.nodes) || [];
  if (!Array.isArray(nodes)) throw new TypeError("defineLibrary: nodes must be an array");
  nodes.forEach((n, i) => {
    if (!isNode(n)) throw new TypeError(`defineLibrary: nodes[${i}] was not made with defineNode`);
  });
  return Object.freeze({ nodes, [LIBRARY]: true });
}

export function isNode(v) {
  return !!v && typeof v === "object" && v[NODE] === true;
}

export function isLibrary(v) {
  return !!v && typeof v === "object" && v[LIBRARY] === true;
}

/** A failure the node reports. It fails the workflow node with this message. */
export class NodeError extends Error {
  constructor(message, { code, details, retryable = false, cause } = {}) {
    super(message, cause ? { cause } : undefined);
    this.name = "NodeError";
    this.lowcoKind = "node";
    this.code = code;
    this.details = details;
    this.retryable = retryable;
  }
}

/** Inputs that cannot be used. Thrown from validate (or input/run). */
export class ValidationError extends NodeError {
  constructor(message, { problems, details } = {}) {
    super(message, { code: "validation", details });
    this.name = "ValidationError";
    this.lowcoKind = "validation";
    this.problems = problems ?? [message];
  }
}

/** The nodes a library module exports, by key. */
export function collectNodes(mod) {
  const found = new Map();
  const add = (n) => {
    if (!isNode(n)) return;
    const seen = found.get(n.key);
    if (seen && seen !== n) throw new TypeError(`two nodes use the key "${n.key}"`);
    found.set(n.key, n);
  };
  const def = mod && mod.default;
  if (isLibrary(def)) def.nodes.forEach(add);
  else if (Array.isArray(def)) def.forEach(add);
  else add(def);
  for (const [name, value] of Object.entries(mod || {})) {
    if (name !== "default") add(value);
  }
  return [...found.values()];
}
