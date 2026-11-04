export interface Config {
  /**
   * Credential. Required. An `lc_…` API key (admin portal) is sent as
   * `X-Api-Key`; anything else (an OAuth2 access token) as
   * `Authorization: Bearer <apiKey>`.
   */
  apiKey: string;
  /** Sent as `X-Org-Id`. Required. */
  orgId: string;
  /**
   * Engage app to track into, sent as `X-Engage-App-Id`. Optional: without
   * it events go to the org's default app.
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
