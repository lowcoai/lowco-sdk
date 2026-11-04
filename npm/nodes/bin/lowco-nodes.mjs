#!/usr/bin/env node
// lowco-nodes — develop, try and push Lowco node libraries.
//
//   lowco-nodes init [dir] [--key acme] [--name "Acme"]
//   lowco-nodes describe [--dir .] [--json]
//   lowco-nodes run <node> [--inputs '{"a":1}' | --inputs-file in.json] [--env-file .env] [--dir .]
//   lowco-nodes push [--changelog "..."] [--public] [--dry-run] [--dir .]
//
// push reads LOWCO_API_URL (default https://api.lowco.ai), LOWCO_ORG, and
// LOWCO_API_KEY or LOWCO_TOKEN.

import { parseArgs } from "node:util";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { MANIFEST, collectFiles, importLibrary, loadManifest, pushBody, validateLibrary } from "../lib/library.mjs";
import { describe, runNode } from "../testing.mjs";

const HELP = `lowco-nodes — develop, try and push Lowco node libraries

Commands
  init [dir]          scaffold a library (--key, --name)
  describe            list the library's nodes as the engine will see them (--json)
  run <node>          run one node locally with real HTTP (--inputs JSON, --inputs-file, --env-file)
  push                publish the library (--changelog, --public, --dry-run)

Options
  --dir <path>        the library's directory (default: current directory)

Environment (push)
  LOWCO_API_URL       default https://api.lowco.ai
  LOWCO_ORG           the org to push to
  LOWCO_API_KEY       an API key (x-api-key), or
  LOWCO_TOKEN         a bearer token
`;

const options = {
  dir: { type: "string", default: "." },
  key: { type: "string" },
  name: { type: "string" },
  json: { type: "boolean", default: false },
  inputs: { type: "string" },
  "inputs-file": { type: "string" },
  "env-file": { type: "string" },
  changelog: { type: "string", default: "" },
  public: { type: "boolean", default: false },
  "dry-run": { type: "boolean", default: false },
  help: { type: "boolean", short: "h", default: false },
};

async function main(argv) {
  const { values, positionals } = parseArgs({ args: argv, options, allowPositionals: true });
  const [command, ...rest] = positionals;
  if (values.help || !command) {
    process.stdout.write(HELP);
    return command ? 0 : 1;
  }
  switch (command) {
    case "init":
      return init(rest[0] || values.dir, values);
    case "describe":
      return describeCmd(values);
    case "run":
      return runCmd(rest[0], values);
    case "push":
      return push(values);
    default:
      throw new Error(`unknown command "${command}"\n\n${HELP}`);
  }
}

// ---- init ----

function init(dir, values) {
  const key = values.key || path.basename(path.resolve(dir)).toLowerCase().replace(/[^a-z0-9_]/g, "_").replace(/^[^a-z]+/, "") || "my_nodes";
  const name = values.name || key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  const files = {
    [MANIFEST]: JSON.stringify({ key, name, description: "", entry: "index.mjs" }, null, 2) + "\n",
    "package.json": JSON.stringify(
      { name: key.replace(/_/g, "-"), private: true, type: "module", scripts: { test: "node --test" }, devDependencies: { "@lowcoai/nodes": "^0.1.0" } },
      null,
      2,
    ) + "\n",
    "index.mjs": `import { defineNode } from "@lowcoai/nodes";

export const greet = defineNode({
  key: "${key}_greet",
  name: "Greet",
  description: "Says hello.",
  category: "${name}",
  inputs: [{ name: "name", displayName: "Name", type: "string", required: true }],
  outputSchema: { type: "object", properties: { greeting: { type: "string" } }, required: ["greeting"] },

  input: (inputs) => ({ ...inputs, name: String(inputs.name ?? "").trim() }),
  validate: (inputs) => (inputs.name ? undefined : "name is required"),
  run: async (inputs, ctx) => {
    ctx.log.info("greeting", { name: inputs.name });
    return { greeting: \`Hello, \${inputs.name}!\` };
  },
});
`,
    "test/greet.test.mjs": `import { test } from "node:test";
import assert from "node:assert/strict";
import { runNode } from "@lowcoai/nodes/testing";
import { greet } from "../index.mjs";

test("greets", async () => {
  const res = await runNode(greet, { name: "  Ada " });
  assert.equal(res.ok, true);
  assert.deepEqual(res.output, { greeting: "Hello, Ada!" });
});

test("rejects an empty name", async () => {
  const res = await runNode(greet, { name: " " });
  assert.equal(res.error.kind, "validation");
});
`,
  };
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(dir, rel);
    if (existsSync(file)) {
      console.log(`skip   ${rel} (exists)`);
      continue;
    }
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, content);
    console.log(`create ${rel}`);
  }
  console.log(`\nNext: cd ${dir} && npm install && npm test && lowco-nodes describe`);
  return 0;
}

// ---- describe ----

async function load(values) {
  const dir = path.resolve(values.dir);
  const manifest = loadManifest(dir);
  const files = collectFiles(dir, manifest);
  const problems = validateLibrary(manifest, files);
  return { dir, manifest, files, problems };
}

async function describeCmd(values) {
  const { dir, manifest, files, problems } = await load(values);
  const nodes = describe(await importLibrary(dir, manifest));
  if (values.json) {
    console.log(JSON.stringify({ library: manifest.key, files: files.map((f) => f.path), nodes, problems }, null, 2));
    return problems.length ? 1 : 0;
  }
  console.log(`${manifest.name} (${manifest.key}) — ${files.length} file(s), ${nodes.length} node(s)`);
  for (const n of nodes) {
    const handlers = ["run", ...n.handlers].join(", ");
    console.log(`  ${n.key.padEnd(28)} ${n.name}  [${handlers}]  inputs: ${n.inputs.map((i) => i.name).join(", ") || "none"}`);
  }
  if (!nodes.length) problems.push("the library declares no nodes: export nodes made with defineNode from its entry module");
  for (const p of problems) console.error(`  ✗ ${p}`);
  return problems.length ? 1 : 0;
}

// ---- run ----

function parseEnvFile(file) {
  const env = {};
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!m) continue;
    env[m[1]] = m[2].replace(/^(['"])(.*)\1$/, "$2");
  }
  return env;
}

async function runCmd(nodeKey, values) {
  if (!nodeKey) throw new Error("usage: lowco-nodes run <node> [--inputs JSON]");
  const { dir, manifest } = await load(values);
  let inputs = {};
  if (values["inputs-file"]) inputs = JSON.parse(readFileSync(values["inputs-file"], "utf8"));
  else if (values.inputs) inputs = JSON.parse(values.inputs);
  const env = values["env-file"] ? parseEnvFile(values["env-file"]) : {};
  const res = await runNode(await importLibrary(dir, manifest), inputs, {
    node: nodeKey,
    env,
    context: { node: { key: nodeKey, library: manifest.key }, run: { executionId: "local" } },
  });
  for (const l of res.logs) console.error(`[${l.level}] ${l.message}${l.fields ? " " + JSON.stringify(l.fields) : ""}`);
  for (const r of res.requests) console.error(`[http] ${r.method} ${r.url}${r.connection ? ` (connection ${r.connection})` : ""}`);
  if (!res.ok) {
    console.error(`✗ ${res.error.kind}: ${res.error.message}${res.error.code ? ` (${res.error.code})` : ""}`);
    if (res.error.details) console.error(JSON.stringify(res.error.details, null, 2));
    return 1;
  }
  console.log(JSON.stringify(res.output, null, 2));
  return 0;
}

// ---- push ----

async function push(values) {
  const { dir, manifest, files, problems } = await load(values);
  // Load it here first: a library that does not import cleanly would only
  // fail on the server.
  const nodes = describe(await importLibrary(dir, manifest));
  if (!nodes.length) problems.push("the library declares no nodes: export nodes made with defineNode from its entry module");
  if (problems.length) {
    for (const p of problems) console.error(`✗ ${p}`);
    return 1;
  }
  const body = pushBody(manifest, files, { changelog: values.changelog, visibility: values.public ? "public" : "private" });
  if (values["dry-run"]) {
    console.log(`would push ${manifest.key}: ${files.length} file(s), ${nodes.length} node(s)`);
    for (const f of files) console.log(`  ${f.path}  ${Buffer.byteLength(f.content)} B`);
    return 0;
  }

  const base = (process.env.LOWCO_API_URL || "https://api.lowco.ai").replace(/\/+$/, "");
  const org = process.env.LOWCO_ORG;
  if (!org) throw new Error("set LOWCO_ORG to the org to push to");
  const headers = { "content-type": "application/json", accept: "application/json", "x-org-id": org };
  if (process.env.LOWCO_API_KEY) headers["x-api-key"] = process.env.LOWCO_API_KEY;
  else if (process.env.LOWCO_TOKEN) headers.authorization = `Bearer ${process.env.LOWCO_TOKEN}`;
  else throw new Error("set LOWCO_API_KEY (or LOWCO_TOKEN) to push");

  const res = await fetch(`${base}/v1/wf/node-libraries/push`, { method: "POST", headers, body: JSON.stringify(body) });
  const text = await res.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = null;
  }
  if (!res.ok) {
    const msg = payload?.error?.message || text || res.statusText;
    console.error(`✗ push failed (${res.status}): ${msg}`);
    return 1;
  }
  const out = payload?.data || payload;
  if (values.json) {
    console.log(JSON.stringify(out, null, 2));
    return 0;
  }
  console.log(out.unchanged ? `${manifest.key}: unchanged (version ${out.version?.version})` : `${manifest.key}: published version ${out.version?.version}`);
  for (const n of out.nodes || []) console.log(`  ${n.status.padEnd(9)} ${n.key.padEnd(28)} definition ${n.definitionId} v${n.version}`);
  for (const k of out.removed || []) console.log(`  removed   ${k} (deprecated; pinned workflows keep running)`);
  return 0;
}

main(process.argv.slice(2)).then(
  (code) => process.exit(code ?? 0),
  (e) => {
    console.error(`✗ ${e.message}`);
    process.exit(1);
  },
);
