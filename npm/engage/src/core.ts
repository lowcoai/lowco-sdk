import {
  generateId,
  HEADER_API_KEY,
  HEADER_ENGAGE_APP_ID,
  HEADER_ORG_ID,
  isApiKey,
  resetId,
} from "./utils";
import {
  BatchEventInput,
  BatchResult,
  BatchRow,
  Config,
  DeviceInfo,
  Event,
  LocationInfo,
  Metadata,
} from "./types";
import { EngageForm, EngageForms } from "./forms";
import {
  ClickIdKey,
  collectAdIds,
  createEventId,
  fbcFromFbclid,
  gaClientIdFromCookie,
  gaSessionId,
  mergeSessionClickIds,
  mirrorEventId,
  parseCookies,
  readClickIds,
} from "./adids";
import UAParser from "ua-parser-js";

const BASE_URL = "https://api.lowco.ai";

/** The most events one POST /v1/engage/track/batch takes. */
export const MAX_BATCH = 1000;

class LowcoAnalytics {
  private static instance: LowcoAnalytics;
  private config: Config | null = null;
  private userId: string | null = null;
  private anonymousId: string | null = null;
  private deviceInfo: DeviceInfo | null = null;
  private locationInfo: LocationInfo | null = null;
  private sessionId: string | null = null;
  private lastEventTime: number | null = null;
  private sessionStart: number | null = null;
  private sessionAds: SessionAds | null = null;
  private forms: EngageForms | null = null;
  private routeHooksInstalled = false;
  private readonly SESSION_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes
  private readonly SESSION_ID_STORAGE_KEY = "lowco_session_id";
  private readonly LAST_EVENT_STORAGE_KEY = "lowco_session_last_event";
  private readonly SESSION_START_STORAGE_KEY = "lowco_session_start";
  private readonly SESSION_ADS_STORAGE_KEY = "lowco_session_ads";
  private readonly FIRST_TOUCH_STORAGE_KEY = "lowco_first_touch";
  private readonly ATTRIBUTION_KEYS = [
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "utm_id",
    "gclid",
    "gbraid",
    "wbraid",
    "fbclid",
    "li_fat_id",
    "ttclid",
    "msclkid",
  ];

  private constructor() {
    this.anonymousId = generateId();
  }

  public static getInstance(): LowcoAnalytics {
    if (!LowcoAnalytics.instance) {
      LowcoAnalytics.instance = new LowcoAnalytics();
    }
    return LowcoAnalytics.instance;
  }

  public init(config: Config) {
    this.config = { ...config };
    // The credential stays out of the log.
    console.log("Analytics initialized with config:", {
      orgId: config.orgId,
      appId: config.appId,
      autoTrack: config.autoTrack,
      forms: config.forms,
      mirrorEventIds: config.mirrorEventIds,
    });
    this.initializeSession();
    if (config.autoTrack && this.canUseBrowserApis()) {
      this.trackPageView();
      this.setLocationInfo();
    }
    if ((config.autoTrack || config.forms) && this.canUseBrowserApis()) {
      this.installRouteHooks();
    }
    if (this.canUseBrowserApis()) {
      this.setDeviceInfo();
    }
    if (config.forms && this.canUseBrowserApis()) {
      const forms = this.ensureForms();
      forms.setAutoShow(true);
      void forms.start();
    } else {
      this.forms?.setAutoShow(false);
    }
  }

  /**
   * An `lc_` API key travels as `X-Api-Key`, any other token as
   * `Authorization: Bearer`. `X-Engage-App-Id` is sent only when `appId` is
   * set; without it the service uses the org's default app.
   */
  private buildHeaders(config: Config): Record<string, string> {
    const apiKey = config.apiKey.trim();
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      [HEADER_ORG_ID]: config.orgId,
    };
    if (isApiKey(apiKey)) {
      headers[HEADER_API_KEY] = apiKey;
    } else {
      headers.Authorization = `Bearer ${apiKey}`;
    }
    const appId = config.appId?.trim();
    if (appId) {
      headers[HEADER_ENGAGE_APP_ID] = appId;
    }
    return headers;
  }

  private canUseBrowserApis(): boolean {
    return (
      typeof window !== "undefined" &&
      typeof document !== "undefined" &&
      typeof history !== "undefined"
    );
  }

  private setDeviceInfo(): void {
    const parser = new UAParser();
    const result = parser.getResult();
    this.deviceInfo = {
      browser: result.browser,
      os: result.os,
      device: result.device,
      cpu: result.cpu,
      engine: result.engine,
      ua: result.ua,
    };
  }
  private setLocationInfo(): void {
    if ("geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const {
            latitude,
            longitude,
            accuracy,
            altitude,
            altitudeAccuracy,
            heading,
            speed,
          } = position.coords;
          this.locationInfo = {
            latitude,
            longitude,
            accuracy,
            altitude,
            altitude_accuracy: altitudeAccuracy,
            heading,
            speed,
          };
        },
        (error: GeolocationPositionError) => {
          // Code 1 = permission denied — expected when the user blocks location; not an app error.
          if (error.code !== 1) {
            console.error("Error getting location:", error);
          }
        },
      );
    } else {
      console.log("Geolocation is not supported by this browser.");
    }
  }

  private initializeSession(): void {
    if (!this.canUseStorage()) {
      this.startNewSession();
      return;
    }

    const storedSessionId = localStorage.getItem(this.SESSION_ID_STORAGE_KEY);
    const storedLastEvent = localStorage.getItem(this.LAST_EVENT_STORAGE_KEY);
    const storedStart = Number(localStorage.getItem(this.SESSION_START_STORAGE_KEY));
    const now = Date.now();

    if (storedSessionId && storedLastEvent) {
      const lastEventTimestamp = Number(storedLastEvent);
      if (!Number.isNaN(lastEventTimestamp)) {
        const isExpired = now - lastEventTimestamp > this.SESSION_TIMEOUT_MS;
        if (!isExpired) {
          this.sessionId = storedSessionId;
          this.lastEventTime = lastEventTimestamp;
          this.sessionStart = Number.isFinite(storedStart) && storedStart > 0 ? storedStart : lastEventTimestamp;
          return;
        }
      }
    }

    this.startNewSession(now);
  }

  /**
   * A new session id, GA4-compatible: `<client id>.<start epoch seconds>`,
   * the client id being GA4's (`_ga` cookie) when the page runs gtag, else
   * this browser's anonymous id.
   */
  private startNewSession(timestamp: number = Date.now()): void {
    this.sessionStart = timestamp;
    this.sessionId = gaSessionId(this.clientId(), timestamp);
    this.lastEventTime = timestamp;
    this.sessionAds = null;
    this.persistSession();
  }

  private clientId(): string {
    const ga = gaClientIdFromCookie(parseCookies(this.readCookie())._ga);
    return ga ?? this.anonymousId ?? this.createSessionId();
  }

  private readCookie(): string {
    try {
      return typeof document !== "undefined" ? (document.cookie ?? "") : "";
    } catch {
      return "";
    }
  }

  private ensureActiveSession(eventTime: Date): void {
    const eventTimestamp = eventTime.getTime();

    if (!this.sessionId || !this.lastEventTime) {
      this.startNewSession(eventTimestamp);
      return;
    }

    const inactiveDuration = eventTimestamp - this.lastEventTime;
    if (inactiveDuration > this.SESSION_TIMEOUT_MS) {
      this.startNewSession(eventTimestamp);
      return;
    }

    this.lastEventTime = eventTimestamp;
    this.persistSession();
  }

  private persistSession(): void {
    if (!this.canUseStorage() || !this.sessionId || !this.lastEventTime) {
      return;
    }

    try {
      localStorage.setItem(this.SESSION_ID_STORAGE_KEY, this.sessionId);
      localStorage.setItem(
        this.LAST_EVENT_STORAGE_KEY,
        this.lastEventTime.toString(),
      );
      if (this.sessionStart) {
        localStorage.setItem(this.SESSION_START_STORAGE_KEY, this.sessionStart.toString());
      }
    } catch (error) {
      console.error("Failed to persist session data:", error);
    }
  }

  private canUseStorage(): boolean {
    return (
      typeof window !== "undefined" &&
      typeof window.localStorage !== "undefined"
    );
  }

  private createSessionId(): string {
    if (typeof crypto !== "undefined" && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    return (
      Date.now().toString(36) + Math.random().toString(36).substring(2, 15)
    );
  }

  /**
   * SPA navigation: `popstate` and the patched `pushState`/`replaceState`
   * track a page view (autoTrack) and let forms re-apply their page rules.
   * Installed once, however often init() runs.
   */
  private installRouteHooks(): void {
    if (this.routeHooksInstalled) return;
    this.routeHooksInstalled = true;
    window.addEventListener("popstate", this.handleRouteChange);
    this.overrideHistoryMethods();
  }

  private handleRouteChange = (): void => {
    if (this.config?.autoTrack) {
      this.trackPageView();
    }
    this.forms?.onRouteChange();
  };

  private overrideHistoryMethods(): void {
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;
    const instance = this;

    history.pushState = function (state, title, url) {
      originalPushState.apply(this, [state, title, url]);
      instance.handleRouteChange();
    };

    history.replaceState = function (state, title, url) {
      originalReplaceState.apply(this, [state, title, url]);
      instance.handleRouteChange();
    };
  }

  private trackPageView = (): void => {
    this.page({
      path: window.location.pathname,
      referrer: document.referrer,
      title: document.title,
      url: window.location.href,
      search: window.location.search,
    });
  };

  private buildAttributionContext(): Metadata {
    const search =
      typeof window !== "undefined" ? (window.location?.search ?? "") : "";
    const attribution = this.getAttributionParams(search);
    const firstTouch = this.resolveFirstTouch(attribution);

    return {
      ...attribution,
      ...(firstTouch ? { first_touch: firstTouch } : {}),
    };
  }

  /**
   * The ad identifiers for this event: the session's click ids (the first
   * value of each seen this session is kept), `click_id`/`click_id_kind`,
   * Meta's `_fbp`/`_fbc` cookies (`fbc` derived from fbclid when the cookie
   * is absent), GA4's client id, the referrer and the page URL.
   */
  private buildAdContext(nowMs: number = Date.now()): Metadata {
    const search =
      typeof window !== "undefined" ? (window.location?.search ?? "") : "";
    const ads = this.loadSessionAds();
    ads.click_ids = mergeSessionClickIds(ads.click_ids, readClickIds(search));
    const cookie = this.readCookie();
    if (ads.click_ids.fbclid && !ads.fbc && !parseCookies(cookie)._fbc) {
      ads.fbc = fbcFromFbclid(ads.click_ids.fbclid, nowMs);
    }
    this.saveSessionAds(ads);
    return collectAdIds({
      clickIds: ads.click_ids,
      cookie,
      derivedFbc: ads.fbc,
      referrer: typeof document !== "undefined" ? document.referrer || undefined : undefined,
      url: typeof window !== "undefined" ? window.location?.href || undefined : undefined,
    });
  }

  private loadSessionAds(): SessionAds {
    const sid = this.sessionId ?? "";
    if (this.sessionAds && this.sessionAds.session_id === sid) {
      return this.sessionAds;
    }
    let ads: SessionAds = { session_id: sid, click_ids: {} };
    if (this.canUseStorage()) {
      try {
        const raw = localStorage.getItem(this.SESSION_ADS_STORAGE_KEY);
        const parsed = raw ? JSON.parse(raw) : null;
        if (parsed && typeof parsed === "object" && parsed.session_id === sid) {
          ads = {
            session_id: sid,
            click_ids: parsed.click_ids && typeof parsed.click_ids === "object" ? parsed.click_ids : {},
            ...(typeof parsed.fbc === "string" ? { fbc: parsed.fbc } : {}),
          };
        }
      } catch {
        // unreadable: start the session's ad ids afresh
      }
    }
    this.sessionAds = ads;
    return ads;
  }

  private saveSessionAds(ads: SessionAds): void {
    this.sessionAds = ads;
    if (!this.canUseStorage()) return;
    try {
      localStorage.setItem(this.SESSION_ADS_STORAGE_KEY, JSON.stringify(ads));
    } catch {
      // storage blocked: the ids live for this page only
    }
  }

  private getAttributionParams(search: string): Metadata {
    if (!search) {
      return {};
    }

    try {
      const params = new URLSearchParams(search);
      const attribution: Metadata = {};
      this.ATTRIBUTION_KEYS.forEach((key) => {
        const value = params.get(key);
        if (value) {
          attribution[key] = value;
        }
      });
      return attribution;
    } catch (error) {
      console.error("Failed to parse attribution parameters:", error);
      return {};
    }
  }

  private resolveFirstTouch(current: Metadata): Metadata | null {
    const stored = this.readFirstTouch();
    if (stored) {
      return stored;
    }

    if (Object.keys(current).length === 0) {
      return null;
    }

    const firstTouch: Metadata = {
      ...current,
      landing_url:
        typeof window !== "undefined" ? window.location.href : undefined,
      referrer: typeof document !== "undefined" ? document.referrer : undefined,
      captured_at: new Date().toISOString(),
    };

    this.writeFirstTouch(firstTouch);
    return firstTouch;
  }

  private readFirstTouch(): Metadata | null {
    if (!this.canUseStorage()) {
      return null;
    }

    try {
      const raw = localStorage.getItem(this.FIRST_TOUCH_STORAGE_KEY);
      if (!raw) {
        return null;
      }
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" ? (parsed as Metadata) : null;
    } catch (error) {
      console.error("Failed to read first-touch attribution:", error);
      return null;
    }
  }

  private writeFirstTouch(firstTouch: Metadata): void {
    if (!this.canUseStorage()) {
      return;
    }

    try {
      localStorage.setItem(
        this.FIRST_TOUCH_STORAGE_KEY,
        JSON.stringify(firstTouch),
      );
    } catch (error) {
      console.error("Failed to persist first-touch attribution:", error);
    }
  }

  /** Tracks a `page_view`; returns its `event_id` (undefined before init). */
  public page(properties: Metadata = {}): string | undefined {
    return this.track("page_view", properties);
  }

  /**
   * Tracks an event and returns its `event_id` (a UUID; pass your own as
   * `event_id` in the metadata to keep it), so the same id can be given to
   * other tags. Undefined before init().
   */
  public track(eventName: string, eventMetadata: Metadata = {}): string | undefined {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return undefined;
    }

    if (!this.sessionId) {
      this.initializeSession();
    }

    const eventTime = new Date();
    this.ensureActiveSession(eventTime);

    const eventData: Metadata = {
      ...this.buildAttributionContext(),
      ...this.buildAdContext(eventTime.getTime()),
      event_id: createEventId(),
      ...eventMetadata,
    };
    const eventId = String(eventData.event_id);
    const event = {
      id: eventId,
      event_name: eventName,
      event_data: eventData,
      user_id: this.userId,
      device_id: this.anonymousId,
      session_id: this.sessionId ?? undefined,
      device_info: this.deviceInfo,
      location: this.locationInfo,
      event_time: eventTime,
    } as Event;

    this.sendEvent(event);
    if (this.config.mirrorEventIds && typeof window !== "undefined") {
      mirrorEventId(window as unknown as { fbq?: unknown; gtag?: unknown }, eventName, eventId, eventMetadata);
    }
    this.forms?.onEvent(eventName);
    return eventId;
  }

  public identifyUser(userId: string, properties: Metadata = {}) {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return;
    }
    this.userId = userId;
    const eventTime = new Date();
    if (!this.sessionId) {
      this.initializeSession();
    }
    this.ensureActiveSession(eventTime);

    // The click ids, fbp/fbc and GA client id ride on the identify too, so
    // they land on the profile.
    const eventData: Metadata = {
      ...this.buildAttributionContext(),
      ...this.buildAdContext(eventTime.getTime()),
      event_id: createEventId(),
      ...properties,
    };
    this.sendEvent({
      id: String(eventData.event_id),
      event_name: "_lowco_identify",
      event_data: eventData,
      user_id: userId,
      device_id: this.anonymousId,
      session_id: this.sessionId ?? undefined,
      device_info: this.deviceInfo,
      location: this.locationInfo,
      event_time: eventTime,
    } as Event);
    this.forms?.onIdentityChange();
  }

  /**
   * Logout: forgets the identified user and starts a new anonymous id
   * (`lowco_uuid`) and session, so the next person on this browser isn't
   * tied to the last one. First-touch attribution is kept.
   */
  public reset(): void {
    this.userId = null;
    this.anonymousId = resetId();
    this.startNewSession();
    this.forms?.onIdentityChange();
  }

  /**
   * Shows a live form now, whatever its trigger, pages, audience or
   * frequency (an inline form fills its `[data-engage-form]` elements, or
   * opens as a popup when the page has none). Works without
   * `init({ forms: true })`. Resolves false when the form isn't live.
   */
  public showForm(id: string): Promise<boolean> {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return Promise.resolve(false);
    }
    if (!this.canUseBrowserApis()) return Promise.resolve(false);
    return this.ensureForms().show(id);
  }

  /**
   * Closes every form popup, slide-in and bar the SDK shows and holds back
   * pending triggers until the next page (or refreshForms). Inline forms stay.
   */
  public hideForms(): void {
    this.forms?.hideAll();
  }

  /** Re-fetches the live forms (skipping the 60 s cache) and re-applies their rules. */
  public refreshForms(): Promise<EngageForm[]> {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return Promise.resolve([]);
    }
    if (!this.canUseBrowserApis()) return Promise.resolve([]);
    return this.ensureForms().refresh();
  }

  private ensureForms(): EngageForms {
    if (!this.forms) {
      this.forms = new EngageForms(
        {
          baseUrl: () => BASE_URL,
          headers: () => (this.config ? this.buildHeaders(this.config) : {}),
          userId: () => this.userId,
          anonymousId: () => this.anonymousId,
          sessionId: () => this.sessionId,
        },
        false,
      );
    }
    return this.forms;
  }

  /**
   * Sends events through POST /v1/engage/track/batch, 1000 a request, and
   * answers each event's outcome by its place in `events` (one bad event
   * doesn't stop the rest). Missing fields are filled like track() fills
   * them: the identified user, this browser's device id, session, device
   * info and location, and now. Rejects when a request fails; batches sent
   * before it were taken.
   */
  public async trackBatch(events: BatchEventInput[]): Promise<BatchResult> {
    const config = this.config;
    if (!config) {
      throw new Error("Analytics not initialized. Call init() first.");
    }
    const out: BatchResult = { accepted: 0, rejected: 0, results: [] };
    const wire = events.map((e) => {
      const eventData: Metadata = { event_id: createEventId(), ...(e.event_data ?? {}) };
      return {
      id: String(eventData.event_id),
      event_name: e.event_name,
      event_data: eventData,
      user_id: e.user_id === undefined ? this.userId : e.user_id,
      device_id: e.device_id ?? this.anonymousId,
      session_id: e.session_id ?? this.sessionId ?? undefined,
      device_info: e.device_info === undefined ? this.deviceInfo : e.device_info,
      location: e.location === undefined ? this.locationInfo : e.location,
      event_time: e.event_time ?? new Date(),
      };
    });
    for (let start = 0; start < wire.length; start += MAX_BATCH) {
      const res = await fetch(`${BASE_URL}/v1/engage/track/batch`, {
        method: "POST",
        headers: this.buildHeaders(config),
        body: JSON.stringify({ events: wire.slice(start, start + MAX_BATCH) }),
      });
      const body = await res.json().catch(() => null);
      if (!res.ok) {
        const message = body?.error?.details || body?.error?.message || body?.message || `status ${res.status}`;
        throw Object.assign(new Error(`track/batch failed: ${message}`), { status: res.status, body });
      }
      const data = body?.data ?? {};
      out.accepted += Number(data.accepted) || 0;
      out.rejected += Number(data.rejected) || 0;
      const rows: BatchRow[] = Array.isArray(data.results) ? data.results : [];
      for (const row of rows) out.results.push({ ...row, index: row.index + start });
    }
    return out;
  }
  private sendEvent(event: Event): void {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return;
    }
    // extract device info and location info
    fetch(`${BASE_URL}/v1/engage/track`, {
      method: "POST",
      body: JSON.stringify(event),
      headers: this.buildHeaders(this.config),
    });
  }
}

/** The session's ad click ids, kept in `lowco_session_ads`. */
interface SessionAds {
  session_id: string;
  click_ids: Partial<Record<ClickIdKey, string>>;
  /** `fbc` derived from fbclid when Meta's `_fbc` cookie is absent. */
  fbc?: string;
}

export default LowcoAnalytics.getInstance();
