import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CLICK_ID_KEYS,
  collectAdIds,
  createEventId,
  fbcFromFbclid,
  gaClientIdFromCookie,
  gaSessionId,
  mergeSessionClickIds,
  mirrorEventId,
  parseCookies,
  primaryClickId,
  readClickIds,
} from "../dist/index.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

test("click id keys match what engage-service reads", () => {
  assert.deepEqual([...CLICK_ID_KEYS], ["gclid", "gbraid", "wbraid", "fbclid", "msclkid", "ttclid", "li_fat_id"]);
});

test("readClickIds takes every click id on the URL and nothing else", () => {
  const ids = readClickIds("?utm_source=google&gclid=G1&gbraid=GB&wbraid=WB&fbclid=F1&li_fat_id=L1&ttclid=T1&msclkid=M1&x=1");
  assert.deepEqual(ids, { gclid: "G1", gbraid: "GB", wbraid: "WB", fbclid: "F1", li_fat_id: "L1", ttclid: "T1", msclkid: "M1" });
  assert.deepEqual(readClickIds(""), {});
  assert.deepEqual(readClickIds("?gclid="), {});
});

test("primaryClickId ranks google, then meta, microsoft, tiktok, linkedin", () => {
  assert.deepEqual(primaryClickId({ fbclid: "F", gclid: "G" }), { click_id: "G", click_id_kind: "gclid" });
  assert.deepEqual(primaryClickId({ li_fat_id: "L", ttclid: "T" }), { click_id: "T", click_id_kind: "ttclid" });
  assert.deepEqual(primaryClickId({}), {});
});

test("mergeSessionClickIds keeps the first value of each key", () => {
  assert.deepEqual(mergeSessionClickIds({ gclid: "first" }, { gclid: "second", fbclid: "F" }), { gclid: "first", fbclid: "F" });
});

test("parseCookies decodes values and keeps the first of duplicate names", () => {
  assert.deepEqual(parseCookies("a=1; _fbp=fb.1.1700.99; b=%20x; a=2; bad"), { a: "1", _fbp: "fb.1.1700.99", b: " x" });
  assert.deepEqual(parseCookies(""), {});
});

test("gaClientIdFromCookie reads the GA4 client id", () => {
  assert.equal(gaClientIdFromCookie("GA1.1.1812345678.1731312004"), "1812345678.1731312004");
  assert.equal(gaClientIdFromCookie("GA1.2.99.88"), "99.88");
  assert.equal(gaClientIdFromCookie("nonsense"), undefined);
  assert.equal(gaClientIdFromCookie("GS1.1.abc.def"), undefined);
  assert.equal(gaClientIdFromCookie(undefined), undefined);
});

test("fbcFromFbclid builds fb.1.<ms>.<fbclid> and leaves an fbc as is", () => {
  assert.equal(fbcFromFbclid("IwAR123", 1731312004123), "fb.1.1731312004123.IwAR123");
  assert.equal(fbcFromFbclid("fb.1.1.IwAR", 5), "fb.1.1.IwAR");
});

test("gaSessionId is <client id>.<start epoch seconds>", () => {
  assert.equal(gaSessionId("1812.1731", 1731312004999), "1812.1731.1731312004");
});

test("createEventId is a UUID v4 and unique", () => {
  const a = createEventId();
  assert.match(a, UUID);
  assert.notEqual(a, createEventId());
});

test("collectAdIds emits engage-service property names", () => {
  const out = collectAdIds({
    clickIds: { fbclid: "F1", li_fat_id: "L1" },
    cookie: "_fbp=fb.1.1700.42; _ga=GA1.1.555.666",
    derivedFbc: "fb.1.1731.F1",
    referrer: "https://l.facebook.com/",
    url: "https://shop.test/?fbclid=F1",
  });
  assert.deepEqual(out, {
    fbclid: "F1",
    li_fat_id: "L1",
    click_id: "F1",
    click_id_kind: "fbclid",
    fbp: "fb.1.1700.42",
    fbc: "fb.1.1731.F1",
    ga_client_id: "555.666",
    referrer: "https://l.facebook.com/",
    url: "https://shop.test/?fbclid=F1",
  });
});

test("collectAdIds prefers Meta's _fbc cookie over a derived fbc", () => {
  const out = collectAdIds({ clickIds: {}, cookie: "_fbc=fb.1.1.cookie", derivedFbc: "fb.1.2.derived" });
  assert.equal(out.fbc, "fb.1.1.cookie");
  assert.deepEqual(collectAdIds({ clickIds: {} }), {});
});

test("mirrorEventId sends the same id to fbq and gtag", () => {
  const calls = [];
  const target = { fbq: (...a) => calls.push(["fbq", ...a]), gtag: (...a) => calls.push(["gtag", ...a]) };
  const res = mirrorEventId(target, "purchase", "E1", { value: 10, currency: "INR", items: [1] });
  assert.deepEqual(res, { fbq: true, gtag: true });
  assert.deepEqual(calls, [
    ["fbq", "track", "Purchase", { value: 10, currency: "INR" }, { eventID: "E1" }],
    ["gtag", "event", "purchase", { value: 10, currency: "INR", event_id: "E1" }],
  ]);
  calls.length = 0;
  mirrorEventId(target, "quiz_done", "E2", {});
  assert.deepEqual(calls[0], ["fbq", "trackCustom", "quiz_done", {}, { eventID: "E2" }]);
});

test("mirrorEventId skips page_view, missing globals and throwing tags", () => {
  const calls = [];
  const target = { fbq: (...a) => calls.push(a), gtag: (...a) => calls.push(a) };
  assert.deepEqual(mirrorEventId(target, "page_view", "E", {}), { fbq: false, gtag: false });
  assert.deepEqual(mirrorEventId({}, "lead", "E", {}), { fbq: false, gtag: false });
  assert.deepEqual(mirrorEventId({ fbq: () => { throw new Error("x"); } }, "lead", "E", {}), { fbq: false, gtag: false });
  assert.equal(calls.length, 0);
});

test("createInlineSnippet emits mirrorEventIds only when on", async () => {
  const { createInlineSnippet } = await import("../dist/index.js");
  assert.match(createInlineSnippet({ mirrorEventIds: true }), /mirrorEventIds: true/);
  assert.doesNotMatch(createInlineSnippet({}), /mirrorEventIds/);
});
