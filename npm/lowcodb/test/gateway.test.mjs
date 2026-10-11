import { test } from "node:test";
import assert from "node:assert/strict";
import { LowcodbClient, QuotaExceededError, isQuotaExceeded, LowcodbError } from "../dist/index.js";

const GATEWAY = "https://api.lowco.ai/gateway/h1";

/** A fetch that answers gateway discovery and records everything else. */
function fakeFetch({ respond, hashes } = {}) {
  const calls = [];
  const queue = hashes ? [...hashes] : null;
  const fetchFn = async (url, init) => {
    const u = new URL(url);
    calls.push({ method: init.method, url: u, headers: init.headers, body: init.body });
    if (u.pathname.includes("/bases/gateway-by-schema/")) {
      const h = queue ? queue.shift() : "h1";
      return new Response(
        JSON.stringify({ data: { gatewayId: "gw-1", hash: h, contextPath: `/gateway/${h}`, url: `https://api.lowco.ai/gateway/${h}`, internalUrl: `http://gateway-svc-gw-1.prod.svc:80/gateway/${h}` } }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    return respond ? respond(u, init) : json({ data: { id: "r1" } });
  };
  return { fetchFn, calls, data: () => calls.filter((c) => c.url.pathname.includes("/gateway/")) };
}
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

test("data calls go through the resolved gateway, resolved once", async () => {
  const f = fakeFetch({ respond: (u) => (u.pathname.endsWith("/leads") && u.search === "" ? json({ data: [] }) : json({ data: { id: "r1" } })) });
  const c = new LowcodbClient({ token: "lc_secret", orgId: "1", fetch: f.fetchFn });
  await c.createRecord("app_crm", "leads", { a: 1 });
  await c.listRecords("app_crm", "leads");
  await c.countViewRecords("app_crm", "hot leads", { pageNo: 2 });
  await c.invokeFunction("app_crm", "score-lead", { id: 1 });
  await c.executeTransaction("app_crm", [{ type: "create", table: "leads", record: {} }]);
  assert.deepEqual(
    f.data().map((x) => `${x.method} ${x.url.pathname}${x.url.search}`),
    ["POST /gateway/h1/v1/leads", "GET /gateway/h1/v1/leads", "GET /gateway/h1/v1/views/hot%20leads/count?pageNo=2", "POST /gateway/h1/v1/fn/score-lead", "POST /gateway/h1/v1/transactions"],
  );
  assert.equal(f.calls.filter((x) => x.url.pathname.includes("gateway-by-schema")).length, 1);
  assert.equal(f.calls[1].headers["X-Api-Key"], "lc_secret");
  assert.equal(f.calls[1].headers.Authorization, undefined);
});

test("pinned gateways skip discovery; a user token is a Bearer", async () => {
  const f = fakeFetch();
  const c = new LowcodbClient({ token: "user-token", fetch: f.fetchFn, gateways: { app_crm: "/gateway/pinned", other: "http://gw.internal:8080/gateway/x" } });
  await c.getRecord("app_crm", "leads", "r1");
  await c.getRecord("other", "leads", "r1");
  assert.deepEqual(f.calls.map((x) => x.url.toString()), ["https://api.lowco.ai/gateway/pinned/v1/leads/r1", "http://gw.internal:8080/gateway/x/v1/leads/r1"]);
  assert.equal(f.calls[0].headers.Authorization, "Bearer user-token");
});

test("internal origin uses the in-cluster url", async () => {
  const f = fakeFetch();
  const c = new LowcodbClient({ token: "lc_k", fetch: f.fetchFn, gatewayOrigin: "internal" });
  await c.getRecord("app_crm", "leads", "r1");
  assert.equal(f.data()[0].url.toString(), "http://gateway-svc-gw-1.prod.svc/gateway/h1/v1/leads/r1");
});

test("a stale gateway is re-resolved once", async () => {
  const f = fakeFetch({ hashes: ["old", "new"], respond: (u) => (u.pathname.includes("/gateway/old/") ? new Response("route not found", { status: 404 }) : json({ data: { id: "r1" } })) });
  const c = new LowcodbClient({ token: "lc_k", fetch: f.fetchFn });
  const row = await c.getRecord("app_crm", "leads", "r1");
  assert.deepEqual(row, { id: "r1" });
  assert.deepEqual(f.data().map((x) => x.url.pathname), ["/gateway/old/v1/leads/r1", "/gateway/new/v1/leads/r1"]);
});

test("402 QUOTA_EXCEEDED is typed", async () => {
  const body = { code: "QUOTA_EXCEEDED", message: "plan cap reached", meter: "app_crm_leads_create", consumed: 100, included: 100, hard_cap: 100, period_end: "2026-11-01T00:00:00Z", app_key: "crm", upgrade: { app_key: "crm", plans: ["pro"] } };
  const f = fakeFetch({ respond: () => json(body, 402) });
  const c = new LowcodbClient({ token: "lc_k", fetch: f.fetchFn });
  await assert.rejects(c.createRecord("app_crm", "leads", {}), (err) => {
    assert.ok(err instanceof QuotaExceededError && isQuotaExceeded(err) && err instanceof LowcodbError);
    assert.equal(err.statusCode, 402);
    assert.equal(err.meter, "app_crm_leads_create");
    assert.equal(err.hardCap, 100);
    assert.equal(err.upgrade.appKey, "crm");
    assert.deepEqual(err.upgrade.plans, ["pro"]);
    return true;
  });
});

test("GatewayClient addresses a gateway directly", async () => {
  const f = fakeFetch({ respond: () => json({ data: { results: [] } }) });
  const c = new LowcodbClient({ token: "lc_k", fetch: f.fetchFn });
  const g = c.gateway("/gateway/direct");
  assert.equal(g.url, "https://api.lowco.ai/gateway/direct");
  await g.executeTransaction([]);
  await g.invokeFunction("score-lead", {});
  assert.deepEqual(f.calls.map((x) => x.url.pathname), ["/gateway/direct/v1/transactions", "/gateway/direct/v1/fn/score-lead"]);
});
