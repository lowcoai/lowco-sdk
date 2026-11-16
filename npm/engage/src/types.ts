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
  /**
   * Show the app's live Engage forms (popups, slide-ins, bars and inline
   * `<div data-engage-form="<id>">` forms) by the display rules set in
   * Engage. Fetched after init and on SPA route changes.
   */
  forms?: boolean;
  /**
   * Also send each tracked event to the Meta pixel (`fbq`, with
   * `{ eventID }`) and gtag (`event_id` parameter) when those globals are
   * on the page, with the same `event_id` Engage stores, so Meta and
   * Google dedupe them against the conversions Engage forwards server-side.
   * `page_view` is never mirrored. Off by default.
   */
  mirrorEventIds?: boolean;
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

/**
 * An event for trackBatch(). Only `event_name` is required; the rest
 * default to what track() would send (pass `user_id: null` for none).
 */
export interface BatchEventInput {
  event_name: string;
  event_data?: Metadata;
  user_id?: string | null;
  device_id?: string;
  session_id?: string;
  device_info?: DeviceInfo | null;
  location?: LocationInfo | null;
  event_time?: Date | string;
}

/** One event's outcome in a batch, by its place in the batch. */
export interface BatchRow {
  index: number;
  eventName: string;
  ok: boolean;
  error?: string;
  issues?: Metadata[];
}

/** POST /v1/engage/track/batch's answer. */
export interface BatchResult {
  accepted: number;
  rejected: number;
  results: BatchRow[];
}

export type {
  EngageForm,
  FormConsent,
  FormContent,
  FormDisplay,
  FormField,
  FormFieldError,
  FormFieldType,
  FormMode,
  FormSubmitResult,
  FormTrigger,
  FormTriggerType,
} from "./forms";
