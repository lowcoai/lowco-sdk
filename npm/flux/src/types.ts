export type MessageData = unknown;

export type MessageType = "action" | "event" | "system" | "error" | "ack";

export interface MessageMeta {
  seq?: number;
  run_id?: string;
}

export interface SocketMessage {
  type?: MessageType;
  channel?: string;
  event?: string;
  data?: MessageData;
  request_id?: string;
  timestamp?: number;
  meta?: MessageMeta;
}

export type ConnectionState = "connected" | "disconnected" | "error";

export type MessageHandler = (message: SocketMessage) => void;
export type ErrorHandler = (error: Error) => void;
export type StateHandler = (state: ConnectionState) => void;
export type ChannelEventHandler = (
  data: MessageData,
  message: SocketMessage,
) => void;

export enum SocketEvent {
  PING = "pi",
  PONG = "po",
  SUBSCRIBE = "sb",
  UNSUBSCRIBE = "usb",
  MESSAGE = "m",
  REPLY = "reply",
}

/** The event pattern that matches every event on a topic. */
export const ALL_EVENTS = "*";

/**
 * A topic, narrowed to the events wanted from it. The server delivers only
 * events matching one of the patterns: `*` alone is every event, otherwise
 * patterns are compared token by token on `.` with `*` matching exactly one
 * token — `messages.*`, `*.delete`, `messages.insert`. Omitted or empty
 * `events` means every event (subscribe) or the whole topic (unsubscribe).
 */
export interface TopicSubscription {
  topic: string;
  events?: readonly string[];
}

/** A bare topic string (every event) or a topic with an event filter. */
export type SubscriptionSpec = string | TopicSubscription;

export interface FluxClientOptions {
  /** Authentication token (user token or API key) sent as the `token` query parameter. Required. */
  token: string;
  /**
   * Called before every (re)connect so a refreshed token is picked up.
   * Returning empty/null, or throwing, falls back to the last token used.
   */
  getToken?: () =>
    | string
    | null
    | undefined
    | Promise<string | null | undefined>;
  /** Organization id. */
  orgId: string;
  /** Optional stable client id (defaults to a generated value). */
  clientId?: string;
  /** Heartbeat interval in milliseconds (default 5000). */
  heartbeatIntervalMs?: number;
  /** Initial reconnect backoff in milliseconds (default 1000). */
  reconnectIntervalMs?: number;
  /** Extra query parameters to add to the WebSocket URL. */
  queryParams?: Record<string, string>;
  /**
   * Custom WebSocket constructor; defaults to `globalThis.WebSocket`. Provide
   * one (e.g. the `ws` package) when running in Node versions without a
   * built-in WebSocket implementation.
   */
  webSocketImpl?: typeof WebSocket;
}
