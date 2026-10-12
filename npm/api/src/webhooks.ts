import { createHmac, timingSafeEqual } from "node:crypto";

/** The signature header on every webhook delivery. */
export const SIGNATURE_HEADER = "Lowco-Signature";

/** Thrown by constructEvent when a delivery's signature does not verify. */
export class LowcoSignatureError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LowcoSignatureError";
  }
}

export interface VerifyOptions {
  /** Seconds a timestamp may differ from now (default 300). */
  toleranceSec?: number;
  /** The current time in seconds (for tests). */
  now?: number;
}

/**
 * Verifies `Lowco-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>`.
 * Pass the raw request body (before JSON parsing) and the endpoint's `whsec_…` secret as-is.
 * During a secret rotation the header may carry several v1 values; any one matching verifies.
 */
export function verifySignature(header: string | null | undefined, rawBody: string | Uint8Array, secret: string, options: VerifyOptions = {}): boolean {
  if (!header) return false;
  let t = 0;
  const sigs: string[] = [];
  for (const piece of header.split(",")) {
    const [k, v] = piece.trim().split("=");
    if (k === "t") t = Number.parseInt(v ?? "", 10);
    if (k === "v1" && v) sigs.push(v);
  }
  if (!t || sigs.length === 0) return false;
  const now = options.now ?? Date.now() / 1000;
  if (Math.abs(now - t) > (options.toleranceSec ?? 300)) return false;
  const body = typeof rawBody === "string" ? Buffer.from(rawBody, "utf8") : Buffer.from(rawBody);
  const expected = createHmac("sha256", secret).update(`${t}.`).update(body).digest("hex");
  return sigs.some((s) => s.length === expected.length && timingSafeEqual(Buffer.from(s), Buffer.from(expected)));
}

/** A webhook event. */
export interface WebhookEvent<T = unknown> {
  id: string;
  type: string;
  created_at: string;
  environment: "live" | "test";
  data: T;
}

/** Verifies a delivery and returns its event; throws LowcoSignatureError when the signature does not verify. */
export function constructEvent<T = unknown>(rawBody: string | Uint8Array, header: string | null | undefined, secret: string, options?: VerifyOptions): WebhookEvent<T> {
  if (!verifySignature(header, rawBody, secret, options)) {
    throw new LowcoSignatureError("The Lowco-Signature does not match this body and secret, or its timestamp is too old");
  }
  const text = typeof rawBody === "string" ? rawBody : new TextDecoder().decode(rawBody);
  return JSON.parse(text) as WebhookEvent<T>;
}
