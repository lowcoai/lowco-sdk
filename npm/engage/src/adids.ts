import type { Metadata } from "./types";

/**
 * Ad click ids read from the landing URL, in the order engage-service ranks
 * them when one event carries several (core/attribution `clickIDs`).
 */
export const CLICK_ID_KEYS = [
  "gclid",
  "gbraid",
  "wbraid",
  "fbclid",
  "msclkid",
  "ttclid",
  "li_fat_id",
] as const;

export type ClickIdKey = (typeof CLICK_ID_KEYS)[number];

/** Parses `document.cookie` into name → value (values URI-decoded when valid). */
export function parseCookies(cookie: string | undefined | null): Record<string, string> {
  const out: Record<string, string> = {};
  if (!cookie) return out;
  for (const part of cookie.split(";")) {
    const eq = part.indexOf("=");
    if (eq <= 0) continue;
    const name = part.slice(0, eq).trim();
    let value = part.slice(eq + 1).trim();
    try {
      value = decodeURIComponent(value);
    } catch {
      // keep the raw value
    }
    if (name && !(name in out)) out[name] = value;
  }
  return out;
}

/**
 * GA4's client id from the `_ga` cookie: `GA1.1.1812345678.1731312004` →
 * `1812345678.1731312004` (the last two dot-separated parts). Undefined when
 * the cookie is absent or malformed.
 */
export function gaClientIdFromCookie(value: string | undefined | null): string | undefined {
  if (!value) return undefined;
  const parts = value.trim().split(".");
  if (parts.length < 4 || !/^GA\d+$/i.test(parts[0] ?? "")) return undefined;
  const id = parts.slice(-2).join(".");
  return /^\d+\.\d+$/.test(id) ? id : undefined;
}

/** Meta's `fbc` value built from a bare `fbclid`: `fb.1.<epoch ms>.<fbclid>`. */
export function fbcFromFbclid(fbclid: string, nowMs: number = Date.now()): string {
  if (fbclid.startsWith("fb.")) return fbclid;
  return `fb.1.${Math.floor(nowMs)}.${fbclid}`;
}

/** The click ids present in a URL query string. */
export function readClickIds(search: string | undefined | null): Partial<Record<ClickIdKey, string>> {
  const out: Partial<Record<ClickIdKey, string>> = {};
  if (!search) return out;
  try {
    const params = new URLSearchParams(search);
    for (const key of CLICK_ID_KEYS) {
      const v = params.get(key)?.trim();
      if (v) out[key] = v.slice(0, 500);
    }
  } catch {
    // unparsable query: no click ids
  }
  return out;
}

/** The highest-ranked click id as `{ click_id, click_id_kind }`, or {}. */
export function primaryClickId(ids: Partial<Record<ClickIdKey, string>>): Metadata {
  for (const key of CLICK_ID_KEYS) {
    const v = ids[key];
    if (v) return { click_id: v, click_id_kind: key };
  }
  return {};
}

/**
 * Merges click ids seen on this page into the session's stored ones; a key
 * already stored for the session keeps its first value (first touch).
 */
export function mergeSessionClickIds(
  stored: Partial<Record<ClickIdKey, string>>,
  current: Partial<Record<ClickIdKey, string>>,
): Partial<Record<ClickIdKey, string>> {
  const out: Partial<Record<ClickIdKey, string>> = { ...stored };
  for (const key of CLICK_ID_KEYS) {
    const v = current[key];
    if (v && !out[key]) out[key] = v;
  }
  return out;
}

/** GA4-compatible session id: `<client id>.<session start epoch seconds>`. */
export function gaSessionId(clientId: string, sessionStartMs: number): string {
  return `${clientId}.${Math.floor(sessionStartMs / 1000)}`;
}

/** A random UUID v4 (crypto.randomUUID when available). */
export function createEventId(): string {
  const c: Crypto | undefined = typeof crypto !== "undefined" ? crypto : undefined;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();
  const bytes = new Uint8Array(16);
  if (c && typeof c.getRandomValues === "function") {
    c.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  }
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export interface AdIdsInput {
  /** Click ids kept for the session (already merged with this page's). */
  clickIds: Partial<Record<ClickIdKey, string>>;
  /** `document.cookie`. */
  cookie?: string | null;
  /** A stored `fbc` derived from fbclid earlier this session (stable ts). */
  derivedFbc?: string;
  referrer?: string;
  url?: string;
}

/**
 * The ad identifiers every event carries, under the property names
 * engage-service reads (destinations `identifiersOf`, attribution `VisitOf`,
 * web analytics): the click ids, `click_id`/`click_id_kind`, `fbp`, `fbc`,
 * `ga_client_id`, `referrer` and `url`. Empty values are left out.
 */
export function collectAdIds(input: AdIdsInput): Metadata {
  const out: Metadata = {};
  for (const key of CLICK_ID_KEYS) {
    const v = input.clickIds[key];
    if (v) out[key] = v;
  }
  Object.assign(out, primaryClickId(input.clickIds));
  const cookies = parseCookies(input.cookie);
  const fbp = cookies._fbp?.trim();
  if (fbp) out.fbp = fbp;
  const fbc = cookies._fbc?.trim() || input.derivedFbc;
  if (fbc) out.fbc = fbc;
  const ga = gaClientIdFromCookie(cookies._ga);
  if (ga) out.ga_client_id = ga;
  if (input.referrer) out.referrer = input.referrer;
  if (input.url) out.url = input.url;
  return out;
}

/** Meta standard events for the event names the SDK mirrors onto `fbq`. */
const META_STANDARD_EVENTS: Record<string, string> = {
  lead: "Lead",
  lead_submitted: "Lead",
  form_submitted: "Lead",
  signup_completed: "CompleteRegistration",
  complete_registration: "CompleteRegistration",
  purchase: "Purchase",
  order_completed: "Purchase",
  add_to_cart: "AddToCart",
  initiate_checkout: "InitiateCheckout",
  checkout_started: "InitiateCheckout",
  view_content: "ViewContent",
  product_viewed: "ViewContent",
  contact: "Contact",
  subscribe: "Subscribe",
  search: "Search",
};

type Fn = (...args: unknown[]) => unknown;

/** Scalar properties only: the pixel and gtag take flat parameters. */
function flatParams(props: Metadata): Metadata {
  const out: Metadata = {};
  for (const [k, v] of Object.entries(props)) {
    if (v === null || v === undefined) continue;
    if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") out[k] = v;
  }
  return out;
}

/**
 * Sends the same event to the Meta pixel (`fbq`, with `eventID`) and gtag
 * (`event_id` parameter) when those globals exist, so the platforms dedupe
 * it against what Engage later forwards server-side. Returns which were
 * called. `page_view` is never mirrored: the pixel base code and
 * `gtag('config')` already send their own page views. Errors in either
 * global are swallowed.
 */
export function mirrorEventId(
  target: { fbq?: unknown; gtag?: unknown } | undefined,
  eventName: string,
  eventId: string,
  props: Metadata,
): { fbq: boolean; gtag: boolean } {
  const called = { fbq: false, gtag: false };
  if (!target || eventName === "page_view") return called;
  const params = flatParams(props);
  if (typeof target.fbq === "function") {
    try {
      const std = META_STANDARD_EVENTS[eventName];
      (target.fbq as Fn)(std ? "track" : "trackCustom", std ?? eventName, params, { eventID: eventId });
      called.fbq = true;
    } catch {
      // the pixel failing never breaks tracking
    }
  }
  if (typeof target.gtag === "function") {
    try {
      (target.gtag as Fn)("event", eventName, { ...params, event_id: eventId });
      called.gtag = true;
    } catch {
      // gtag failing never breaks tracking
    }
  }
  return called;
}
