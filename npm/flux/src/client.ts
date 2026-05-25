import { FluxError } from "./errors.js";
import {
  type ChannelEventHandler,
  type ConnectionState,
  type ErrorHandler,
  type FluxClientOptions,
  type MessageData,
  type MessageHandler,
  type MessageType,
  type SocketMessage,
  type StateHandler,
} from "./types.js";
import {
  buildWebSocketUrl,
  generateClientId,
  normalizeTopic,
  normalizeTopics,
} from "./utils.js";

const DEFAULT_HEARTBEAT_INTERVAL_MS = 5000;
const DEFAULT_RECONNECT_INTERVAL_MS = 1000;
const MAX_RECONNECT_INTERVAL_MS = 30_000;

type ResolvedOptions = {
  baseUrl: string;
  token: string;
  orgId: string;
  clientId: string;
  userId: string;
  heartbeatIntervalMs: number;
  reconnectIntervalMs: number;
  queryParams?: Record<string, string>;
  webSocketImpl: typeof WebSocket;
};

/**
 * WebSocket client for the flux realtime service. One instance owns a single
 * connection, automatically reconnects with exponential backoff, and keeps
 * topic subscriptions in sync across reconnects.
 */
export class FluxClient {
  private static instance: FluxClient | null = null;

  /**
   * Returns the process-wide singleton, creating and connecting it on first
   * call. Subsequent calls ignore `options`.
   */
  static getInstance(options?: FluxClientOptions): FluxClient {
    if (!FluxClient.instance) {
      if (!options) {
        throw new FluxError(
          "FluxClient.getInstance: options are required on first call",
        );
      }
      FluxClient.instance = new FluxClient(options);
      FluxClient.instance.connect();
    }
    return FluxClient.instance;
  }

  /** Disconnects and clears the singleton (if any). */
  static destroyInstance(): void {
    FluxClient.instance?.disconnect();
    FluxClient.instance = null;
  }

  private readonly options: ResolvedOptions;

  private ws: WebSocket | null = null;
  private pingSeq = 1;
  private lastSentSeq: number | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempt = 0;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private manuallyClosed = false;
  private subscribed = new Set<string>();
  private _isConnected = false;

  private readonly onMessageHandlers = new Set<MessageHandler>();
  private readonly onErrorHandlers = new Set<ErrorHandler>();
  private readonly onStateHandlers = new Set<StateHandler>();
  private readonly channelEventHandlers = new Map<
    string,
    Map<string, Set<ChannelEventHandler>>
  >();
  private readonly channels = new Map<string, FluxChannel>();

  constructor(options: FluxClientOptions) {
    if (!options.baseUrl) {
      throw new FluxError("baseUrl is required");
    }
    if (!options.token) {
      throw new FluxError("token is required");
    }
    if (!options.orgId) {
      throw new FluxError("orgId is required");
    }
    const ws =
      options.webSocketImpl ??
      (globalThis as { WebSocket?: typeof WebSocket }).WebSocket;
    if (!ws) {
      throw new FluxError(
        "no WebSocket implementation found; pass webSocketImpl in options",
      );
    }
    this.options = {
      baseUrl: options.baseUrl,
      token: options.token,
      orgId: options.orgId,
      clientId: options.clientId ?? generateClientId(),
      userId: options.userId ?? "",
      heartbeatIntervalMs:
        options.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_INTERVAL_MS,
      reconnectIntervalMs:
        options.reconnectIntervalMs ?? DEFAULT_RECONNECT_INTERVAL_MS,
      queryParams: options.queryParams,
      webSocketImpl: ws,
    };
  }

  connect(): void {
    if (this.ws && this.ws.readyState !== this.options.webSocketImpl.CLOSED) {
      return;
    }
    this.manuallyClosed = false;
    this.clearReconnectTimer();

    const WSImpl = this.options.webSocketImpl;
    const ws = new WSImpl(this.buildUrl());
    this.ws = ws;

    ws.onopen = () => {
      this._isConnected = true;
      this.reconnectAttempt = 0;
      this.emitState("connected");
      this.startHeartbeat();
      this.resubscribeTopics();
    };

    ws.onmessage = (event: MessageEvent) => {
      const text = event.data as string;
      let payload: SocketMessage;
      try {
        payload = JSON.parse(text) as SocketMessage;
      } catch {
        this.emitError(new Error(`received non-JSON message: ${text}`));
        return;
      }

      if (payload.event === "pong" && !this.isExpectedPong(payload.data)) {
        this.emitError(new Error("pong out of sync, reconnecting"));
        ws.close();
        return;
      }
      if (payload.event === "sb" || payload.event === "usb") {
        this.syncSubscribed(payload.data);
      }
      this.emitChannelEvent(payload);
      this.emitMessage(payload);
    };

    ws.onclose = () => {
      this._isConnected = false;
      this.stopHeartbeat();
      this.emitState("disconnected");
      this.ws = null;
      if (!this.manuallyClosed) {
        const delay = Math.min(
          this.options.reconnectIntervalMs * 2 ** this.reconnectAttempt,
          MAX_RECONNECT_INTERVAL_MS,
        );
        this.reconnectAttempt += 1;
        this.reconnectTimer = setTimeout(() => this.connect(), delay);
      }
    };

    ws.onerror = () => {
      this.emitState("error");
      this.emitError(new Error("websocket error"));
    };
  }

  isConnected(): boolean {
    return this._isConnected;
  }

  disconnect(): void {
    this.manuallyClosed = true;
    this.clearReconnectTimer();
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
  }

  subscribe(channel: string): FluxChannel;
  subscribe(topics: string[]): void;
  subscribe(channelOrTopics: string | string[]): FluxChannel | void {
    const normalized = normalizeTopics(
      Array.isArray(channelOrTopics) ? channelOrTopics : [channelOrTopics],
    );
    if (normalized.length === 0) {
      throw new FluxError("at least one topic is required to subscribe");
    }
    this.send("flux:subscription", "sb", normalized, "action");
    if (Array.isArray(channelOrTopics)) {
      return;
    }
    return this.getOrCreateChannel(normalized[0]!);
  }

  unsubscribe(channel: string): void;
  unsubscribe(topics: string[]): void;
  unsubscribe(channelOrTopics: string | string[]): void {
    const normalized = normalizeTopics(
      Array.isArray(channelOrTopics) ? channelOrTopics : [channelOrTopics],
    );
    if (normalized.length === 0) {
      throw new FluxError("at least one topic is required to unsubscribe");
    }
    this.send("flux:subscription", "usb", normalized, "action");
    if (!Array.isArray(channelOrTopics)) {
      const name = normalized[0]!;
      this.clearChannelHandlers(name);
      this.channels.delete(name);
    }
  }

  sendMessage(channel: string, event: string, data: MessageData): void {
    this.send(channel, event, data);
  }

  getSubscribedTopics(): string[] {
    return [...this.subscribed];
  }

  onMessage(handler: MessageHandler): () => void {
    this.onMessageHandlers.add(handler);
    return () => this.onMessageHandlers.delete(handler);
  }

  onError(handler: ErrorHandler): () => void {
    this.onErrorHandlers.add(handler);
    return () => this.onErrorHandlers.delete(handler);
  }

  onState(handler: StateHandler): () => void {
    this.onStateHandlers.add(handler);
    return () => this.onStateHandlers.delete(handler);
  }

  bind(
    channel: string,
    eventName: string,
    handler: ChannelEventHandler,
  ): () => void {
    const normalizedChannel = normalizeTopic(channel);
    const normalizedEvent = normalizeTopic(eventName);
    if (!normalizedChannel) {
      throw new FluxError("channel is required");
    }
    if (!normalizedEvent) {
      throw new FluxError("eventName is required");
    }

    let eventMap = this.channelEventHandlers.get(normalizedChannel);
    if (!eventMap) {
      eventMap = new Map<string, Set<ChannelEventHandler>>();
      this.channelEventHandlers.set(normalizedChannel, eventMap);
    }

    let handlers = eventMap.get(normalizedEvent);
    if (!handlers) {
      handlers = new Set<ChannelEventHandler>();
      eventMap.set(normalizedEvent, handlers);
    }
    handlers.add(handler);

    return () => {
      handlers!.delete(handler);
      if (handlers!.size === 0) {
        eventMap!.delete(normalizedEvent);
      }
      if (eventMap!.size === 0) {
        this.channelEventHandlers.delete(normalizedChannel);
      }
    };
  }

  unbind(
    channel: string,
    eventName?: string,
    handler?: ChannelEventHandler,
  ): void {
    const normalizedChannel = normalizeTopic(channel);
    if (!normalizedChannel) {
      throw new FluxError("channel is required");
    }
    const eventMap = this.channelEventHandlers.get(normalizedChannel);
    if (!eventMap) {
      return;
    }
    if (!eventName) {
      this.channelEventHandlers.delete(normalizedChannel);
      return;
    }

    const normalizedEvent = normalizeTopic(eventName);
    if (!normalizedEvent) {
      return;
    }
    const handlers = eventMap.get(normalizedEvent);
    if (!handlers) {
      return;
    }
    if (!handler) {
      eventMap.delete(normalizedEvent);
    } else {
      handlers.delete(handler);
      if (handlers.size === 0) {
        eventMap.delete(normalizedEvent);
      }
    }
    if (eventMap.size === 0) {
      this.channelEventHandlers.delete(normalizedChannel);
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.send("flux:health_check", "pi", `${this.pingSeq}`);
    this.lastSentSeq = this.pingSeq;
    this.pingSeq = 1;

    this.heartbeatTimer = setInterval(() => {
      this.lastSentSeq = this.pingSeq;
      this.send("flux:health_check", "pi", `${this.pingSeq}`);
      this.pingSeq += 1;
    }, this.options.heartbeatIntervalMs);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private send(
    channel: string,
    event: string,
    data: MessageData,
    type: MessageType = "action",
  ): void {
    if (!this.ws || this.ws.readyState !== this.options.webSocketImpl.OPEN) {
      throw new FluxError("websocket is not connected");
    }
    const msg: SocketMessage = {
      channel,
      type,
      event,
      data,
      timestamp: Math.floor(Date.now() / 1000),
      request_id:
        Date.now().toString(36) + Math.random().toString(36).substring(2, 15),
    };

    this.ws.send(JSON.stringify(msg));
  }

  private buildUrl(): string {
    return buildWebSocketUrl(
      this.options.baseUrl,
      this.options.token,
      this.options.orgId,
      this.options.clientId,
      this.options.userId,
      this.options.queryParams,
    );
  }

  private isExpectedPong(content: unknown): boolean {
    if (this.lastSentSeq === null) {
      return false;
    }
    const seq = Number(content);
    return Number.isFinite(seq) && seq === this.lastSentSeq;
  }

  private syncSubscribed(content: unknown): void {
    if (!Array.isArray(content)) {
      return;
    }
    this.subscribed = new Set(
      content.filter((v): v is string => typeof v === "string" && v.length > 0),
    );
  }

  private emitMessage(message: SocketMessage): void {
    for (const handler of this.onMessageHandlers) {
      handler(message);
    }
  }

  private emitError(error: Error): void {
    for (const handler of this.onErrorHandlers) {
      handler(error);
    }
  }

  private emitState(state: ConnectionState): void {
    for (const handler of this.onStateHandlers) {
      handler(state);
    }
  }

  private emitChannelEvent(message: SocketMessage): void {
    const channel = normalizeTopic(message.channel);
    const eventName = normalizeTopic(message.event);
    if (!channel || !eventName) {
      return;
    }

    const eventMap = this.channelEventHandlers.get(channel);
    if (!eventMap) {
      return;
    }
    const handlers = eventMap.get(eventName);
    if (!handlers || handlers.size === 0) {
      return;
    }
    for (const handler of handlers) {
      handler(message.data, message);
    }
  }

  private getOrCreateChannel(name: string): FluxChannel {
    const normalized = normalizeTopic(name);
    if (!normalized) {
      throw new FluxError("channel is required");
    }
    const existing = this.channels.get(normalized);
    if (existing) {
      return existing;
    }
    const created = new FluxChannel(this, normalized);
    this.channels.set(normalized, created);
    return created;
  }

  private clearChannelHandlers(channel: string): void {
    const normalized = normalizeTopic(channel);
    if (!normalized) {
      return;
    }
    this.channelEventHandlers.delete(normalized);
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private resubscribeTopics(): void {
    const topics = [...this.subscribed];
    if (topics.length === 0) {
      return;
    }
    try {
      this.send("flux:subscription", "sb", topics, "action");
    } catch {
      /* socket may not be ready yet */
    }
  }
}

/** Convenience handle for a single channel returned by `subscribe(name)`. */
export class FluxChannel {
  constructor(
    private readonly client: FluxClient,
    public readonly name: string,
  ) {}

  bind(eventName: string, handler: ChannelEventHandler): () => void {
    return this.client.bind(this.name, eventName, handler);
  }

  unbind(eventName?: string, handler?: ChannelEventHandler): void {
    this.client.unbind(this.name, eventName, handler);
  }

  unsubscribe(): void {
    this.client.unsubscribe(this.name);
  }

  destroy(): void {
    this.client.unbind(this.name);
    this.client.unsubscribe(this.name);
  }

  sendMessage(eventName: string, data: MessageData): void {
    this.client.sendMessage(this.name, eventName, data);
  }
}
