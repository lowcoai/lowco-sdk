// Tests run against the built package (`npm run build` first; `npm test` does it
// via `pretest`). `fetch` is stubbed through the client's `fetch` option, so no
// request leaves the process.
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

import { DocsClient, DocsError, HEADER_ORG_ID, HttpClient } from "../dist/index.js";

const B = "my bucket";
const EB = "my%20bucket";
const P = "/v1/documents";

function json(payload, status = 200, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json", ...headers }
  });
}

function ok(data, status = 200, headers = {}) {
  return json({ status: 1, data }, status, headers);
}

function redirect(location, status = 307) {
  return new Response(null, { status, headers: { location } });
}

function bytes(data, headers = {}, status = 200) {
  return new Response(data, { status, headers });
}

/** A client whose fetch records each call and answers with `responder`. */
function setup(responder = () => ok({ id: "x" }), config = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url: new URL(url), rawUrl: url, init, headers: new Headers(init.headers) });
    return responder(url, init);
  };
  const client = new DocsClient({ token: "tok-123", orgId: "org-1", fetch, ...config });
  return { client, calls };
}

function queryOf(call) {
  return Object.fromEntries(call.url.searchParams);
}

const fileUpload = { data: new TextEncoder().encode("hello"), fileName: "hello.txt", contentType: "text/plain" };

// Every public method: [name, invoke, HTTP method, encoded path, query, JSON body, response, expected result].
const routes = [
  // client
  ["health", (c) => c.health(), "GET", "/health", {}, undefined, () => new Response("Working!"), "Working!"],
  ["search", (c) => c.search(B, "q3 report"), "GET", `${P}/${EB}/search`, { q: "q3 report" }],
  // buckets
  ["buckets.get", (c) => c.buckets.get(), "GET", P, {}],
  ["buckets.stats", (c) => c.buckets.stats(B), "GET", `${P}/${EB}/stats`, {}],
  // folders
  ["folders.list", (c) => c.folders.list(B, { prefix: "a/b", sizes: false }), "GET", `${P}/${EB}/objects`, { prefix: "a/b", sizes: "false" }],
  ["folders.listAt", (c) => c.folders.listAt(B, "a b/c", { sizes: true }), "GET", `${P}/${EB}/objects/a%20b/c`, { sizes: "true" }],
  ["folders.listPublic", (c) => c.folders.listPublic(B), "GET", `${P}/${EB}/public/objects`, {}],
  ["folders.listUser", (c) => c.folders.listUser(B, "u/1", { prefix: "notes" }), "GET", `${P}/${EB}/users/u%2F1/objects`, { prefix: "notes" }],
  ["folders.listApp", (c) => c.folders.listApp(B, "invoicing"), "GET", `${P}/${EB}/apps/invoicing/objects`, {}],
  ["folders.get", (c) => c.folders.get(B, "projects"), "GET", `${P}/${EB}/folder/projects`, {}],
  ["folders.create", (c) => c.folders.create(B, { folderName: "2026/q4", parentName: "projects" }), "POST", `${P}/${EB}/folder`, {}, { folderName: "2026/q4", parentName: "projects" }],
  ["folders.delete", (c) => c.folders.delete(B, "old"), "DELETE", `${P}/${EB}/folder/old`, {}],
  ["folders.deleteByPath", (c) => c.folders.deleteByPath(B, "a/b/"), "DELETE", `${P}/${EB}/folder`, { path: "a/b/" }],
  ["folders.upload", (c) => c.folders.upload(B, [fileUpload]), "POST", `${P}/${EB}/upload-folder`, {}, "multipart"],
  ["folders.downloadZip", (c) => c.folders.downloadZip(B, "reports/2026"), "GET", `${P}/${EB}/folder-zip/reports/2026`, {}, undefined,
    () => bytes(new Uint8Array([80, 75]), { "content-type": "application/zip", "content-disposition": 'attachment; filename="2026.zip"' }),
    { data: new Uint8Array([80, 75]), contentType: "application/zip", fileName: "2026.zip" }],
  ["folders.duplicate", (c) => c.folders.duplicate(B, { path: "plan.md", type: "file" }), "POST", `${P}/${EB}/duplicate`, {}, { path: "plan.md", type: "file" }],
  ["folders.rename", (c) => c.folders.rename(B, { parentName: "p", oldName: "a", newName: "b" }), "PUT", `${P}/${EB}/folder/rename`, {}, { parentName: "p", oldName: "a", newName: "b" }],
  // files
  ["files.get", (c) => c.files.get(B, ".users/u-1/notes/todo.md"), "GET", `${P}/${EB}/file/.users/u-1/notes/todo.md`, {}],
  ["files.read", (c) => c.files.read(B, "notes/todo.md", { meta: true }), "GET", `${P}/${EB}/file`, { path: "notes/todo.md", meta: "true" }],
  ["files.createBlank", (c) => c.files.createBlank(B, { fileName: "todo.md", parentName: "notes" }), "POST", `${P}/${EB}/file`, {}, { fileName: "todo.md", parentName: "notes" }],
  ["files.update", (c) => c.files.update(B, { fileName: "todo.md", content: "# Todo", ifMatch: "e1" }), "PUT", `${P}/${EB}/file`, {}, { fileName: "todo.md", content: "# Todo", ifMatch: "e1" }],
  ["files.updateAt", (c) => c.files.updateAt(B, "notes/todo.md", { fileName: "todo.md", content: "x" }), "PUT", `${P}/${EB}/file/notes/todo.md`, {}, { fileName: "todo.md", content: "x" }],
  ["files.rename", (c) => c.files.rename(B, { oldName: "a.md", newName: "b.md" }), "PUT", `${P}/${EB}/file/rename`, {}, { oldName: "a.md", newName: "b.md" }],
  ["files.delete", (c) => c.files.delete(B, "a/b.txt"), "DELETE", `${P}/${EB}/file/a/b.txt`, {}],
  ["files.deleteByPath", (c) => c.files.deleteByPath(B, "a/b.txt"), "DELETE", `${P}/${EB}/file`, { path: "a/b.txt" }],
  ["files.upload", (c) => c.files.upload(B, fileUpload), "POST", `${P}/${EB}/upload-file`, {}, "multipart"],
  ["files.downloadUrl", (c) => c.files.downloadUrl(B, "a/b.pdf"), "GET", `${P}/${EB}/download/a/b.pdf`, {}, undefined,
    () => redirect("https://cdn.example.com/b.pdf?sig=1"), "https://cdn.example.com/b.pdf?sig=1"],
  ["files.previewUrl", (c) => c.files.previewUrl(B, "a/b.docx"), "GET", `${P}/${EB}/preview/a/b.docx`, {}, undefined,
    () => redirect("https://cdn.example.com/b.pdf"), "https://cdn.example.com/b.pdf"],
  ["files.listArchive", (c) => c.files.listArchive(B, "exports/report.zip"), "GET", `${P}/${EB}/archive/exports/report.zip`, {}],
  // nodes
  ["nodes.get", (c) => c.nodes.get("n1"), "GET", `${P}/nodes/n1`, {}],
  ["nodes.resolve", (c) => c.nodes.resolve("n1", { download: true }), "GET", `${P}/d/n1`, { download: "1" }, undefined,
    () => redirect("https://cdn.example.com/q3.pdf"), { url: "https://cdn.example.com/q3.pdf" }],
  ["nodes.content", (c) => c.nodes.content("n1"), "GET", `${P}/d/n1/content`, {}, undefined,
    () => bytes("abc", { "content-type": "text/plain", "x-file-name": "q3.txt" }),
    { content: { data: new TextEncoder().encode("abc"), contentType: "text/plain", fileName: "q3.txt" } }],
  // library
  ["library.star", (c) => c.library.star(B, "n1"), "POST", `${P}/${EB}/nodes/n1/star`, {}],
  ["library.unstar", (c) => c.library.unstar(B, "n1"), "DELETE", `${P}/${EB}/nodes/n1/star`, {}],
  ["library.starPath", (c) => c.library.starPath(B, "plan.md", { type: "file" }), "POST", `${P}/${EB}/star`, {}, { path: "plan.md", type: "file" }],
  ["library.unstarPath", (c) => c.library.unstarPath(B, "a/plan.md"), "DELETE", `${P}/${EB}/star`, { path: "a/plan.md" }],
  ["library.starred", (c) => c.library.starred(B), "GET", `${P}/${EB}/starred`, {}],
  ["library.recent", (c) => c.library.recent(B, { limit: 10 }), "GET", `${P}/${EB}/recent`, { limit: "10" }],
  ["library.trash", (c) => c.library.trash(B), "GET", `${P}/${EB}/trash`, {}],
  ["library.restore", (c) => c.library.restore(B, "n1"), "POST", `${P}/${EB}/trash/n1/restore`, {}],
  ["library.purge", (c) => c.library.purge(B, "n1"), "DELETE", `${P}/${EB}/trash/n1`, {}],
  // sharing
  ["sharing.create", (c) => c.sharing.create(B, { path: "r.pdf", subjectType: "user", subjectId: "u-2", role: "viewer" }), "POST", `${P}/${EB}/shares`, {}, { path: "r.pdf", subjectType: "user", subjectId: "u-2", role: "viewer" }],
  ["sharing.list", (c) => c.sharing.list(B, { path: "r", type: "folder" }), "GET", `${P}/${EB}/shares`, { path: "r", type: "folder" }],
  ["sharing.delete", (c) => c.sharing.delete(B, "s1"), "DELETE", `${P}/${EB}/shares/s1`, {}],
  ["sharing.sharedWithMe", (c) => c.sharing.sharedWithMe(B, { appKey: "notes" }), "GET", `${P}/${EB}/shared-with-me`, { appKey: "notes" }],
  ["sharing.createLink", (c) => c.sharing.createLink(B, { path: "r.pdf", type: "file" }), "POST", `${P}/${EB}/share-links`, {}, { path: "r.pdf", type: "file" }],
  ["sharing.listLinks", (c) => c.sharing.listLinks(B, { path: "r.pdf" }), "GET", `${P}/${EB}/share-links`, { path: "r.pdf" }],
  ["sharing.deleteLink", (c) => c.sharing.deleteLink(B, "l1"), "DELETE", `${P}/${EB}/share-links/l1`, {}],
  ["sharing.resolveLink", (c) => c.sharing.resolveLink("tok/en"), "GET", `${P}/link/tok%2Fen`, {}, undefined,
    () => redirect("https://cdn.example.com/r.pdf"), "https://cdn.example.com/r.pdf"],
  // automation
  ["automation.list", (c) => c.automation.list(B, { prefix: "invoices/" }), "GET", `${P}/${EB}/folder-configs`, { prefix: "invoices/" }],
  ["automation.create", (c) => c.automation.create(B, { prefix: "invoices/", pipelineType: "extract_text" }), "POST", `${P}/${EB}/folder-configs`, {}, { prefix: "invoices/", pipelineType: "extract_text" }],
  ["automation.get", (c) => c.automation.get(B, "c1"), "GET", `${P}/${EB}/folder-configs/c1`, {}],
  ["automation.update", (c) => c.automation.update(B, "c1", { prefix: "inv/", pipelineType: "thumbnail", active: false }), "PUT", `${P}/${EB}/folder-configs/c1`, {}, { prefix: "inv/", pipelineType: "thumbnail", active: false }],
  ["automation.delete", (c) => c.automation.delete(B, "c1"), "DELETE", `${P}/${EB}/folder-configs/c1`, {}],
  ["automation.jobs", (c) => c.automation.jobs(B, { configId: "c1", limit: 5 }), "GET", `${P}/${EB}/processing-jobs`, { configId: "c1", limit: "5" }],
  // appFiles
  ["appFiles.upload", (c) => c.appFiles.upload("invoicing", fileUpload), "POST", `${P}/app-files/invoicing`, {}, "multipart"],
  ["appFiles.list", (c) => c.appFiles.list("invoicing", { prefix: "2026" }), "GET", `${P}/app-files/invoicing/objects`, { prefix: "2026" }],
  ["appFiles.delete", (c) => c.appFiles.delete("invoicing", "2026/INV 1.pdf"), "DELETE", `${P}/app-files/invoicing/2026/INV%201.pdf`, {}],
  ["appFiles.sweep", (c) => c.appFiles.sweep("invoicing", { olderThanDays: 30 }), "POST", `${P}/app-files/invoicing/sweep`, {}, { olderThanDays: 30 }],
  // triggers
  ["triggers.list", (c) => c.triggers.list(), "GET", `${P}/triggers`, {}],
  ["triggers.create", (c) => c.triggers.create({ prefix: "inv/", workflowId: "w1", eventType: "create", active: true }), "POST", `${P}/triggers`, {}, { prefix: "inv/", workflowId: "w1", eventType: "create", active: true }],
  ["triggers.get", (c) => c.triggers.get("t1"), "GET", `${P}/triggers/t1`, {}],
  ["triggers.update", (c) => c.triggers.update("t1", { prefix: "inv/", workflowId: "w2" }), "PUT", `${P}/triggers/t1`, {}, { prefix: "inv/", workflowId: "w2" }],
  ["triggers.delete", (c) => c.triggers.delete("t1"), "DELETE", `${P}/triggers/t1`, {}, undefined, () => ok(null), undefined],
  // webhooks
  ["webhooks.list", (c) => c.webhooks.list({ page: 2, limit: 10 }), "GET", `${P}/webhooks`, { page: "2", limit: "10" }],
  ["webhooks.create", (c) => c.webhooks.create({ url: "https://h.example.com", method: "POST", prefix: "up/", eventTypes: ["create"] }), "POST", `${P}/webhooks`, {}, { url: "https://h.example.com", method: "POST", prefix: "up/", eventTypes: ["create"] }],
  ["webhooks.get", (c) => c.webhooks.get("h1"), "GET", `${P}/webhooks/h1`, {}],
  ["webhooks.update", (c) => c.webhooks.update("h1", { url: "https://h.example.com", method: "PUT", prefix: "up/", eventTypes: ["update"], active: true }), "PUT", `${P}/webhooks/h1`, {}, { url: "https://h.example.com", method: "PUT", prefix: "up/", eventTypes: ["update"], active: true }],
  ["webhooks.delete", (c) => c.webhooks.delete("h1"), "DELETE", `${P}/webhooks/h1`, {}, undefined, () => new Response(null, { status: 204 }), undefined]
];

describe("route table", () => {
  test("covers all 69 operations and every public method", () => {
    assert.equal(routes.length, 69);
    const names = new Set(routes.map((r) => r[0]));
    assert.equal(names.size, 69, "duplicate route names");
    const { client } = setup();
    const resources = ["buckets", "folders", "files", "nodes", "library", "sharing", "automation", "appFiles", "triggers", "webhooks"];
    for (const resource of resources) {
      const proto = Object.getPrototypeOf(client[resource]);
      for (const method of Object.getOwnPropertyNames(proto)) {
        if (method === "constructor") continue;
        assert.ok(names.has(`${resource}.${method}`), `${resource}.${method} has no route test`);
      }
    }
    assert.ok(names.has("health") && names.has("search"));
  });

  for (const [name, invoke, method, path, query, body, respond, expected] of routes) {
    test(`${name} -> ${method} ${path}`, async () => {
      const { client, calls } = setup(respond ?? (() => ok({ id: "x" })));
      const result = await invoke(client);
      assert.equal(calls.length, 1);
      const [call] = calls;
      assert.equal(call.init.method, method);
      assert.equal(call.url.origin, "https://api.lowco.ai");
      assert.equal(call.url.pathname, path);
      assert.deepEqual(queryOf(call), query);
      assert.equal(call.headers.get("authorization"), "Bearer tok-123");
      assert.equal(call.headers.get(HEADER_ORG_ID), "org-1");
      if (body === "multipart") {
        assert.ok(call.init.body instanceof FormData);
      } else if (body === undefined) {
        assert.equal(call.init.body, undefined);
      } else {
        assert.deepEqual(JSON.parse(call.init.body), body);
      }
      if (respond === undefined) {
        assert.deepEqual(result, { id: "x" });
      } else {
        assert.deepEqual(result, expected);
      }
    });
  }
});

describe("config validation", () => {
  const fetch = async () => ok(null);

  test("missing token throws", () => {
    assert.throws(() => new DocsClient({ orgId: "org-1", fetch }), /token/);
    assert.throws(() => new DocsClient({ token: "", orgId: "org-1", fetch }), /token/);
    assert.throws(() => new DocsClient({ token: "  ", orgId: "org-1", fetch }), /token/);
  });

  test("missing or blank orgId throws", () => {
    assert.throws(() => new DocsClient({ token: "t", fetch }), /orgId/);
    assert.throws(() => new DocsClient({ token: "t", orgId: "", fetch }), /orgId/);
    assert.throws(() => new DocsClient({ token: "t", orgId: "   ", fetch }), /orgId/);
  });

  test("missing config throws", () => {
    assert.throws(() => new DocsClient(undefined), /token/);
  });

  test("valid config constructs every resource", () => {
    const client = new DocsClient({ token: "t", orgId: "o", fetch });
    for (const resource of ["buckets", "folders", "files", "nodes", "library", "sharing", "automation", "appFiles", "triggers", "webhooks"]) {
      assert.equal(typeof client[resource], "object", resource);
    }
    assert.equal(typeof client.health, "function");
    assert.equal(typeof client.search, "function");
  });
});

describe("headers", () => {
  test("Authorization, X-Org-Id, Accept and JSON Content-Type", async () => {
    const { client, calls } = setup();
    await client.folders.create(B, { folderName: "x" });
    const { headers } = calls[0];
    assert.equal(HEADER_ORG_ID, "X-Org-Id");
    assert.equal(headers.get("authorization"), "Bearer tok-123");
    assert.equal(headers.get("x-org-id"), "org-1");
    assert.equal(headers.get("accept"), "application/json");
    assert.equal(headers.get("content-type"), "application/json");
  });

  test("no Content-Type on bodyless requests", async () => {
    const { client, calls } = setup();
    await client.buckets.get();
    assert.equal(calls[0].headers.get("content-type"), null);
  });

  test("extra headers are sent; explicit Authorization and X-Org-Id win", async () => {
    const { client, calls } = setup(undefined, {
      headers: { "X-Trace": "abc", authorization: "Bearer other", "x-org-id": "org-9" }
    });
    await client.buckets.get();
    const sent = calls[0].init.headers;
    assert.equal(calls[0].headers.get("x-trace"), "abc");
    assert.equal(calls[0].headers.get("authorization"), "Bearer other");
    assert.equal(calls[0].headers.get("x-org-id"), "org-9");
    // No duplicate differently-cased copies.
    assert.equal(Object.keys(sent).filter((k) => k.toLowerCase() === "authorization").length, 1);
    assert.equal(Object.keys(sent).filter((k) => k.toLowerCase() === "x-org-id").length, 1);
  });

  test("multipart uploads leave Content-Type to fetch (boundary)", async () => {
    const { client, calls } = setup();
    await client.files.upload(B, fileUpload);
    assert.equal(calls[0].headers.get("content-type"), null);
    assert.equal(calls[0].headers.get("authorization"), "Bearer tok-123");
    assert.equal(calls[0].headers.get("x-org-id"), "org-1");
  });
});

describe("envelope unwrapping", () => {
  test("returns the data of {status: 1, data}", async () => {
    const doc = { id: "b1", name: "org-bucket", type: "folder", metadata: { privateNotes: "false" } };
    const { client } = setup(() => ok(doc));
    assert.deepEqual(await client.buckets.get(), doc);
  });

  test("returns arrays and message strings", async () => {
    const { client } = setup(() => ok([{ id: "1" }, { id: "2" }]));
    assert.deepEqual(await client.library.starred(B), [{ id: "1" }, { id: "2" }]);
    const second = setup(() => ok("file deleted"));
    assert.equal(await second.client.files.delete(B, "a.txt"), "file deleted");
  });

  test("empty body resolves to undefined", async () => {
    const { client } = setup(() => new Response(null, { status: 204 }));
    assert.equal(await client.webhooks.delete("h1"), undefined);
  });

  test("a status-0 envelope is an error even on a 2xx", async () => {
    const { client } = setup(() => json({ status: 0, error: { message: "boom", code: 500 } }, 200));
    await assert.rejects(client.buckets.get(), (err) => err instanceof DocsError && err.message === "boom" && err.status === 200);
  });

  test("invalid JSON on a 2xx is a DocsError", async () => {
    const { client } = setup(() => new Response("<html>", { status: 200 }));
    await assert.rejects(client.buckets.get(), (err) => err instanceof DocsError && err.status === 200 && err.payload === "<html>");
  });
});

describe("errors", () => {
  test('{"status":0,"error":{...}} with a platform code uses details', async () => {
    const payload = { status: 0, error: { message: "AAS-00106", code: 400, details: "bucket name is required" } };
    const { client } = setup(() => json(payload, 400));
    await assert.rejects(client.buckets.stats(B), (err) => {
      assert.ok(err instanceof DocsError);
      assert.ok(err instanceof Error);
      assert.equal(err.name, "DocsError");
      assert.equal(err.status, 400);
      assert.equal(err.message, "bucket name is required");
      assert.equal(err.code, "AAS-00106");
      assert.deepEqual(err.payload, payload);
      return true;
    });
  });

  test('{"status":0,"error":{...}} with a readable message', async () => {
    const payload = { status: 0, error: { message: "the file was changed by someone else", code: 412 }, data: { currentEtag: "e2" } };
    const { client } = setup(() => json(payload, 412));
    await assert.rejects(client.files.update(B, { fileName: "a.md", content: "x", ifMatch: "e1" }), (err) => {
      assert.equal(err.status, 412);
      assert.equal(err.message, "the file was changed by someone else");
      assert.equal(err.code, undefined);
      assert.equal(err.payload.data.currentEtag, "e2");
      return true;
    });
  });

  test('{"message": "..."}', async () => {
    const { client } = setup(() => json({ message: "you don't have access to this item" }, 403));
    await assert.rejects(client.files.get(B, "a.md"), (err) => {
      assert.ok(err instanceof DocsError);
      assert.equal(err.status, 403);
      assert.equal(err.message, "you don't have access to this item");
      assert.deepEqual(err.payload, { message: "you don't have access to this item" });
      return true;
    });
  });

  test("non-JSON and empty error bodies", async () => {
    const text = setup(() => new Response("Bad Gateway", { status: 502 }));
    await assert.rejects(text.client.triggers.list(), (err) => err.status === 502 && err.message === "Bad Gateway" && err.payload === "Bad Gateway");
    const empty = setup(() => new Response(null, { status: 500 }));
    await assert.rejects(empty.client.triggers.list(), (err) => err.status === 500 && err.message === "Request failed with status 500" && err.payload === null);
  });

  test("errors on binary, redirect and node methods are DocsErrors", async () => {
    const { client } = setup(() => json({ message: "document not found" }, 404));
    for (const call of [
      () => client.folders.downloadZip(B, "x"),
      () => client.files.downloadUrl(B, "x"),
      () => client.nodes.resolve("n1"),
      () => client.nodes.content("n1"),
      () => client.health()
    ]) {
      await assert.rejects(call(), (err) => err instanceof DocsError && err.status === 404 && err.message === "document not found");
    }
  });

  test("network failures become DocsError with status 0", async () => {
    const { client } = setup(() => {
      throw new TypeError("fetch failed");
    });
    await assert.rejects(client.buckets.get(), (err) => {
      assert.ok(err instanceof DocsError);
      assert.equal(err.status, 0);
      assert.equal(err.message, "fetch failed");
      assert.ok(err.cause instanceof TypeError);
      return true;
    });
  });

  test("timeouts become DocsError with status 0", async () => {
    const fetch = (url, init) =>
      new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(new Error("aborted"))));
    const client = new DocsClient({ token: "t", orgId: "o", fetch, timeoutMs: 20 });
    await assert.rejects(client.buckets.get(), (err) => err instanceof DocsError && err.status === 0 && /timed out after 20ms/.test(err.message));
  });
});

describe("path encoding", () => {
  test("single-segment params are fully percent-encoded", async () => {
    const { client, calls } = setup();
    await client.folders.get("b/1", "a/b c#?%");
    assert.equal(calls[0].url.pathname, `${P}/b%2F1/folder/a%2Fb%20c%23%3F%25`);
    await client.nodes.get("n 1/2");
    assert.equal(calls[1].url.pathname, `${P}/nodes/n%201%2F2`);
    await client.sharing.delete(B, "id?x");
    assert.equal(calls[2].url.pathname, `${P}/${EB}/shares/id%3Fx`);
    await client.folders.listUser(B, "u 1");
    assert.equal(calls[3].url.pathname, `${P}/${EB}/users/u%201/objects`);
    await client.appFiles.list("my app");
    assert.equal(calls[4].url.pathname, `${P}/app-files/my%20app/objects`);
  });

  test("wildcard params keep / and encode each segment", async () => {
    const { client, calls } = setup();
    await client.files.get(B, "a b/c.txt");
    assert.equal(calls[0].url.pathname, `${P}/${EB}/file/a%20b/c.txt`);
    await client.files.get(B, "/.users/u-1/r&d/#1?.md");
    assert.equal(calls[1].url.pathname, `${P}/${EB}/file/.users/u-1/r%26d/%231%3F.md`);
    assert.equal(calls[1].url.search, "");
    await client.appFiles.delete("invoicing", "2026/ü.pdf");
    assert.equal(calls[2].url.pathname, `${P}/app-files/invoicing/2026/%C3%BC.pdf`);
  });

  test("leading slashes are stripped from wildcard params", async () => {
    const { client, calls } = setup();
    await client.folders.listAt(B, "//reports/2026");
    assert.equal(calls[0].url.pathname, `${P}/${EB}/objects/reports/2026`);
  });

  test("dot segments are rejected without a request", async () => {
    const { client, calls } = setup();
    await assert.rejects(client.files.get(B, "a/../../triggers"), (err) => err instanceof DocsError && err.status === 0);
    await assert.rejects(client.nodes.get(".."), (err) => err instanceof DocsError && err.status === 0);
    await assert.rejects(client.folders.get(B, "."), (err) => err instanceof DocsError);
    assert.equal(calls.length, 0);
  });

  test("query values are encoded, not the path", async () => {
    const { client, calls } = setup();
    await client.files.read(B, ".users/u-1/a b&c.md");
    assert.equal(calls[0].url.pathname, `${P}/${EB}/file`);
    assert.equal(calls[0].url.searchParams.get("path"), ".users/u-1/a b&c.md");
  });
});

describe("query omission", () => {
  test("undefined and null options are not sent", async () => {
    const { client, calls } = setup(() => ok([]));
    await client.folders.list(B);
    await client.folders.list(B, {});
    await client.folders.list(B, { prefix: undefined, sizes: null });
    await client.library.recent(B);
    await client.automation.jobs(B, { configId: undefined });
    await client.webhooks.list();
    await client.sharing.sharedWithMe(B);
    await client.sharing.list(B, { path: "a" });
    for (const call of calls.slice(0, 7)) {
      assert.equal(call.url.search, "", call.rawUrl);
    }
    assert.deepEqual(queryOf(calls[7]), { path: "a" });
  });

  test("false booleans are sent, except download (any value forces a download)", async () => {
    const { client, calls } = setup((url) =>
      url.includes("/d/") ? redirect("https://cdn.example.com/f") : ok([])
    );
    await client.folders.list(B, { sizes: false });
    await client.files.read(B, "a.md", { meta: false });
    await client.nodes.resolve("n1", { download: false });
    await client.nodes.resolve("n1");
    assert.deepEqual(queryOf(calls[0]), { sizes: "false" });
    assert.deepEqual(queryOf(calls[1]), { path: "a.md", meta: "false" });
    assert.equal(calls[2].url.search, "");
    assert.equal(calls[3].url.search, "");
  });
});

describe("multipart uploads", () => {
  test("files.upload uses file, ParentID and onConflict", async () => {
    const { client, calls } = setup(() => ok({ id: "f1", name: "hello.txt" }));
    const doc = await client.files.upload(B, fileUpload, { parentId: "projects/2026", onConflict: "rename" });
    assert.deepEqual(doc, { id: "f1", name: "hello.txt" });
    const form = calls[0].init.body;
    assert.deepEqual([...form.keys()], ["file", "ParentID", "onConflict"]);
    const part = form.get("file");
    assert.equal(part.name, "hello.txt");
    assert.equal(part.type, "text/plain");
    assert.equal(await part.text(), "hello");
    assert.equal(form.get("ParentID"), "projects/2026");
    assert.equal(form.get("parentID"), null);
    assert.equal(form.get("onConflict"), "rename");
  });

  test("files.upload omits unset optional fields", async () => {
    const { client, calls } = setup();
    await client.files.upload(B, fileUpload);
    assert.deepEqual([...calls[0].init.body.keys()], ["file"]);
  });

  test("folders.upload repeats files and relativePaths in order, with parentID and prefix", async () => {
    const { client, calls } = setup(() => ok({ folder: { name: "photos" }, files: [] }));
    const files = [
      { data: new Uint8Array([1, 2, 3]), fileName: "a.jpg", contentType: "image/jpeg" },
      { data: new Uint8Array([4]).buffer, fileName: "b.png" },
      { data: "# notes", fileName: "c.md", contentType: "text/markdown" }
    ];
    const result = await client.folders.upload(B, files, {
      relativePaths: ["photos/a.jpg", "photos/2026/b.png", "c.md"],
      parentId: "uploads",
      prefix: "ignored/"
    });
    assert.deepEqual(result, { folder: { name: "photos" }, files: [] });
    const form = calls[0].init.body;
    const parts = form.getAll("files");
    assert.deepEqual(parts.map((p) => p.name), ["a.jpg", "b.png", "c.md"]);
    assert.deepEqual(parts.map((p) => p.type), ["image/jpeg", "application/octet-stream", "text/markdown"]);
    assert.deepEqual([...new Uint8Array(await parts[0].arrayBuffer())], [1, 2, 3]);
    assert.deepEqual(form.getAll("relativePaths"), ["photos/a.jpg", "photos/2026/b.png", "c.md"]);
    assert.equal(form.get("parentID"), "uploads");
    assert.equal(form.get("ParentID"), null);
    assert.equal(form.get("prefix"), "ignored/");
  });

  test("folders.upload rejects mismatched relativePaths without a request", async () => {
    const { client, calls } = setup();
    await assert.rejects(
      client.folders.upload(B, [fileUpload, fileUpload], { relativePaths: ["a.txt"] }),
      (err) => err instanceof DocsError && err.status === 0 && /relativePaths/.test(err.message)
    );
    assert.equal(calls.length, 0);
  });

  test("appFiles.upload uses file, path and onConflict", async () => {
    const uploaded = { appKey: "invoicing", nodeId: "n1", permalink: "/v1/documents/d/n1" };
    const { client, calls } = setup(() => ok(uploaded));
    const result = await client.appFiles.upload("invoicing", fileUpload, { path: "2026/invoices", onConflict: "replace" });
    assert.deepEqual(result, uploaded);
    const form = calls[0].init.body;
    assert.deepEqual([...form.keys()], ["file", "path", "onConflict"]);
    assert.equal(form.get("file").name, "hello.txt");
    assert.equal(form.get("path"), "2026/invoices");
    assert.equal(form.get("onConflict"), "replace");
  });

  test("accepts Blob, File and Blob-with-name inputs", async () => {
    const { client, calls } = setup();
    await client.files.upload(B, new Blob(["raw"], { type: "text/plain" }));
    assert.equal(calls[0].init.body.get("file").name, "blob");
    await client.files.upload(B, { data: new Blob(["raw"]), fileName: "named.txt", contentType: "text/csv" });
    const named = calls[1].init.body.get("file");
    assert.equal(named.name, "named.txt");
    assert.equal(named.type, "text/csv");
    assert.equal(await named.text(), "raw");
    if (typeof globalThis.File === "function") {
      await client.files.upload(B, new File(["f"], "real.pdf", { type: "application/pdf" }));
      const part = calls[2].init.body.get("file");
      assert.equal(part.name, "real.pdf");
      assert.equal(part.type, "application/pdf");
    }
  });
});

describe("redirect URL methods", () => {
  test("do not follow redirects and return Location untouched", async () => {
    const signed = "https://cdn.example.com/org/a%20b.pdf?X-Amz-Signature=abc%2F%3D&x=1";
    const { client, calls } = setup(() => redirect(signed));
    assert.equal(await client.files.downloadUrl(B, "a b.pdf"), signed);
    assert.equal(calls[0].init.redirect, "manual");
  });

  test("relative Location is resolved against the API host", async () => {
    const { client } = setup(() => redirect("/v1/documents/d/n1"));
    assert.equal(await client.sharing.resolveLink("t1"), "https://api.lowco.ai/v1/documents/d/n1");
  });

  test("opaque redirects (browser fetch) raise a clear DocsError", async () => {
    const opaque = { type: "opaqueredirect", status: 0, ok: false, headers: new Headers(), text: async () => "" };
    const { client } = setup(() => opaque);
    await assert.rejects(client.files.previewUrl(B, "a.docx"), (err) => {
      assert.ok(err instanceof DocsError);
      assert.equal(err.status, 0);
      assert.match(err.message, /server runtime/);
      return true;
    });
    await assert.rejects(client.nodes.resolve("n1"), /server runtime/);
  });

  test("missing Location or a non-redirect success is a DocsError", async () => {
    const noLocation = setup(() => new Response(null, { status: 307 }));
    await assert.rejects(noLocation.client.files.downloadUrl(B, "a"), (err) => err instanceof DocsError && err.status === 307);
    const notRedirect = setup(() => ok({ id: "x" }));
    await assert.rejects(notRedirect.client.files.downloadUrl(B, "a"), (err) => err instanceof DocsError && err.status === 200 && /Expected a redirect/.test(err.message));
  });
});

describe("binary downloads", () => {
  test("nodes.content reads X-File-Name", async () => {
    const data = new Uint8Array([0, 1, 2, 255]);
    const { client, calls } = setup(() =>
      bytes(data, { "content-type": "application/pdf", "x-file-name": "q3 report.pdf", "content-disposition": 'inline; filename="other.pdf"' })
    );
    const result = await client.nodes.content("n1");
    assert.deepEqual(Object.keys(result), ["content"]);
    assert.ok(result.content.data instanceof Uint8Array);
    assert.deepEqual([...result.content.data], [0, 1, 2, 255]);
    assert.equal(result.content.contentType, "application/pdf");
    assert.equal(result.content.fileName, "q3 report.pdf");
    assert.equal(calls[0].headers.get("accept"), "*/*");
  });

  test("UTF-8 X-File-Name sent as raw bytes is decoded", async () => {
    const latin1 = String.fromCharCode(...new TextEncoder().encode("résumé.pdf"));
    const fakeResponse = {
      ok: true,
      status: 200,
      type: "basic",
      headers: new Headers({ "content-type": "application/pdf", "x-file-name": latin1 }),
      arrayBuffer: async () => new ArrayBuffer(0)
    };
    const { client } = setup(() => fakeResponse);
    const result = await client.nodes.content("n1");
    assert.equal(result.content.fileName, "résumé.pdf");
  });

  test("Content-Disposition fallbacks: quoted, escaped, RFC 5987 and absent", async () => {
    const cases = [
      ['attachment; filename="My \\"Q3\\".zip"', 'My "Q3".zip'],
      ["attachment; filename*=UTF-8''r%C3%A9sum%C3%A9.zip; filename=\"resume.zip\"", "résumé.zip"],
      ["attachment; filename=plain.zip", "plain.zip"],
      [null, undefined]
    ];
    for (const [disposition, expected] of cases) {
      const headers = { "content-type": "application/zip" };
      if (disposition) headers["content-disposition"] = disposition;
      const { client } = setup(() => bytes(new Uint8Array([1]), headers));
      const result = await client.folders.downloadZip(B, "x");
      assert.equal(result.fileName, expected, String(disposition));
      if (expected === undefined) assert.ok(!("fileName" in result));
    }
  });

  test("missing Content-Type defaults to application/octet-stream", async () => {
    const fakeResponse = {
      ok: true,
      status: 200,
      type: "basic",
      headers: new Headers(),
      arrayBuffer: async () => new Uint8Array([7]).buffer
    };
    const { client } = setup(() => fakeResponse);
    const result = await client.folders.downloadZip(B, "x");
    assert.equal(result.contentType, "application/octet-stream");
    assert.deepEqual([...result.data], [7]);
  });
});

describe("node file results", () => {
  const restoring = {
    status: "restoring",
    nodeId: "n1",
    name: "q3.pdf",
    retryAfterSeconds: 300,
    message: "this file was moved to cold storage; a restore has been requested, try again in a few minutes"
  };

  test("202 on content returns restoring with Retry-After", async () => {
    const { client } = setup(() => ok(restoring, 202, { "retry-after": "120" }));
    const result = await client.nodes.content("n1");
    assert.deepEqual(result, { restoring, retryAfter: 120 });
  });

  test("202 on resolve returns restoring; retryAfter falls back to the body", async () => {
    const { client, calls } = setup(() => ok(restoring, 202));
    const result = await client.nodes.resolve("n1");
    assert.deepEqual(result, { restoring, retryAfter: 300 });
    assert.equal(calls[0].init.redirect, "manual");
  });

  test("resolve 307 returns the URL only", async () => {
    const { client } = setup(() => redirect("https://cdn.example.com/q3.pdf?sig=x"));
    assert.deepEqual(await client.nodes.resolve("n1"), { url: "https://cdn.example.com/q3.pdf?sig=x" });
  });

  test("resolve 200 (restored from cold storage) returns content", async () => {
    const { client } = setup(() => bytes(new Uint8Array([9, 9]), { "content-type": "application/pdf" }));
    const result = await client.nodes.resolve("n1");
    assert.deepEqual(Object.keys(result), ["content"]);
    assert.deepEqual([...result.content.data], [9, 9]);
    assert.equal(result.content.contentType, "application/pdf");
  });

  test("410 is an error, not a result", async () => {
    const { client } = setup(() => json({ message: "this file was archived and the archive tier is not available" }, 410));
    await assert.rejects(client.nodes.content("n1"), (err) => err instanceof DocsError && err.status === 410);
  });
});

describe("health and search", () => {
  test("health hits /health outside the prefix and returns text", async () => {
    const { client, calls } = setup(() => new Response("Working!", { headers: { "content-type": "text/plain" } }));
    assert.equal(await client.health(), "Working!");
    assert.equal(calls[0].rawUrl, "https://api.lowco.ai/health");
  });

  test("search sends q", async () => {
    const hits = [{ id: "1", name: "q3.pdf", metadata: { matchedBy: "content" } }];
    const { client, calls } = setup(() => ok(hits));
    assert.deepEqual(await client.search(B, "revenue & costs"), hits);
    assert.equal(calls[0].url.searchParams.get("q"), "revenue & costs");
  });
});

describe("package", () => {
  test("ESM exports", () => {
    assert.equal(typeof DocsClient, "function");
    assert.equal(typeof DocsError, "function");
    assert.equal(typeof HttpClient, "function");
    assert.equal(HEADER_ORG_ID, "X-Org-Id");
  });

  test("CommonJS build exports the same API", () => {
    const require = createRequire(import.meta.url);
    const cjs = require("../dist/index.cjs");
    assert.equal(typeof cjs.DocsClient, "function");
    assert.equal(typeof cjs.DocsError, "function");
    assert.equal(cjs.HEADER_ORG_ID, "X-Org-Id");
    const client = new cjs.DocsClient({ token: "t", orgId: "o", fetch: async () => ok(null) });
    assert.equal(typeof client.files.upload, "function");
  });
});
