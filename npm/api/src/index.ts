import { randomUUID } from "node:crypto";
import { Core, type Answer, type ClientOptions, type WaitOptions } from "./core.js";
import { GeneratedClient } from "./generated.js";

export * from "./generated.js";
export { Core, DEFAULT_BASE_URL, LowcoApiError, LowcoJobError, LowcoTimeoutError, SDK_VERSION } from "./core.js";
export type { Answer, CallOptions, ClientOptions, FileInput, FileRef, RequestOptions, WaitOptions } from "./core.js";
export { Files } from "./files.js";
export { constructEvent, LowcoSignatureError, SIGNATURE_HEADER, verifySignature } from "./webhooks.js";
export type { VerifyOptions, WebhookEvent } from "./webhooks.js";

/** A new Idempotency-Key: store it with your record before calling, and reuse it on retries. */
export function newIdempotencyKey(): string {
  return randomUUID();
}

/**
 * The Lowco API client.
 *
 * ```ts
 * const lowco = new LowcoApi(); // LOWCO_API_KEY
 * const answer = await lowco.docai.invoice({ file: Files.path("invoice.pdf") }, { mode: "async" });
 * const invoice = await lowco.waitForResult(answer);
 * ```
 */
export class LowcoApi extends GeneratedClient {
  constructor(options: ClientOptions = {}) {
    super(new Core(options));
  }

  /** The result of an operation's answer: inline data, or the job's result once it finishes (polling with Retry-After). */
  waitForResult<T>(answer: Answer<T>, options?: WaitOptions): Promise<T> {
    return this.core.waitForResult(answer, options);
  }
}
