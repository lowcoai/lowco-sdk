/**
 * Thrown for every non-2xx response from the lowcodb manager.
 *
 * `statusCode` is always set. `message` and `code` are populated when the
 * manager returns its standard JSON error envelope; otherwise `message`
 * falls back to the raw response text and `code` is undefined.
 */
export class LowcodbError extends Error {
  readonly statusCode: number;
  /** The manager sends the numeric HTTP status in `error.code`, so this may be a number. */
  readonly code?: string | number;
  readonly body: string;

  constructor(opts: { statusCode: number; message: string; code?: string | number; body: string }) {
    super(opts.message || `lowcodb: status=${opts.statusCode}`);
    this.name = "LowcodbError";
    this.statusCode = opts.statusCode;
    this.code = opts.code;
    this.body = opts.body;
  }
}

/** Body code of a 402 from a base's gateway: the plan cap for the metered resource is reached. */
export const CODE_QUOTA_EXCEEDED = "QUOTA_EXCEEDED";

/**
 * Thrown for a 402 QUOTA_EXCEEDED from the gateway. Carries the quota plane's body so a
 * caller can explain, wait for `periodEnd`, or offer the upgrade. `instanceof
 * LowcodbError` still holds.
 */
export class QuotaExceededError extends LowcodbError {
  /** The metered resource, e.g. "vlbrofrujc_employees_create". */
  readonly meter: string;
  /** The period's usage and the plan's allowance. */
  readonly consumed: number;
  readonly included: number;
  /** The ceiling that refused the call; null when the plan has none. */
  readonly hardCap: number | null;
  /** When the usage window resets (RFC 3339), when known. */
  readonly periodEnd?: string;
  /** Product whose plan applies. */
  readonly appKey?: string;
  /** What would lift the cap, when the plane says. */
  readonly upgrade?: { appKey?: string; plans?: string[] };

  constructor(opts: {
    statusCode: number;
    message: string;
    body: string;
    meter: string;
    consumed: number;
    included: number;
    hardCap: number | null;
    periodEnd?: string;
    appKey?: string;
    upgrade?: { appKey?: string; plans?: string[] };
  }) {
    super({ statusCode: opts.statusCode, message: opts.message, code: CODE_QUOTA_EXCEEDED, body: opts.body });
    this.name = "QuotaExceededError";
    this.meter = opts.meter;
    this.consumed = opts.consumed;
    this.included = opts.included;
    this.hardCap = opts.hardCap;
    this.periodEnd = opts.periodEnd;
    this.appKey = opts.appKey;
    this.upgrade = opts.upgrade;
  }
}

/** Whether `err` is a 402 QUOTA_EXCEEDED from the gateway. */
export function isQuotaExceeded(err: unknown): err is QuotaExceededError {
  return err instanceof QuotaExceededError;
}

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);

/**
 * Reads a 402 body (the plane's QuotaError) leniently: the keeper writes it at the top
 * level, an envelope would nest it under `error`. Returns undefined when it is not one.
 */
export function parseQuotaExceeded(status: number, fallbackMessage: string, text: string): QuotaExceededError | undefined {
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(text) as Record<string, unknown>;
  } catch {
    return undefined;
  }
  if (!raw || typeof raw !== "object") return undefined;
  const nested = raw.error as Record<string, unknown> | undefined;
  const fields = nested && typeof nested === "object" && "code" in nested ? nested : raw;
  if (String(fields.code ?? "").toUpperCase() !== CODE_QUOTA_EXCEEDED) return undefined;
  const upgradeRaw = fields.upgrade as Record<string, unknown> | undefined;
  const upgrade =
    upgradeRaw && typeof upgradeRaw === "object"
      ? {
          appKey: (upgradeRaw.app_key as string | undefined) ?? (upgradeRaw.appKey as string | undefined),
          plans: Array.isArray(upgradeRaw.plans) ? (upgradeRaw.plans as string[]) : undefined,
        }
      : undefined;
  return new QuotaExceededError({
    statusCode: status,
    message: typeof fields.message === "string" && fields.message.trim() ? fields.message : fallbackMessage,
    body: text,
    meter: typeof fields.meter === "string" ? fields.meter : "",
    consumed: num(fields.consumed),
    included: num(fields.included),
    hardCap: fields.hard_cap === null || fields.hard_cap === undefined ? null : num(fields.hard_cap),
    periodEnd: typeof fields.period_end === "string" ? fields.period_end : undefined,
    appKey: typeof fields.app_key === "string" ? fields.app_key : undefined,
    upgrade,
  });
}
