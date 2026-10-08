import { generateId } from "./utils";
import { Config, DeviceInfo, Event, LocationInfo, Metadata } from "./types";
import UAParser from "ua-parser-js";

const BASE_URL = "https://api.lowco.ai";

class LowcoAnalytics {
  private static instance: LowcoAnalytics;
  private config: Config | null = null;
  private userId: string | null = null;
  private anonymousId: string | null = null;
  private deviceInfo: DeviceInfo | null = null;
  private locationInfo: LocationInfo | null = null;
  private sessionId: string | null = null;
  private lastEventTime: number | null = null;
  private readonly SESSION_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes
  private readonly SESSION_ID_STORAGE_KEY = "lowco_session_id";
  private readonly LAST_EVENT_STORAGE_KEY = "lowco_session_last_event";
  private readonly FIRST_TOUCH_STORAGE_KEY = "lowco_first_touch";
  private readonly ATTRIBUTION_KEYS = [
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "utm_id",
    "gclid",
    "fbclid",
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
    console.log("Analytics initialized with config:", config);
    this.initializeSession();
    if (config.autoTrack && this.canUseBrowserApis()) {
      this.trackPageView();
      window.addEventListener("popstate", this.trackPageView);
      this.overrideHistoryMethods();
      this.setLocationInfo();
    }
    if (this.canUseBrowserApis()) {
      this.setDeviceInfo();
    }
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
    const now = Date.now();

    if (storedSessionId && storedLastEvent) {
      const lastEventTimestamp = Number(storedLastEvent);
      if (!Number.isNaN(lastEventTimestamp)) {
        const isExpired = now - lastEventTimestamp > this.SESSION_TIMEOUT_MS;
        if (!isExpired) {
          this.sessionId = storedSessionId;
          this.lastEventTime = lastEventTimestamp;
          return;
        }
      }
    }

    this.startNewSession(now);
  }

  private startNewSession(timestamp: number = Date.now()): void {
    this.sessionId = this.createSessionId();
    this.lastEventTime = timestamp;
    this.persistSession();
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

  private overrideHistoryMethods(): void {
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;
    const instance = this;

    history.pushState = function (state, title, url) {
      originalPushState.apply(this, [state, title, url]);
      instance.trackPageView();
    };

    history.replaceState = function (state, title, url) {
      originalReplaceState.apply(this, [state, title, url]);
      instance.trackPageView();
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

  public page(properties: Metadata = {}) {
    this.track("page_view", properties);
  }

  public track(eventName: string, eventMetadata: Metadata = {}) {
    if (!this.config) {
      console.error("Analytics not initialized. Call init() first.");
      return;
    }

    if (!this.sessionId) {
      this.initializeSession();
    }

    const eventTime = new Date();
    this.ensureActiveSession(eventTime);

    const event = {
      id: "",
      event_name: eventName,
      event_data: {
        ...this.buildAttributionContext(),
        ...eventMetadata,
      },
      user_id: this.userId,
      device_id: this.anonymousId,
      session_id: this.sessionId ?? undefined,
      device_info: this.deviceInfo,
      location: this.locationInfo,
      event_time: eventTime,
    } as Event;

    this.sendEvent(event);
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

    this.sendEvent({
      id: "",
      event_name: "_lowco_identify",
      event_data: {
        ...this.buildAttributionContext(),
        ...properties,
      },
      user_id: userId,
      device_id: this.anonymousId,
      session_id: this.sessionId ?? undefined,
      device_info: this.deviceInfo,
      location: this.locationInfo,
      event_time: eventTime,
    } as Event);
    // Here you would typically send the user properties to your analytics backend
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
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.config.apiKey}`,
        "X-Org-Id": this.config.orgId,
      },
    });
  }
}

export default LowcoAnalytics.getInstance();
