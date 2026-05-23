/**
 * Thrown for every non-2xx response from the lowcodb manager.
 *
 * `statusCode` is always set. `message` and `code` are populated when the
 * manager returns its standard JSON error envelope; otherwise `message`
 * falls back to the raw response text and `code` is undefined.
 */
export class LowcodbError extends Error {
  readonly statusCode: number;
  readonly code?: string;
  readonly body: string;

  constructor(opts: { statusCode: number; message: string; code?: string; body: string }) {
    super(opts.message || `lowcodb: status=${opts.statusCode}`);
    this.name = "LowcodbError";
    this.statusCode = opts.statusCode;
    this.code = opts.code;
    this.body = opts.body;
  }
}
