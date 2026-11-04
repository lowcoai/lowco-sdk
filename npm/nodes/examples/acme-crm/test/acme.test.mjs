import { test } from "node:test";
import assert from "node:assert/strict";
import { describe, runNode } from "@lowcoai/nodes/testing";
import library from "../index.mjs";

test("the library declares its nodes", () => {
  const nodes = describe(library);
  assert.deepEqual(nodes.map((n) => n.key), ["acme_create_contact", "acme_score_lead"]);
  assert.deepEqual(nodes[0].handlers, ["input", "validate", "output"]);
});

test("create contact: normalises, posts through the connection, shapes the output", async () => {
  const res = await runNode(library, { crm: "conn_1", email: "  Ada@Example.com ", tags: "vip, beta" }, {
    node: "acme_create_contact",
    http: (req) => ({ status: 201, json: { id: "c_1", email: req.json.email } }),
  });
  assert.equal(res.ok, true, JSON.stringify(res.error));
  assert.deepEqual(res.output, { id: "c_1", email: "ada@example.com", created: true });
  assert.equal(res.requests.length, 1);
  assert.equal(res.requests[0].connection, "crm");
  assert.deepEqual(res.requests[0].json.tags, ["vip", "beta"]);
});

test("create contact: an existing email returns that contact", async () => {
  const res = await runNode(library, { crm: "conn_1", email: "ada@example.com" }, {
    node: "acme_create_contact",
    http: (req) =>
      req.method === "POST"
        ? { status: 409, json: { code: "exists" } }
        : { status: 200, json: { items: [{ id: "c_9", email: req.query.email }] } },
  });
  assert.deepEqual(res.output, { id: "c_9", email: "ada@example.com", created: false });
  assert.equal(res.logs[0].message, "contact exists");
});

test("create contact: a bad email never reaches the API", async () => {
  const res = await runNode(library, { crm: "conn_1", email: "nope" }, { node: "acme_create_contact", http: () => assert.fail("no call") });
  assert.equal(res.error.kind, "validation");
  assert.deepEqual(res.error.details.problems, ['"nope" is not an email address']);
});

test("create contact: an API failure is a node error the engine can retry", async () => {
  const res = await runNode(library, { crm: "conn_1", email: "ada@example.com" }, {
    node: "acme_create_contact",
    http: () => ({ status: 503, json: { message: "maintenance" } }),
  });
  assert.equal(res.error.kind, "node");
  assert.equal(res.error.code, "http_503");
  assert.equal(res.error.retryable, true);
});

test("score lead", async () => {
  const res = await runNode(library, { employees: 500, budget: 60000, industry: "saas" }, { node: "acme_score_lead" });
  assert.deepEqual(res.output, { score: 85, grade: "A" });
  const bad = await runNode(library, { employees: "lots" }, { node: "acme_score_lead" });
  assert.equal(bad.error.kind, "validation");
});
