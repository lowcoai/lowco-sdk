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

export interface FluxClientOptions {
  /** WebSocket base URL, e.g. "wss://flux.example.com" or "https://flux.example.com". */
  baseUrl: string;
  /** Authentication token. */
  token: string;
  /** Organization id. */
  orgId: string;
  /** Optional stable client id (defaults to a generated value). */
  clientId?: string;
  /** Optional user id sent as `userId` query parameter. */
  userId?: string;
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
