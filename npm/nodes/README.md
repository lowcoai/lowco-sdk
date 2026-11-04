# @lowcoai/nodes

Write Lowco workflow nodes in JavaScript. A **node library** is a small package of nodes. You test it locally, then push it to your org. Each node then shows up in the Studio designer like any other node.

```js
import { defineNode, NodeError } from "@lowcoai/nodes";

export const createContact = defineNode({
  key: "acme_create_contact",
  name: "Create contact",
  category: "Acme CRM",
  inputs: [
    { name: "crm", displayName: "Acme CRM account", type: "connection", required: true },
    { name: "email", displayName: "Email", type: "string", required: true },
  ],
  outputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },

  input: (inputs) => ({ ...inputs, email: inputs.email.trim().toLowerCase() }),
  validate: (inputs) => (inputs.email.includes("@") ? undefined : "email is not an email address"),
  run: async (inputs, ctx) => {
    const res = await ctx.http.post("https://api.acme-crm.example/v1/contacts", { email: inputs.email }, { connection: "crm" });
    return res.json;
  },
  output: (contact) => ({ id: contact.id }),
});
```

## How a node runs

Every run of a node goes through four handlers, in order. Only `run` is required.

| Handler | Signature | Purpose |
|---|---|---|
| `input` | `(inputs, ctx) → inputs` | Normalise the resolved inputs (trim, coerce, default). Return the new inputs. |
| `validate` | `(inputs, ctx) → string \| string[] \| void` | Return a problem, or a list of problems, to reject the inputs. The node then fails with `input.invalid` and the problems. You can also throw a `ValidationError`. |
| `run` | `(inputs, ctx) → result` | Do the work. |
| `output` | `(result, inputs, ctx) → output` | Shape the result into the node's output. |

Before your handlers run, the engine resolves `{{ }}` expressions in the inputs and checks them against `inputs`. After they finish, it checks the output against `outputSchema`. A mismatch only warns, unless `strictOutput: true` makes it fail the node.

### Failures

- `throw new NodeError(message, { code, details, retryable })`, or `ctx.fail(message, opts)`, fails the node with your message. The node error code is `node.reported`; your `code` and `details` appear in the run.
- `throw new ValidationError(message, { problems })` is reported as invalid inputs.
- Anything else you throw is reported with its stack trace.

### `ctx`

| | |
|---|---|
| `ctx.http` | `request({ method, url, headers, query, json, body, connection, timeoutMs, throwOnError })`, plus `get`, `delete`, `post`, `put` and `patch`. A non-2xx status throws a `NodeError` with code `http_status` unless you pass `throwOnError: false`. |
| `ctx.log` | `debug`, `info`, `warn` and `error(message, fields)`. Lines land in the run's trace (at most 200 per run). |
| `ctx.env` | Your org's environment variables. Libraries published as **public** (platform libraries) get none. |
| `ctx.node` / `ctx.run` | The node's key, version and library; the run's execution id, workflow id and org id. |

### HTTP and connections

Your code runs in a sandbox with **no network**. `ctx.http` calls go through the workflow engine, which:

- refuses private, loopback, link-local and cluster-internal destinations, redirects to them included;
- for `connection: "<input name>"`, adds the credentials of the connection the workflow author picked for that input. Your code never sees them. Declare the input with `type: "connection"`. A request through a connection takes a JSON body.

Each request may take up to 120 s (30 s by default) and return up to 10 MiB. The whole run is limited by the library's `timeoutSeconds` (30 s by default).

## A library

```
my-library/
  lowco-nodes.json     manifest
  package.json         optional; its "dependencies" become the library's
  index.mjs            entry: exports the nodes
  nodes/*.mjs          any layout; relative imports work
  test/*.test.mjs      local tests (not uploaded)
```

`lowco-nodes.json`:

```json
{
  "key": "acme_crm",
  "name": "Acme CRM",
  "description": "Contacts and lead scoring for the Acme CRM API.",
  "entry": "index.mjs",
  "timeoutSeconds": 20,
  "dependencies": { "dayjs": "1.11.13" }
}
```

- **Exports.** The entry module exports nodes made with `defineNode`, either as named exports, as a default array, or as `export default defineLibrary({ nodes: [...] })`.
- **Dependencies.** These are npm packages pinned to exact versions. When `dependencies` is missing, the CLI uses `package.json`'s instead. The sandbox installs them; `@lowcoai/nodes` is always provided.
- **Uploaded files.** Every `.mjs`, `.js`, `.cjs`, `.json`, `.md` and `.txt` file is uploaded, except `node_modules`, hidden files, tests and lock files. To upload only some of them, list them in `"files": ["index.mjs", "nodes"]`.
- **Limits.** At most 300 files, 2 MiB in total and 512 KiB per file, 40 dependencies and 100 nodes.
- **Node keys** are unique in your org. A push is refused when a key is already used by a node built in the Studio node builder, or by another library.

## Test locally

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { runNode, describe } from "@lowcoai/nodes/testing";
import { createContact } from "../nodes/create-contact.mjs";

test("creates a contact", async () => {
  const res = await runNode(createContact, { crm: "conn_1", email: " Ada@Example.com" }, {
    http: (req) => ({ status: 201, json: { id: "c_1", email: req.json.email } }),
  });
  assert.equal(res.ok, true);
  assert.deepEqual(res.output, { id: "c_1" });
  assert.equal(res.requests[0].connection, "crm");
});
```

`runNode(target, inputs, options)` runs the same pipeline as the engine. It returns `{ ok, output, error, logs, requests }`.

- **`target`** is a node, a library, or a module namespace. When the target holds several nodes, name one with `options.node`.
- **`options.http`** is a mock, `(req) => ({ status, json, body, headers })`. When you leave it out, requests are made for real, and a connection is whatever headers you hand in with `options.connections: { crm: { headers: { Authorization: "Bearer …" } } }`.
- **`options.env`** and **`options.context`** set `ctx.env`, `ctx.node` and `ctx.run`.

Two things differ from a real run. A local run makes HTTP requests directly, so private addresses are not refused. And connections are your stand-ins, not the org's.

## CLI

```bash
npx lowco-nodes init my-library --key acme_crm   # scaffold
npx lowco-nodes describe                         # the nodes, as the engine will read them
npx lowco-nodes run acme_score_lead --inputs '{"employees": 40}' --env-file .env
npx lowco-nodes push --changelog "Lead scoring"  # publish
```

`push` reads these environment variables:

- `LOWCO_API_URL` (default `https://api.lowco.ai`)
- `LOWCO_ORG`
- `LOWCO_API_KEY`, or `LOWCO_TOKEN`

The caller needs the `workflow.node-definitions.core.execute` permission. `--public` publishes a platform library and works only for the platform org, with `workflow.node-definitions.public.write`. `--dry-run` lists what would be uploaded.

## Versions

Each push with changed code (or a changed name, description, dependencies or timeout) publishes a new immutable library version. It also publishes a new version of each node's definition, pinned to that library version. Pushing identical code changes nothing, and it repairs the node definitions if an earlier push stopped halfway. A node you remove from the library has its definition deprecated. Workflows always run the version they pinned, so existing workflows keep working until someone upgrades the node in the designer.

## Developing this package

`index.mjs` and `runtime.mjs` are copies of the engine's `workflow-core/services/workflow/coderuntime/js`, in the workflow repo. That code ships into every sandbox run. Change it there, then run `npm run sync`. The script looks for the workflow repo next to `lowco-sdk`; set `LOWCO_WORKFLOW` to point it elsewhere. `npm test` fails while the copies are stale, and so does the engine's `TestSDKPackageInSync`. Without the workflow repo, the check is skipped.
