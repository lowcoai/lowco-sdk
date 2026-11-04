// The SDK and the node pipeline are owned by the workflow engine, which ships
// them into every sandbox run (workflow-core/.../coderuntime/js in the
// workflow repo). This copies them into the package, so what a developer
// tests locally is what runs.
//
//   node scripts/sync.mjs           copy
//   node scripts/sync.mjs --check   fail if the copies are stale
//
// LOWCO_WORKFLOW is the workflow repo; it defaults to a checkout next to
// lowco-sdk.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const workflow = process.env.LOWCO_WORKFLOW || path.join(root, "..", "..", "..", "workflow");
const source = path.join(workflow, "workflow-core", "services", "workflow", "coderuntime", "js");

// In the sandbox the runtime imports the SDK as an installed package; here
// they sit side by side.
const SANDBOX_IMPORT = `"../node_modules/@lowcoai/nodes/index.mjs"`;

const copies = [
  { from: "nodes.mjs", to: "index.mjs", transform: (s) => s },
  {
    from: "runtime.mjs",
    to: "runtime.mjs",
    transform: (s) => {
      if (!s.includes(SANDBOX_IMPORT)) throw new Error(`runtime.mjs no longer imports ${SANDBOX_IMPORT}; update scripts/sync.mjs`);
      return s.replace(SANDBOX_IMPORT, `"./index.mjs"`);
    },
  },
];

const check = process.argv.includes("--check");
if (!existsSync(source)) {
  console.error(`engine sources not found at ${source}`);
  process.exit(check ? 0 : 1); // a published copy has nothing to compare against
}
let stale = 0;
for (const c of copies) {
  const want = c.transform(readFileSync(path.join(source, c.from), "utf8"));
  const target = path.join(root, c.to);
  const have = existsSync(target) ? readFileSync(target, "utf8") : null;
  if (have === want) continue;
  if (check) {
    console.error(`${c.to} differs from the engine's ${c.from}: run npm run sync`);
    stale++;
  } else {
    writeFileSync(target, want);
    console.log(`updated ${c.to}`);
  }
}
process.exit(stale ? 1 : 0);
