// Reading a node library from disk the way the engine will see it: the
// lowco-nodes.json manifest, the files a push uploads, and the same checks the
// engine applies (workflow-core/.../coderuntime/library.go), so a push fails
// here, with the same message, rather than on the server.

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export const MANIFEST = "lowco-nodes.json";

export const LIMITS = Object.freeze({ files: 300, totalBytes: 2 << 20, fileBytes: 512 << 10, dependencies: 40 });

const KEY_RE = /^[a-z][a-z0-9_]{1,63}$/;
const NPM_NAME_RE = /^(@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/;
const EXACT_VERSION_RE = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;
const ALLOWED_EXT = new Set([".mjs", ".js", ".cjs", ".json", ".md", ".txt"]);
// Uploaded only when listed in manifest.files: tests run locally, lock files
// describe node_modules, which the sandbox installs itself.
const SKIPPED = [/(^|\/)test\//, /\.test\.[cm]?js$/, /\.spec\.[cm]?js$/, /(^|\/)package-lock\.json$/, /(^|\/)npm-shrinkwrap\.json$/];

/**
 * Load the manifest in dir. Dependencies default to package.json's
 * "dependencies" (minus the SDK itself, which the engine supplies — under
 * either of its names, since libraries predating the rename list the old one).
 */
export function loadManifest(dir) {
  const file = path.join(dir, MANIFEST);
  if (!existsSync(file)) throw new Error(`${MANIFEST} not found in ${dir} (run lowco-nodes init)`);
  let m;
  try {
    m = JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    throw new Error(`${MANIFEST}: ${e.message}`);
  }
  m.entry = m.entry || "index.mjs";
  if (!m.dependencies) {
    const pkgFile = path.join(dir, "package.json");
    if (existsSync(pkgFile)) {
      const deps = { ...(JSON.parse(readFileSync(pkgFile, "utf8")).dependencies || {}) };
      delete deps["@lowcoai/nodes"];
      delete deps["@lowco/nodes"];
      if (Object.keys(deps).length) m.dependencies = deps;
    }
  }
  return m;
}

/** The files a push uploads, sorted, as { path, content }. */
export function collectFiles(dir, manifest) {
  const roots = manifest.files && manifest.files.length ? manifest.files : ["."];
  const explicit = new Set();
  const found = new Map();
  for (const r of roots) {
    const abs = path.resolve(dir, r);
    if (!abs.startsWith(path.resolve(dir))) throw new Error(`files: ${r} is outside the library`);
    if (!existsSync(abs)) throw new Error(`files: ${r} does not exist`);
    if (statSync(abs).isDirectory()) walk(abs, dir, found);
    else {
      const rel = toRel(dir, abs);
      explicit.add(rel);
      found.set(rel, abs);
    }
  }
  const files = [];
  for (const [rel, abs] of found) {
    if (!explicit.has(rel) && SKIPPED.some((re) => re.test(rel))) continue;
    files.push({ path: rel, content: readFileSync(abs, "utf8") });
  }
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return files;
}

function walk(absDir, root, found) {
  for (const entry of readdirSync(absDir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
    const abs = path.join(absDir, entry.name);
    if (entry.isDirectory()) walk(abs, root, found);
    else if (entry.isFile() && ALLOWED_EXT.has(path.extname(entry.name))) found.set(toRel(root, abs), abs);
  }
}

function toRel(root, abs) {
  return path.relative(root, abs).split(path.sep).join("/");
}

/** The engine's checks; returns a list of problems (empty when fine). */
export function validateLibrary(m, files) {
  const problems = [];
  if (!KEY_RE.test(m.key || "")) problems.push(`library key "${m.key}" must be 2-64 lowercase letters, digits and underscores, starting with a letter`);
  if (!String(m.name || "").trim()) problems.push("library name is required");
  if (!files.length) problems.push("the library has no files");
  if (files.length > LIMITS.files) problems.push(`a library may have at most ${LIMITS.files} files, got ${files.length}`);
  const deps = Object.entries(m.dependencies || {});
  if (deps.length > LIMITS.dependencies) problems.push(`a library may have at most ${LIMITS.dependencies} dependencies`);
  for (const [name, version] of deps) {
    if (!NPM_NAME_RE.test(name)) problems.push(`dependency "${name}" is not an npm package name`);
    else if (!EXACT_VERSION_RE.test(String(version))) problems.push(`dependency ${name}@${version} must be pinned to an exact version (e.g. 1.2.3)`);
  }
  let total = 0;
  for (const f of files) {
    const bytes = Buffer.byteLength(f.content);
    if (bytes > LIMITS.fileBytes) problems.push(`file ${f.path} is larger than ${LIMITS.fileBytes >> 10} KiB`);
    total += bytes;
  }
  if (total > LIMITS.totalBytes) problems.push(`the library is larger than ${LIMITS.totalBytes >> 20} MiB`);
  const entry = String(m.entry || "").replace(/^\.\//, "");
  if (![".mjs", ".js"].includes(path.extname(entry))) problems.push(`entry ${entry} must be an ES module (.mjs or .js)`);
  else if (!files.some((f) => f.path === entry)) problems.push(`entry ${entry} is not among the uploaded files`);
  if (m.timeoutSeconds !== undefined && !(Number.isInteger(m.timeoutSeconds) && m.timeoutSeconds > 0)) {
    problems.push("timeoutSeconds must be a positive integer");
  }
  return problems;
}

/** Import the library's entry module (for describe and local runs). */
export async function importLibrary(dir, manifest) {
  const entry = path.resolve(dir, manifest.entry);
  return import(pathToFileURL(entry).href);
}

/** The body of POST /v1/wf/node-libraries/push. */
export function pushBody(manifest, files, { changelog = "", visibility = "private" } = {}) {
  const { files: _globs, ...rest } = manifest;
  return {
    manifest: { ...rest, entry: String(manifest.entry).replace(/^\.\//, "") },
    files,
    changelog,
    visibility,
  };
}
