import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

// A minimal browser: the SDK is a singleton built on import, so the globals
// exist before it loads.
class MemoryStorage {
  constructor() { this.m = new Map(); }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null; }
  setItem(k, v) { this.m.set(k, String(v)); }
  removeItem(k) { this.m.delete(k); }
  clear() { this.m.clear(); }
}
const storage = new MemoryStorage();
const page = { href: "https://shop.test/landing", search: "", pathname: "/landing" };
const doc = { cookie: "", referrer: "", title: "Shop" };
const win = {
  localStorage: storage,
  location: page,
  navigator: { userAgent: "Mozilla/5.0 (test)" },
  addEventListener() {},
};
globalThis.window = win;
globalThis.document = doc;
globalThis.localStorage = storage;
globalThis.history = { pushState() {}, replaceState() {} };

const sent = [];
globalThis.fetch = async (url, init) => {
  sent.push({ url: String(url), body: JSON.parse(init.body) });
  return new Response("{}", { status: 200 });
};
console.log = () => {};

const { default: analytics } = await import("../dist/index.js");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const visit = (url, referrer = "") => {
  const u = new URL(url);
  page.href = u.href;
  page.search = u.search;
  page.pathname = u.pathname;
  doc.referrer = referrer;
};
const last = () => sent[sent.length - 1].body;

beforeEach(() => {
  sent.length = 0;
  storage.clear();
  doc.cookie = "";
  delete win.fbq;
  delete win.gtag;
  visit("https://shop.test/landing");
  analytics.init({ apiKey: "lc_test", orgId: "1" });
  analytics.reset();
});

test("every event carries a UUID event_id, also as the event id", () => {
  const id = analytics.track("signup_completed", { plan: "pro" });
  const body = last();
  assert.match(id, UUID);
  assert.equal(body.event_data.event_id, id);
  assert.equal(body.id, id);
  assert.equal(body.event_data.plan, "pro");
  assert.notEqual(analytics.track("x"), id);
});

test("an event_id passed by the caller is kept", () => {
  assert.equal(analytics.track("purchase", { event_id: "order-42" }), "order-42");
  assert.equal(last().event_data.event_id, "order-42");
});

test("click ids, cookies, referrer and url ride on every event", () => {
  doc.cookie = "_fbp=fb.1.1700.42; _ga=GA1.1.555.666";
  visit("https://shop.test/landing?utm_source=facebook&fbclid=F1&gclid=G1", "https://l.facebook.com/");
  analytics.track("lead_submitted");
  const d = last().event_data;
  assert.equal(d.gclid, "G1");
  assert.equal(d.fbclid, "F1");
  assert.equal(d.click_id, "G1");
  assert.equal(d.click_id_kind, "gclid");
  assert.equal(d.fbp, "fb.1.1700.42");
  assert.match(d.fbc, /^fb\.1\.\d{13}\.F1$/);
  assert.equal(d.ga_client_id, "555.666");
  assert.equal(d.referrer, "https://l.facebook.com/");
  assert.equal(d.url, "https://shop.test/landing?utm_source=facebook&fbclid=F1&gclid=G1");
  assert.equal(d.utm_source, "facebook");
});

test("click ids persist for the session, first value kept, derived fbc stable", () => {
  visit("https://shop.test/?fbclid=F1&li_fat_id=L1");
  analytics.track("a");
  const fbc = last().event_data.fbc;
  visit("https://shop.test/next?fbclid=F2");
  analytics.track("b");
  const d = last().event_data;
  assert.equal(d.fbclid, "F1");
  assert.equal(d.li_fat_id, "L1");
  assert.equal(d.fbc, fbc);
  assert.equal(d.url, "https://shop.test/next?fbclid=F2");
});

test("Meta's _fbc cookie wins over the derived fbc", () => {
  doc.cookie = "_fbc=fb.1.99.cookie";
  visit("https://shop.test/?fbclid=F1");
  analytics.track("a");
  assert.equal(last().event_data.fbc, "fb.1.99.cookie");
});

test("a new session forgets the last session's click ids", () => {
  visit("https://shop.test/?gclid=G1");
  analytics.track("a");
  analytics.reset();
  visit("https://shop.test/plain");
  analytics.track("b");
  assert.equal(last().event_data.gclid, undefined);
  assert.equal(last().event_data.click_id, undefined);
});

test("session id is GA4-compatible: <client id>.<start seconds>", () => {
  doc.cookie = "_ga=GA1.1.555.666";
  analytics.reset();
  analytics.track("a");
  const sid = last().session_id;
  assert.match(sid, /^555\.666\.\d{10}$/);
  analytics.track("b");
  assert.equal(last().session_id, sid);
});

test("without _ga the session id uses the anonymous id", () => {
  analytics.track("a");
  const body = last();
  assert.ok(body.session_id.startsWith(body.device_id + "."));
  assert.match(body.session_id.slice(body.device_id.length + 1), /^\d{10}$/);
});

test("session renews after 30 minutes idle", () => {
  analytics.track("a");
  const sid = last().session_id;
  const realNow = Date.now;
  try {
    const later = realNow() + 31 * 60 * 1000;
    Date.now = () => later;
    const RealDate = Date;
    globalThis.Date = class extends RealDate {
      constructor(...a) { if (a.length) super(...a); else super(later); }
      static now() { return later; }
    };
    analytics.track("b");
    globalThis.Date = RealDate;
    assert.notEqual(last().session_id, sid);
    assert.match(last().session_id, new RegExp(`\\.${Math.floor(later / 1000)}$`));
  } finally {
    Date.now = realNow;
  }
});

test("identify forwards the ad ids so they land on the profile", () => {
  doc.cookie = "_fbp=fb.1.1700.42; _ga=GA1.1.555.666";
  visit("https://shop.test/?gclid=G1");
  analytics.identifyUser("u1", { email: "a@b.test" });
  const body = last();
  assert.equal(body.event_name, "_lowco_identify");
  assert.equal(body.user_id, "u1");
  assert.equal(body.event_data.gclid, "G1");
  assert.equal(body.event_data.fbp, "fb.1.1700.42");
  assert.equal(body.event_data.ga_client_id, "555.666");
  assert.equal(body.event_data.email, "a@b.test");
  assert.match(body.event_data.event_id, UUID);
});

test("mirrorEventIds sends the same event_id to fbq and gtag", () => {
  const calls = [];
  win.fbq = (...a) => calls.push(["fbq", ...a]);
  win.gtag = (...a) => calls.push(["gtag", ...a]);
  analytics.track("lead", { value: 1 });
  assert.equal(calls.length, 0, "off by default");
  analytics.init({ apiKey: "lc_test", orgId: "1", mirrorEventIds: true });
  const id = analytics.track("lead", { value: 1 });
  assert.deepEqual(calls, [
    ["fbq", "track", "Lead", { value: 1 }, { eventID: id }],
    ["gtag", "event", "lead", { value: 1, event_id: id }],
  ]);
});

test("trackBatch gives each event an event_id unless it has one", async () => {
  globalThis.fetch = async (url, init) => {
    sent.push({ url: String(url), body: JSON.parse(init.body) });
    return new Response(JSON.stringify({ data: { accepted: 2, rejected: 0, results: [] } }), { status: 200 });
  };
  await analytics.trackBatch([{ event_name: "a" }, { event_name: "b", event_data: { event_id: "keep" } }]);
  const [a, b] = last().events;
  assert.match(a.event_data.event_id, UUID);
  assert.equal(a.id, a.event_data.event_id);
  assert.equal(b.event_data.event_id, "keep");
});
