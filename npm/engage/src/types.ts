export interface Config {
  /**
   * Sent as `Authorization: Bearer <apiKey>`.
   *
   * Use the app's write key (`ewk_…`, engage → Settings → Apps): it selects
   * the org and the app on its own, so `orgId` and `appId` are not needed. A
   * write key is public (it ships inside your app) and only authorizes event
   * tracking.
   *
   * Any other key (a user JWT or platform API key) needs `orgId`.
   */
  apiKey: string;
  /**
   * Sent as `X-Org-Id`. Required unless `apiKey` is an app write key
   * (`ewk_…`), which already identifies the org.
   */
  orgId?: string;
  /**
   * Engage app to track into, sent as `X-Engage-App-Id` when `apiKey` is not a
   * write key. Without it, events go to the org's default app. Ignored with a
   * write key, which already identifies the app.
   */
  appId?: string;
  autoTrack?: boolean;
}

export interface Metadata {
  [key: string]: any;
}
export interface Event {
  event_time: Date;
  event_name: string;
  event_data?: Metadata;
  user_id?: string;
  device_id: string;
  session_id?: string;
  device_info?: DeviceInfo;
  location?: LocationInfo;
  id?: string;
}
export interface Identify {
  user_id: string;
  user_data: Metadata;
}

export interface DeviceInfo {
  browser?: {
    name?: string;
    version?: string;
    major?: string;
  };
  os?: {
    name?: string;
    version?: string;
  };
  device?: {
    model?: string;
    type?: string;
    vendor?: string;
  };
  cpu?: {
    architecture?: string;
  };
  engine?: {
    name?: string;
    version?: string;
  };
  ua?: string;
}
export interface LocationInfo {
  latitude?: number;
  longitude?: number;
  accuracy?: number;
  altitude?: number | null;
  altitude_accuracy?: number | null;
  heading?: number | null;
  speed?: number | null;
}
