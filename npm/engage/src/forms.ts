/**
 * Engage forms in the browser (WS4.3): the live forms of the app are fetched
 * from GET /v1/engage/sdk/forms and shown by their display rules — popup,
 * slide-in, top bar, or inline into `<div data-engage-form="<id>">` — when
 * their trigger fires (immediately, after a delay, on scroll, on exit intent
 * or when an event is tracked), on the pages they include, to the audience
 * they target, as often as their frequency allows. Answers go to
 * POST /v1/engage/sdk/forms/{id}/submit; every display counts a view.
 *
 * The DOM is self-contained: no framework, one injected stylesheet scoped to
 * `.lcf-root`, text set as text (never HTML). This file is shared verbatim by
 * `@lowco/engage-core` and the publishable `@lowcoai/engage`.
 */

export type FormFieldType =
  | "email"
  | "phone"
  | "text"
  | "textarea"
  | "select"
  | "checkbox"
  | "rating"
  | "nps"
  | "hidden";

export interface FormField {
  key: string;
  type: FormFieldType;
  label: string;
  placeholder?: string;
  required?: boolean;
  options?: string[];
}

export interface FormContent {
  title?: string;
  body?: string;
  submitLabel?: string;
  successTitle?: string;
  successBody?: string;
  imageUrl?: string;
  privacyText?: string;
  /** Button colour (#hex). */
  accent?: string;
}

export type FormTriggerType = "immediate" | "delay" | "scroll" | "exit_intent" | "event";

export interface FormTrigger {
  type: FormTriggerType;
  seconds?: number;
  percent?: number;
  event?: string;
}

export type FormMode = "popup" | "slide_in" | "bar" | "inline";

export interface FormDisplay {
  mode: FormMode;
  trigger: FormTrigger;
  /** once (never again after an answer or close), session or always. */
  frequency?: "once" | "session" | "always";
  /** Days to wait after a close before showing the form again. */
  daysBetween?: number;
  /** Page path patterns (`*` wildcard); a pattern starting with http(s):// matches the full URL. */
  include?: string[];
  exclude?: string[];
  /** anyone, anonymous (not identified yet) or known (identified). */
  audience?: "anyone" | "anonymous" | "known";
}

export interface FormConsent {
  channel: string;
  purpose?: string;
  doubleOptIn?: boolean;
}

/** A live form as the SDK receives it (GET /v1/engage/sdk/forms). */
export interface EngageForm {
  id: string;
  kind: string;
  name: string;
  fields: FormField[];
  content: FormContent;
  display: FormDisplay;
  consent?: FormConsent;
  redirectUrl?: string;
  referralReward?: string;
}

/** How an answer was taken (POST /v1/engage/sdk/forms/{id}/submit). */
export interface FormSubmitResult {
  ok: boolean;
  responseId?: string;
  title?: string;
  message?: string;
  redirectUrl?: string;
  /** "sent" when a double opt-in email went out. */
  confirmation?: string;
}

export interface FormFieldError {
  field: string;
  message: string;
}

/** What the forms runtime needs from the analytics client. */
export interface FormsHost {
  baseUrl(): string;
  headers(): Record<string, string>;
  userId(): string | null;
  anonymousId(): string | null;
  sessionId(): string | null;
}

interface FormMemory {
  shownAt?: number;
  closedAt?: number;
  submittedAt?: number;
  /** The SDK session the form was last shown in (frequency "session"). */
  session?: string;
}

interface Armed {
  off: () => void;
  fire: () => void;
  event?: string;
}

interface Mounted {
  mode: FormMode;
  root: HTMLElement;
  close: (byUser: boolean) => void;
}

export const FORMS_PATH = "/v1/engage/sdk/forms";
export const FORMS_MEMORY_KEY = "lowco_forms";
export const HONEYPOT_FIELD = "_hp";
const STYLE_ID = "lowco-forms-style";
const FETCH_TTL_MS = 60_000;
const DAY_MS = 86_400_000;
const RENDERED_ATTR = "data-engage-form-rendered";
const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

const hasDom = (): boolean => typeof window !== "undefined" && typeof document !== "undefined";

/**
 * Whether `pattern` (`*` wildcard, case-insensitive) matches the page: a
 * pattern starting with http(s):// is matched against the URL without its
 * hash, anything else against the path. A trailing slash doesn't matter.
 */
export function matchPagePattern(pattern: string, path: string, href: string): boolean {
  const p = pattern.trim();
  if (!p) return false;
  const target = /^https?:\/\//i.test(p) ? (href.split("#")[0] ?? "") : path;
  const strip = (s: string) => (s.length > 1 && s.endsWith("/") ? s.slice(0, -1) : s);
  const source = strip(p)
    .split("*")
    .map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
    .join(".*");
  return new RegExp(`^${source}$`, "i").test(strip(target));
}

/** Whether the form's include/exclude patterns allow this page. */
export function pageAllowed(display: FormDisplay, path: string, href: string): boolean {
  const include = (display.include ?? []).filter((p) => p.trim() !== "");
  const exclude = (display.exclude ?? []).filter((p) => p.trim() !== "");
  if (include.length > 0 && !include.some((p) => matchPagePattern(p, path, href))) return false;
  return !exclude.some((p) => matchPagePattern(p, path, href));
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function isEmail(value: string): boolean {
  return EMAIL_RE.test(value);
}

/** At least 7 digits, and only digits, spaces, +, -, ., ( and ). */
export function isPhone(value: string): boolean {
  return /^[+\d\s().-]+$/.test(value) && value.replace(/\D/g, "").length >= 7;
}

function uuid(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** http(s) URLs only (no javascript:, data: …). */
function safeUrl(value: string | undefined, allowDataImage = false): string | null {
  if (!value) return null;
  const v = value.trim();
  if (/^https?:\/\//i.test(v)) return v;
  if (allowDataImage && /^data:image\//i.test(v)) return v;
  return null;
}

function safeColor(value: string | undefined): string | null {
  if (!value) return null;
  const v = value.trim();
  if (/^#[0-9a-f]{3,8}$/i.test(v)) return v;
  if (/^(rgb|rgba|hsl|hsla)\([\d\s.,%]+\)$/i.test(v)) return v;
  return null;
}

function normalizeForm(raw: unknown): EngageForm | null {
  if (!raw || typeof raw !== "object") return null;
  const f = raw as Partial<EngageForm>;
  if (typeof f.id !== "string" || !f.id || !Array.isArray(f.fields)) return null;
  const display = (f.display ?? {}) as Partial<FormDisplay>;
  return {
    id: f.id,
    kind: typeof f.kind === "string" ? f.kind : "",
    name: typeof f.name === "string" ? f.name : "",
    fields: f.fields.filter((fd): fd is FormField => !!fd && typeof fd.key === "string" && typeof fd.type === "string"),
    content: f.content && typeof f.content === "object" ? f.content : {},
    display: {
      ...display,
      mode: display.mode ?? "popup",
      trigger: display.trigger && typeof display.trigger === "object" ? display.trigger : { type: "immediate" },
    },
    consent: f.consent,
    redirectUrl: f.redirectUrl,
    referralReward: f.referralReward,
  };
}

type Attrs = Record<string, string | number | boolean | undefined | null>;

function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Attrs = {},
  children: (Node | string | null | undefined | false)[] = [],
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue;
    if (name === "text") el.textContent = String(value);
    else el.setAttribute(name, value === true ? "" : String(value));
  }
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    el.appendChild(typeof child === "string" ? document.createTextNode(child) : child);
  }
  return el;
}

const CSS = `
.lcf-root{--lcf-accent:#1a1a1a;--lcf-fg:#1a1a1a;--lcf-muted:#5a5a5a;--lcf-bg:#fff;--lcf-border:#cfcfcf;--lcf-error:#b00020;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:16px;line-height:1.45;color:var(--lcf-fg);text-align:left}
.lcf-root *,.lcf-root *::before,.lcf-root *::after{box-sizing:border-box}
.lcf-overlay{position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;padding:16px}
.lcf-backdrop{position:absolute;inset:0;background:rgba(0,0,0,.45)}
.lcf-card{position:relative;background:var(--lcf-bg);color:var(--lcf-fg);border-radius:14px;box-shadow:0 10px 40px rgba(0,0,0,.18);padding:24px}
.lcf-popup{width:100%;max-width:460px;max-height:calc(100vh - 32px);overflow:auto}
.lcf-slide{position:fixed;right:16px;bottom:16px;z-index:2147483000;width:360px;max-width:calc(100vw - 32px);max-height:calc(100vh - 32px);overflow:auto}
.lcf-bar{position:fixed;left:0;right:0;top:0;z-index:2147483000;border-radius:0;padding:12px 56px 12px 16px;box-shadow:0 2px 12px rgba(0,0,0,.12)}
.lcf-inline{box-shadow:none;border:1px solid var(--lcf-border)}
.lcf-close{position:absolute;top:8px;right:8px;width:40px;height:40px;border:0;background:transparent;border-radius:8px;font-size:24px;line-height:1;cursor:pointer;color:var(--lcf-muted)}
.lcf-close:hover{background:rgba(0,0,0,.06)}
.lcf-close:focus-visible{outline:2px solid var(--lcf-accent);outline-offset:2px}
.lcf-title{font-size:20px;font-weight:700;line-height:1.3;margin:0 36px 6px 0}
.lcf-body{margin:0 0 14px;color:var(--lcf-muted)}
.lcf-reward{margin:0 0 14px;font-weight:600}
.lcf-image{display:block;width:100%;height:auto;border-radius:10px;margin:0 0 14px}
.lcf-field{margin:0 0 14px;border:0;padding:0;min-width:0}
.lcf-label{display:block;font-weight:600;margin:0 0 6px;font-size:15px;padding:0}
.lcf-req{color:var(--lcf-error);margin-left:2px}
.lcf-input{display:block;width:100%;min-height:44px;margin:0;padding:10px 12px;font:inherit;font-size:16px;color:inherit;background:#fff;border:1px solid var(--lcf-border);border-radius:8px}
textarea.lcf-input{min-height:96px;resize:vertical}
.lcf-input:focus{outline:2px solid var(--lcf-accent);outline-offset:1px}
.lcf-input[aria-invalid="true"]{border-color:var(--lcf-error)}
.lcf-check{display:flex;gap:10px;align-items:flex-start;font-size:15px;cursor:pointer;min-height:44px;padding-top:10px}
.lcf-check input{width:20px;height:20px;margin:1px 0 0;flex:none;accent-color:var(--lcf-accent)}
.lcf-scale{display:flex;flex-wrap:wrap;gap:6px}
.lcf-scale label{position:relative;flex:1 0 36px}
.lcf-scale input{position:absolute;inset:0;opacity:0;width:100%;height:100%;margin:0;cursor:pointer}
.lcf-scale span{display:flex;align-items:center;justify-content:center;min-height:44px;border:1px solid var(--lcf-border);border-radius:8px;font-weight:600}
.lcf-scale input:checked+span{background:var(--lcf-accent);border-color:var(--lcf-accent);color:#fff}
.lcf-scale input:focus-visible+span{outline:2px solid var(--lcf-accent);outline-offset:2px}
.lcf-hints{display:flex;justify-content:space-between;font-size:13px;color:var(--lcf-muted);margin-top:4px}
.lcf-error{color:var(--lcf-error);font-size:14px;margin:6px 0 0}
.lcf-error:empty,.lcf-status:empty{display:none}
.lcf-submit{display:inline-flex;align-items:center;justify-content:center;width:100%;min-height:46px;padding:0 22px;border:0;border-radius:8px;background:var(--lcf-accent);color:#fff;font:inherit;font-weight:600;cursor:pointer}
.lcf-submit:focus-visible{outline:2px solid var(--lcf-accent);outline-offset:2px}
.lcf-submit[disabled]{opacity:.6;cursor:progress}
.lcf-status{font-size:14px;color:var(--lcf-error);margin:10px 0 0}
.lcf-privacy{font-size:13px;color:var(--lcf-muted);margin:12px 0 0}
.lcf-hp{position:absolute!important;left:-10000px!important;top:auto!important;width:1px!important;height:1px!important;overflow:hidden!important}
.lcf-success{outline:none}
.lcf-bar .lcf-form{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-end}
.lcf-bar .lcf-field{margin:0;flex:1 1 200px}
.lcf-bar .lcf-submit{width:auto}
.lcf-bar .lcf-title{font-size:16px;margin:0 0 4px}
.lcf-bar .lcf-body{margin:0 0 8px}
@keyframes lcf-in{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.lcf-popup,.lcf-slide,.lcf-bar{animation:lcf-in .18s ease-out}
@media (prefers-reduced-motion:reduce){.lcf-popup,.lcf-slide,.lcf-bar{animation:none}}
@media (max-width:520px){.lcf-overlay{align-items:flex-end;padding:0}.lcf-popup{max-width:none;max-height:90vh;border-radius:16px 16px 0 0}.lcf-slide{left:0;right:0;bottom:0;width:auto;max-width:none;border-radius:16px 16px 0 0}.lcf-bar .lcf-form{flex-direction:column;align-items:stretch}.lcf-bar .lcf-submit{width:100%}}
`;

function injectStyles(): void {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = CSS;
  (document.head ?? document.documentElement).appendChild(style);
}

let instanceSeq = 0;

/**
 * The forms runtime behind `LowcoAnalytics.showForm` and `init({forms: true})`.
 * With `autoShow` it shows forms by their display rules; without it forms
 * only appear through `show(id)`.
 */
export class EngageForms {
  /** Replaced in tests; follows a form's redirect URL after an answer. */
  navigate: (url: string) => void = (url) => window.location.assign(url);

  private forms: EngageForm[] = [];
  private fetchedAt = 0;
  private loading: Promise<EngageForm[]> | null = null;
  private armed = new Map<string, Armed>();
  private shownThisPage = new Set<string>();
  private eventsThisPage = new Set<string>();
  private open = new Map<string, Mounted>();
  private observer: MutationObserver | null = null;
  private scanQueued = false;
  private suppressed = false;
  private path: string | null = null;

  constructor(
    private readonly host: FormsHost,
    private autoShow: boolean,
  ) {}

  /** The forms fetched last. */
  list(): EngageForm[] {
    return this.forms.slice();
  }

  setAutoShow(on: boolean): void {
    this.autoShow = on;
    if (!on) this.disarmAll();
  }

  /** Fetches the live forms and shows the ones whose rules allow it. */
  async start(): Promise<void> {
    if (!hasDom()) return;
    this.path = window.location.pathname;
    this.observe();
    await this.fetchForms(false);
    this.evaluate();
  }

  /** Re-fetches (ignoring the 60 s cache) and re-applies the rules. */
  async refresh(): Promise<EngageForm[]> {
    this.suppressed = false;
    const forms = await this.fetchForms(true);
    this.evaluate();
    return forms;
  }

  /** An SPA navigation: a new page for triggers, frequency and patterns. */
  onRouteChange(): void {
    if (!hasDom()) return;
    const path = window.location.pathname;
    if (path === this.path) return;
    this.path = path;
    this.disarmAll();
    this.shownThisPage.clear();
    this.eventsThisPage.clear();
    this.suppressed = false;
    if (!this.autoShow) return;
    void this.fetchForms(false).then(() => this.evaluate());
  }

  /** An event was tracked on this page: shows forms triggered by it. */
  onEvent(name: string): void {
    this.eventsThisPage.add(name);
    for (const armed of Array.from(this.armed.values())) {
      if (armed.event === name) armed.fire();
    }
  }

  /** The person was identified or reset: the audience may have changed. */
  onIdentityChange(): void {
    this.evaluate();
  }

  /**
   * Shows a form now, whatever its trigger, pages, audience or frequency.
   * An inline form fills its `[data-engage-form]` elements, or opens as a
   * popup when the page has none. Resolves false when the form isn't live.
   */
  async show(id: string): Promise<boolean> {
    if (!hasDom()) return false;
    let form = this.byId(id);
    if (!form) {
      await this.fetchForms(false);
      form = this.byId(id);
    }
    if (!form) return false;
    this.disarm(id);
    return this.display(form, "api");
  }

  /**
   * Closes every popup, slide-in and bar (not counted as the person closing
   * them) and holds back pending triggers until the next page or refresh.
   * Inline forms stay: they are part of the page.
   */
  hideAll(): void {
    this.suppressed = true;
    this.disarmAll();
    for (const mounted of Array.from(this.open.values())) mounted.close(false);
  }

  /** Removes everything the runtime added. */
  destroy(): void {
    this.hideAll();
    this.observer?.disconnect();
    this.observer = null;
  }

  // --- Fetching -------------------------------------------------------------

  private fetchForms(force: boolean): Promise<EngageForm[]> {
    if (!force && this.fetchedAt && Date.now() - this.fetchedAt < FETCH_TTL_MS) {
      return Promise.resolve(this.forms);
    }
    if (this.loading) return this.loading;
    const p = this.load().finally(() => {
      if (this.loading === p) this.loading = null;
    });
    this.loading = p;
    return p;
  }

  private async load(): Promise<EngageForm[]> {
    try {
      const res = await fetch(`${this.host.baseUrl()}${FORMS_PATH}`, { headers: this.host.headers() });
      this.fetchedAt = Date.now();
      if (!res.ok) return this.forms;
      const body = await res.json();
      const data: unknown[] = Array.isArray(body?.data) ? body.data : [];
      this.forms = data.map(normalizeForm).filter((f): f is EngageForm => f !== null);
    } catch {
      this.fetchedAt = Date.now();
    }
    return this.forms;
  }

  private byId(id: string): EngageForm | undefined {
    return this.forms.find((f) => f.id === id);
  }

  // --- Rules ----------------------------------------------------------------

  private eligible(form: EngageForm): boolean {
    const d = form.display;
    if (!pageAllowed(d, window.location.pathname, window.location.href)) return false;
    const known = !!this.host.userId();
    if (d.audience === "known" && !known) return false;
    if (d.audience === "anonymous" && known) return false;
    const mem = this.memory()[form.id] ?? {};
    const now = Date.now();
    const days = d.daysBetween ?? 0;
    if (mem.closedAt && days > 0 && now - mem.closedAt < days * DAY_MS) return false;
    const frequency = d.frequency || (d.mode === "inline" ? "always" : "once");
    switch (frequency) {
      case "always":
        return true;
      case "session": {
        const session = this.host.sessionId();
        return !mem.session || !session || mem.session !== session;
      }
      default:
        if (mem.submittedAt) return false;
        // Closed: never again, unless daysBetween (checked above) has passed.
        return !mem.closedAt || days > 0;
    }
  }

  private evaluate(): void {
    if (!hasDom() || !this.autoShow) return;
    for (const [id, armed] of Array.from(this.armed.entries())) {
      const form = this.byId(id);
      if (!form || this.suppressed || !this.eligible(form)) {
        armed.off();
        this.armed.delete(id);
      }
    }
    if (this.suppressed) return;
    for (const form of this.forms) {
      if (form.display.mode === "inline") continue;
      if (this.armed.has(form.id) || this.shownThisPage.has(form.id) || this.open.has(form.id)) continue;
      if (this.eligible(form)) this.arm(form);
    }
    this.scanInline();
  }

  private arm(form: EngageForm): void {
    const trigger = form.display.trigger ?? { type: "immediate" };
    const fire = () => {
      this.disarm(form.id);
      if (this.suppressed || this.open.has(form.id) || !this.eligible(form)) return;
      this.display(form, "auto");
    };
    let off = () => {};
    let event: string | undefined;
    let fireNow = false;
    switch (trigger.type) {
      case "delay": {
        const timer = setTimeout(fire, Math.max(0, Number(trigger.seconds) || 0) * 1000);
        off = () => clearTimeout(timer);
        break;
      }
      case "scroll": {
        const percent = Math.min(100, Math.max(0, trigger.percent ?? 50));
        const onScroll = () => {
          if (scrolledPercent() >= percent) fire();
        };
        window.addEventListener("scroll", onScroll, { passive: true });
        off = () => window.removeEventListener("scroll", onScroll);
        break;
      }
      case "exit_intent": {
        const onOut = (e: MouseEvent) => {
          if (!e.relatedTarget && e.clientY <= 0) fire();
        };
        document.addEventListener("mouseout", onOut);
        off = () => document.removeEventListener("mouseout", onOut);
        break;
      }
      case "event":
        event = trigger.event;
        fireNow = !!event && this.eventsThisPage.has(event);
        break;
      default:
        fireNow = true;
    }
    this.armed.set(form.id, { off, fire, event });
    if (fireNow) fire();
  }

  private disarm(id: string): void {
    const armed = this.armed.get(id);
    if (!armed) return;
    armed.off();
    this.armed.delete(id);
  }

  private disarmAll(): void {
    for (const armed of Array.from(this.armed.values())) armed.off();
    this.armed.clear();
  }

  // --- Memory (localStorage, per form id) -------------------------------------

  private memory(): Record<string, FormMemory> {
    try {
      const raw = window.localStorage.getItem(FORMS_MEMORY_KEY);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === "object" ? (parsed as Record<string, FormMemory>) : {};
    } catch {
      return {};
    }
  }

  private remember(id: string, patch: FormMemory): void {
    try {
      const all = this.memory();
      all[id] = { ...all[id], ...patch };
      window.localStorage.setItem(FORMS_MEMORY_KEY, JSON.stringify(all));
    } catch {
      // Storage blocked: the form may show again; nothing else breaks.
    }
  }

  private markShown(form: EngageForm): void {
    this.remember(form.id, { shownAt: Date.now(), session: this.host.sessionId() ?? undefined });
    if (this.shownThisPage.has(form.id)) return;
    this.shownThisPage.add(form.id);
    void fetch(`${this.host.baseUrl()}${FORMS_PATH}/${encodeURIComponent(form.id)}/view`, {
      method: "POST",
      headers: this.host.headers(),
      body: "{}",
    }).catch(() => {});
  }

  // --- Display ----------------------------------------------------------------

  private display(form: EngageForm, source: "auto" | "api"): boolean {
    let mode: FormMode = form.display.mode;
    if (mode === "inline") {
      const targets = inlineTargets(form.id);
      if (targets.length > 0) {
        targets.forEach((el) => this.renderInline(form, el, true));
        return true;
      }
      if (source === "auto") return false;
      mode = "popup";
    }
    if (mode !== "slide_in" && mode !== "bar") mode = "popup";
    if (this.open.has(form.id)) return true;
    for (const mounted of Array.from(this.open.values())) {
      if (mounted.mode !== mode) continue;
      if (source === "auto") {
        // One popup (slide-in, bar) at a time; this one waits for the next page.
        this.shownThisPage.add(form.id);
        return false;
      }
      mounted.close(false);
    }
    injectStyles();
    this.open.set(form.id, this.mountOverlay(form, mode));
    this.markShown(form);
    return true;
  }

  private observe(): void {
    if (this.observer || typeof MutationObserver === "undefined" || !document.body) return;
    this.observer = new MutationObserver(() => {
      if (this.scanQueued) return;
      this.scanQueued = true;
      setTimeout(() => {
        this.scanQueued = false;
        this.scanInline();
      }, 0);
    });
    this.observer.observe(document.body, { childList: true, subtree: true });
  }

  /** Fills the page's `[data-engage-form]` elements with their inline forms. */
  private scanInline(): void {
    if (!hasDom() || !this.autoShow || this.forms.length === 0) return;
    for (const el of Array.from(document.querySelectorAll<HTMLElement>("[data-engage-form]"))) {
      const id = el.getAttribute("data-engage-form") ?? "";
      if (el.getAttribute(RENDERED_ATTR) === id) continue;
      const form = this.byId(id);
      if (!form || form.display.mode !== "inline" || !this.eligible(form)) continue;
      this.renderInline(form, el, false);
    }
  }

  private renderInline(form: EngageForm, el: HTMLElement, force: boolean): void {
    if (!force && el.getAttribute(RENDERED_ATTR) === form.id) return;
    injectStyles();
    el.setAttribute(RENDERED_ATTR, form.id);
    const root = h("div", { class: "lcf-root lcf-inline-wrap", "data-lowco-form": form.id });
    applyAccent(root, form);
    const titleId = `lcf${++instanceSeq}-title`;
    const card = h("div", { class: "lcf-card lcf-inline", role: "region", "aria-labelledby": titleId });
    card.appendChild(this.buildForm(form, titleId, "inline", null));
    root.appendChild(card);
    el.replaceChildren(root);
    this.markShown(form);
  }

  private mountOverlay(form: EngageForm, mode: FormMode): Mounted {
    const seq = ++instanceSeq;
    const titleId = `lcf${seq}-title`;
    const root = h("div", { class: "lcf-root", "data-lowco-form": form.id });
    applyAccent(root, form);
    const previous = document.activeElement as HTMLElement | null;
    const label = form.content.title ? undefined : form.name || "Form";
    let card: HTMLElement;
    if (mode === "popup") {
      root.classList.add("lcf-overlay");
      card = h("div", {
        class: "lcf-card lcf-popup",
        role: "dialog",
        "aria-modal": "true",
        "aria-labelledby": label ? undefined : titleId,
        "aria-label": label,
        tabindex: "-1",
      });
      const backdrop = h("div", { class: "lcf-backdrop", "aria-hidden": "true" });
      backdrop.addEventListener("click", () => close(true));
      root.appendChild(backdrop);
    } else {
      card = h("div", {
        class: mode === "bar" ? "lcf-card lcf-bar" : "lcf-card lcf-slide",
        role: mode === "bar" ? "region" : "dialog",
        "aria-modal": mode === "bar" ? undefined : "false",
        "aria-labelledby": label ? undefined : titleId,
        "aria-label": label,
      });
    }
    const closeButton = h("button", { type: "button", class: "lcf-close", "aria-label": "Close", text: "×" });
    closeButton.addEventListener("click", () => close(true));
    card.appendChild(closeButton);
    let submitted = false;
    card.appendChild(
      this.buildForm(form, titleId, mode, () => {
        submitted = true;
      }),
    );
    root.appendChild(card);

    const htmlStyle = document.documentElement.style;
    const previousOverflow = htmlStyle.overflow;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (mode === "popup" || card.contains(document.activeElement)) {
          e.preventDefault();
          close(true);
        }
        return;
      }
      if (e.key !== "Tab" || mode !== "popup") return;
      const focusables = focusableIn(card);
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (!first || !last) {
        e.preventDefault();
        card.focus();
        return;
      }
      const active = document.activeElement;
      if (!card.contains(active)) {
        e.preventDefault();
        first.focus();
      } else if (e.shiftKey && (active === first || active === card)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKey, true);

    let closed = false;
    const close = (byUser: boolean) => {
      if (closed) return;
      closed = true;
      document.removeEventListener("keydown", onKey, true);
      root.remove();
      this.open.delete(form.id);
      if (mode === "popup") {
        htmlStyle.overflow = previousOverflow;
        if (previous && typeof previous.focus === "function" && document.contains(previous)) previous.focus();
      }
      if (byUser && !submitted) this.remember(form.id, { closedAt: Date.now() });
    };

    document.body.appendChild(root);
    if (mode === "popup") {
      htmlStyle.overflow = "hidden";
      const firstField = card.querySelector<HTMLElement>(".lcf-form " + FOCUSABLE.split(", ").join(", .lcf-form "));
      (firstField ?? card).focus();
    }
    return { mode, root, close };
  }

  /** The form itself (title, fields, submit) and its submit handling. */
  private buildForm(
    form: EngageForm,
    titleId: string,
    mode: FormMode,
    onSubmitted: (() => void) | null,
  ): HTMLElement {
    const c = form.content;
    const prefix = titleId.replace(/-title$/, "");
    const wrap = h("div", { class: "lcf-content" });
    const image = safeUrl(c.imageUrl, true);
    if (image) wrap.appendChild(h("img", { class: "lcf-image", src: image, alt: "" }));
    wrap.appendChild(h("h2", { class: "lcf-title", id: titleId, text: c.title || form.name }));
    if (c.body) wrap.appendChild(h("p", { class: "lcf-body", text: c.body }));
    if (form.referralReward) wrap.appendChild(h("p", { class: "lcf-reward", text: form.referralReward }));

    const formEl = h("form", { class: "lcf-form", novalidate: true, "aria-labelledby": titleId });
    const inputs = new Map<string, { field: FormField; control: HTMLElement; error: HTMLElement }>();
    for (const field of form.fields) {
      if (field.type === "hidden") continue;
      const built = buildField(field, `${prefix}-${field.key}`, mode);
      formEl.appendChild(built.node);
      inputs.set(field.key, { field, control: built.control, error: built.error });
    }
    const honeypot = h("input", { type: "text", name: HONEYPOT_FIELD, tabindex: "-1", autocomplete: "off" });
    formEl.appendChild(h("div", { class: "lcf-hp", "aria-hidden": "true" }, [h("label", {}, ["Leave this empty ", honeypot])]));
    const submit = h("button", { type: "submit", class: "lcf-submit", text: c.submitLabel || "Send" });
    formEl.appendChild(submit);
    const status = h("p", { class: "lcf-status", role: "status", "aria-live": "polite" });
    formEl.appendChild(status);
    if (c.privacyText) formEl.appendChild(h("p", { class: "lcf-privacy", text: c.privacyText }));
    wrap.appendChild(formEl);

    let submissionId = uuid();
    let busy = false;

    const clearErrors = () => {
      status.textContent = "";
      inputs.forEach(({ control, error }) => {
        error.textContent = "";
        control.removeAttribute("aria-invalid");
      });
    };
    const showErrors = (errors: FormFieldError[], fromServer: boolean) => {
      const general: string[] = [];
      let first: HTMLElement | null = null;
      for (const err of errors) {
        const entry = inputs.get(err.field);
        if (!entry) {
          general.push(err.message);
          continue;
        }
        entry.error.textContent = fromServer ? `${entry.field.label} ${err.message}` : err.message;
        entry.control.setAttribute("aria-invalid", "true");
        first = first ?? entry.control;
      }
      if (general.length > 0) status.textContent = general.join(" ");
      const focusTarget: HTMLElement | null = first;
      if (focusTarget) (focusTarget.matches("fieldset") ? focusTarget.querySelector<HTMLElement>("input") : focusTarget)?.focus();
    };

    formEl.addEventListener("submit", (e) => {
      e.preventDefault();
      if (busy) return;
      clearErrors();
      const { answers, errors } = collectAnswers(form, inputs);
      if (errors.length > 0) {
        showErrors(errors, false);
        return;
      }
      answers[HONEYPOT_FIELD] = honeypot.value;
      busy = true;
      submit.disabled = true;
      submit.setAttribute("aria-busy", "true");
      const userId = this.host.userId();
      const anonymousId = this.host.anonymousId();
      const payload = {
        answers,
        ...(userId ? { userId } : {}),
        ...(anonymousId ? { anonymousId } : {}),
        submissionId,
        pageUrl: window.location.href,
      };
      void (async () => {
        try {
          const res = await fetch(`${this.host.baseUrl()}${FORMS_PATH}/${encodeURIComponent(form.id)}/submit`, {
            method: "POST",
            headers: this.host.headers(),
            body: JSON.stringify(payload),
          });
          const body = await res.json().catch(() => null);
          if (res.status === 422) {
            const errs: FormFieldError[] = Array.isArray(body?.data?.errors) ? body.data.errors : [];
            showErrors(errs.length > 0 ? errs : [{ field: "", message: "Some answers need fixing." }], true);
            return;
          }
          if (res.status === 429) {
            status.textContent = "Too many answers. Please try again in a minute.";
            return;
          }
          if (!res.ok) {
            status.textContent = "Something went wrong. Please try again.";
            return;
          }
          const result: FormSubmitResult = body?.data && typeof body.data === "object" ? body.data : { ok: true };
          submissionId = uuid();
          this.remember(form.id, { submittedAt: Date.now() });
          onSubmitted?.();
          const redirect = safeUrl(result.redirectUrl || form.redirectUrl);
          if (redirect) {
            this.navigate(redirect);
            return;
          }
          let message = result.message || c.successBody || "";
          if (!message && result.confirmation === "sent") message = "Check your inbox to confirm.";
          const success = h("div", { class: "lcf-success", role: "status", tabindex: "-1" }, [
            h("h2", { class: "lcf-title", id: titleId, text: result.title || c.successTitle || "Thank you" }),
            message ? h("p", { class: "lcf-body", text: message }) : null,
          ]);
          wrap.replaceChildren(success);
          success.focus();
        } catch {
          status.textContent = "Something went wrong. Please try again.";
        } finally {
          busy = false;
          submit.disabled = false;
          submit.removeAttribute("aria-busy");
        }
      })();
    });
    return wrap;
  }
}

function applyAccent(root: HTMLElement, form: EngageForm): void {
  const accent = safeColor(form.content.accent);
  if (accent) root.style.setProperty("--lcf-accent", accent);
}

function inlineTargets(id: string): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>("[data-engage-form]")).filter(
    (el) => el.getAttribute("data-engage-form") === id,
  );
}

function focusableIn(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter((el) => !el.closest(".lcf-hp"));
}

function scrolledPercent(): number {
  const doc = document.documentElement;
  const max = Math.max(doc.scrollHeight, document.body?.scrollHeight ?? 0) - window.innerHeight;
  if (max <= 0) return 100;
  return ((window.scrollY || doc.scrollTop || 0) / max) * 100;
}

const AUTOCOMPLETE: Record<string, string> = {
  name: "name",
  full_name: "name",
  first_name: "given-name",
  last_name: "family-name",
  company: "organization",
};

function buildField(
  field: FormField,
  id: string,
  mode: FormMode,
): { node: HTMLElement; control: HTMLElement; error: HTMLElement } {
  const errorId = `${id}-error`;
  const error = h("p", { class: "lcf-error", id: errorId });
  const required = !!field.required;
  const marker = required ? h("span", { class: "lcf-req", "aria-hidden": "true", text: "*" }) : null;

  if (field.type === "checkbox") {
    const input = h("input", {
      type: "checkbox",
      id,
      name: field.key,
      "aria-required": required ? "true" : undefined,
      "aria-describedby": errorId,
    });
    const label = h("label", { class: "lcf-check", for: id }, [input, h("span", { text: field.label }), marker]);
    return { node: h("div", { class: "lcf-field" }, [label, error]), control: input, error };
  }

  if (field.type === "rating" || field.type === "nps") {
    const [lo, hi] = field.type === "nps" ? [0, 10] : [1, 5];
    const legendId = `${id}-legend`;
    const scale = h("div", { class: "lcf-scale" });
    for (let n = lo; n <= hi; n++) {
      const input = h("input", {
        type: "radio",
        name: field.key,
        value: String(n),
        "aria-label": field.type === "rating" ? `${n} of 5` : String(n),
      });
      scale.appendChild(h("label", {}, [input, h("span", { "aria-hidden": "true", text: String(n) })]));
    }
    const fieldset = h(
      "fieldset",
      {
        class: "lcf-field",
        role: "radiogroup",
        "aria-labelledby": legendId,
        "aria-required": required ? "true" : undefined,
        "aria-describedby": errorId,
      },
      [
        h("legend", { class: "lcf-label", id: legendId }, [field.label, marker]),
        scale,
        field.type === "nps"
          ? h("div", { class: "lcf-hints", "aria-hidden": "true" }, [
              h("span", { text: "Not likely" }),
              h("span", { text: "Very likely" }),
            ])
          : null,
        error,
      ],
    );
    return { node: fieldset, control: fieldset, error };
  }

  let control: HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
  const common: Attrs = {
    id,
    name: field.key,
    class: "lcf-input",
    "aria-required": required ? "true" : undefined,
    "aria-describedby": errorId,
  };
  if (field.type === "textarea") {
    control = h("textarea", { ...common, placeholder: field.placeholder, rows: mode === "bar" ? 1 : 4 });
  } else if (field.type === "select") {
    control = h("select", common, [
      h("option", { value: "", text: field.placeholder || "Choose…" }),
      ...(field.options ?? []).map((o) => h("option", { value: o, text: o })),
    ]);
  } else {
    const type = field.type === "email" ? "email" : field.type === "phone" ? "tel" : "text";
    control = h("input", {
      ...common,
      type,
      placeholder: field.placeholder,
      inputmode: field.type === "email" ? "email" : field.type === "phone" ? "tel" : undefined,
      autocomplete:
        field.type === "email" ? "email" : field.type === "phone" ? "tel" : (AUTOCOMPLETE[field.key] ?? undefined),
    });
  }
  const label = h("label", { class: "lcf-label", for: id }, [field.label, marker]);
  return { node: h("div", { class: "lcf-field" }, [label, control, error]), control, error };
}

/** Reads and checks the answers: required, email and phone, like the server. */
function collectAnswers(
  form: EngageForm,
  inputs: Map<string, { field: FormField; control: HTMLElement; error: HTMLElement }>,
): { answers: Record<string, unknown>; errors: FormFieldError[] } {
  const answers: Record<string, unknown> = {};
  const errors: FormFieldError[] = [];
  const query = new URLSearchParams(window.location.search);
  for (const field of form.fields) {
    if (field.type === "hidden") {
      // A hidden field takes the page's query parameter of the same name
      // (e.g. utm_campaign); a value set on the form wins on the server.
      const value = query.get(field.key);
      if (value) answers[field.key] = value;
      continue;
    }
    const entry = inputs.get(field.key);
    if (!entry) continue;
    const { control } = entry;
    if (field.type === "checkbox") {
      const checked = (control as HTMLInputElement).checked;
      if (field.required && !checked) errors.push({ field: field.key, message: "Please tick this box to continue." });
      answers[field.key] = checked;
      continue;
    }
    if (field.type === "rating" || field.type === "nps") {
      const picked = control.querySelector<HTMLInputElement>("input:checked");
      if (picked) answers[field.key] = Number(picked.value);
      else if (field.required) errors.push({ field: field.key, message: "Please choose a score." });
      continue;
    }
    const value = (control as HTMLInputElement).value.trim();
    if (!value) {
      if (field.required) errors.push({ field: field.key, message: "This field is required." });
      continue;
    }
    if (field.type === "email" && !isEmail(value)) {
      errors.push({ field: field.key, message: "Enter a valid email address." });
      continue;
    }
    if (field.type === "phone" && !isPhone(value)) {
      errors.push({ field: field.key, message: "Enter a valid phone number." });
      continue;
    }
    answers[field.key] = value;
  }
  return { answers, errors };
}
