import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, symlinkSync, mkdirSync } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { collectFiles, loadManifest, validateLibrary } from "../lib/library.mjs";

const pkg = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(pkg, "bin", "lowco-nodes.mjs");
const example = path.join(pkg, "examples", "acme-crm");

function scratch() {
  const dir = mkdtempSync(path.join(os.tmpdir(), "lowco-nodes-"));
  return { dir, done: () => rmSync(dir, { recursive: true, force: true }) };
}

// A scaffolded library resolves @lowcoai/nodes from its node_modules, as after npm install.
function linkSDK(dir) {
  mkdirSync(path.join(dir, "node_modules", "@lowcoai"), { recursive: true });
  symlinkSync(pkg, path.join(dir, "node_modules", "@lowcoai", "nodes"), "dir");
}

test("the example library's files and manifest pass the engine's checks", () => {
  const m = loadManifest(example);
  const files = collectFiles(example, m);
  assert.deepEqual(files.map((f) => f.path), ["index.mjs", "lowco-nodes.json", "nodes/create-contact.mjs", "nodes/score-lead.mjs"]);
  assert.deepEqual(validateLibrary(m, files), []);
});

test("validateLibrary mirrors the engine's rules", () => {
  const files = [{ path: "index.mjs", content: "" }];
  assert.deepEqual(validateLibrary({ key: "ok_lib", name: "Ok", entry: "index.mjs" }, files), []);
  const problems = validateLibrary({ key: "Bad", name: "", entry: "main.ts", dependencies: { ms: "^2.1.3", "Bad Name": "1.0.0" } }, files);
  assert.equal(problems.length, 5, problems.join("\n"));
  assert.ok(problems.some((p) => p.includes("ms@^2.1.3 must be pinned")));
});

test("init scaffolds a library whose own tests pass and that describes cleanly", () => {
  const { dir, done } = scratch();
  try {
    execFileSync("node", [cli, "init", dir, "--key", "demo_nodes"], { encoding: "utf8" });
    linkSDK(dir);
    const test = spawnSync("node", ["--test"], { cwd: dir, encoding: "utf8" });
    assert.equal(test.status, 0, test.stdout + test.stderr);
    const out = execFileSync("node", [cli, "describe", "--dir", dir, "--json"], { encoding: "utf8" });
    const d = JSON.parse(out);
    assert.equal(d.nodes[0].key, "demo_nodes_greet");
    assert.deepEqual(d.problems, []);
    assert.deepEqual(d.files, ["index.mjs", "lowco-nodes.json", "package.json"]);
  } finally {
    done();
  }
});

test("run executes a node locally", () => {
  const out = execFileSync("node", [cli, "run", "acme_score_lead", "--dir", example, "--inputs", '{"employees":10,"industry":"retail"}'], { encoding: "utf8" });
  assert.deepEqual(JSON.parse(out), { score: 14, grade: "D" });
  const bad = spawnSync("node", [cli, "run", "acme_score_lead", "--dir", example, "--inputs", '{"employees":-1}'], { encoding: "utf8" });
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /validation: employees must be a number/);
});

function runAsync(args, env) {
  return new Promise((resolve) => {
    const child = spawn("node", args, { env: { ...process.env, ...env } });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c) => (stdout += c));
    child.stderr.on("data", (c) => (stderr += c));
    child.on("close", (status) => resolve({ status, stdout, stderr }));
  });
}

test("push sends the library with the org and credentials, and reports the result", async () => {
  let got;
  let answer = { status: 201, body: { data: { version: { version: 3 }, nodes: [{ key: "acme_score_lead", status: "updated", definitionId: "d1", version: 3 }], removed: ["old_node"], unchanged: false } } };
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      got = { path: req.url, org: req.headers["x-org-id"], key: req.headers["x-api-key"], body: JSON.parse(body) };
      res.writeHead(answer.status, { "content-type": "application/json" });
      res.end(JSON.stringify(answer.body));
    });
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const env = { LOWCO_API_URL: `http://127.0.0.1:${server.address().port}`, LOWCO_ORG: "org-7", LOWCO_API_KEY: "key-1", LOWCO_TOKEN: "" };
  try {
    const ok = await runAsync([cli, "push", "--dir", example, "--changelog", "better scoring"], env);
    assert.equal(ok.status, 0, ok.stderr);
    assert.equal(got.path, "/v1/wf/node-libraries/push");
    assert.equal(got.org, "org-7");
    assert.equal(got.key, "key-1");
    assert.equal(got.body.manifest.key, "acme_crm");
    assert.equal(got.body.changelog, "better scoring");
    assert.equal(got.body.visibility, "private");
    assert.equal(got.body.files.length, 4);
    assert.match(ok.stdout, /published version 3/);
    assert.match(ok.stdout, /removed\s+old_node/);

    answer = { status: 409, body: { error: { message: "node acme_score_lead: the org already has a node definition with key" } } };
    const conflict = await runAsync([cli, "push", "--dir", example], env);
    assert.equal(conflict.status, 1);
    assert.match(conflict.stderr, /push failed \(409\): node acme_score_lead/);

    const noOrg = await runAsync([cli, "push", "--dir", example], { ...env, LOWCO_ORG: "" });
    assert.equal(noOrg.status, 1);
    assert.match(noOrg.stderr, /LOWCO_ORG/);
  } finally {
    server.close();
  }
});
