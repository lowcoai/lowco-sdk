import { FluxError, FluxUnauthorizedError } from "./errors.js";
import {
  ALL_EVENTS,
  type ChannelEventHandler,
  type ConnectionState,
  type ErrorHandler,
  type FluxClientOptions,
  type MessageData,
  type MessageHandler,
  type MessageType,
  type SocketMessage,
  type StateHandler,
  type SubscriptionSpec,
  type TopicSubscription,
} from "./types.js";
import { buildWebSocketUrl, generateClientId, normalizeTopic } from "./utils.js";

const DEFAULT_HEARTBEAT_INTERVAL_MS = 5000;
const DEFAULT_RECONNECT_INTERVAL_MS = 1000;
const MAX_RECONNECT_INTERVAL_MS = 30_000;
/** The close code flux sends after rejecting a connection's token. */
const CLOSE_POLICY_VIOLATION = 1008;

type ResolvedOptions = {
  getToken?: FluxClientOptions["getToken"];
  orgId: string;
  clientId: string;
  heartbeatIntervalMs: number;
  reconnectIntervalMs: number;
  queryParams?: Record<string, string>;
  webSocketImpl: typeof WebSocket;
};

/**
 * WebSocket client for the flux realtime service. One instance owns a single
 * connection, automatically reconnects with exponential backoff, and replays
 * every subscription — event filters included — on each reconnect.
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
  private token: string;
  /** Awaiting `getToken` before opening a socket. */
  private resolvingToken = false;
  /**
   * The server rejected the current token and nothing newer was available:
   * no reconnect is scheduled until `setToken` or `connect()`.
   */
  private stoppedForAuth = false;
  /**
   * What this client wants delivered: topic → event patterns (`*` = every
   * event). It is the client's own record rather than a mirror of the
   * server's acks, so a reconnect replays it in full, and a subscribe made
   * while the socket is down is simply sent on the next open.
   */
  private readonly desired = new Map<string, Set<string>>();
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
    this.token = options.token;
    this.options = {
      getToken: options.getToken,
      orgId: options.orgId,
      clientId: options.clientId ?? generateClientId(),
      heartbeatIntervalMs:
        options.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_INTERVAL_MS,
      reconnectIntervalMs:
        options.reconnectIntervalMs ?? DEFAULT_RECONNECT_INTERVAL_MS,
      queryParams: options.queryParams,
      webSocketImpl: ws,
    };
  }

  connect(): void {
    if (
      this.resolvingToken ||
      (this.ws && this.ws.readyState !== this.options.webSocketImpl.CLOSED)
    ) {
      return;
    }
    this.manuallyClosed = false;
    this.stoppedForAuth = false;
    this.clearReconnectTimer();
    if (!this.options.getToken) {
      this.open(this.token);
      return;
    }
    this.resolvingToken = true;
    void this.resolveToken().then((token) => {
      this.resolvingToken = false;
      if (!this.manuallyClosed) {
        this.open(token);
      }
    });
  }

  /**
   * Use `token` from the next connect on. A client stopped by a rejected
   * token reconnects at once.
   */
  setToken(token: string): void {
    if (!token) {
      return;
    }
    this.token = token;
    if (this.stoppedForAuth && !this.manuallyClosed) {
      this.connect();
    }
  }

  private open(token: string): void {
    const WSImpl = this.options.webSocketImpl;
    const ws = new WSImpl(this.buildUrl(token));
    this.ws = ws;
    let rejected = false;

    ws.onopen = () => {
      // The backoff is not reset here: flux upgrades before it checks the
      // token, so a rejected socket opens too. The first pong resets it.
      this._isConnected = true;
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

      if (payload.event === "pong") {
        if (!this.isExpectedPong(payload.data)) {
          this.emitError(new Error("pong out of sync, reconnecting"));
          ws.close();
          return;
        }
        this.reconnectAttempt = 0;
      }
      if (isAuthRejection(payload)) {
        rejected = true;
      }
      this.emitChannelEvent(payload);
      this.emitMessage(payload);
    };

    ws.onclose = (event?: CloseEvent) => {
      this._isConnected = false;
      this.stopHeartbeat();
      this.emitState("disconnected");
      this.ws = null;
      if (this.manuallyClosed) {
        return;
      }
      if (rejected || event?.code === CLOSE_POLICY_VIOLATION) {
        this.handleAuthRejection(token);
        return;
      }
      this.scheduleReconnect();
    };

    ws.onerror = () => {
      this.emitState("error");
      this.emitError(new Error("websocket error"));
    };
  }

  /**
   * Retrying a token the server just refused only repeats the refusal, so
   * reconnect only when a different one is available, else stop.
   */
  private handleAuthRejection(rejected: string): void {
    this.emitError(new FluxUnauthorizedError());
    void this.resolveToken().then((next) => {
      if (
        this.manuallyClosed ||
        this.ws ||
        this.reconnectTimer ||
        this.resolvingToken
      ) {
        return;
      }
      if (next === rejected) {
        this.stoppedForAuth = true;
        return;
      }
      this.scheduleReconnect();
    });
  }

  private scheduleReconnect(): void {
    const delay = Math.min(
      this.options.reconnectIntervalMs * 2 ** this.reconnectAttempt,
      MAX_RECONNECT_INTERVAL_MS,
    );
    this.reconnectAttempt += 1;
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private async resolveToken(): Promise<string> {
    try {
      const token = await this.options.getToken?.();
      if (token) {
        this.token = token;
      }
    } catch {
      /* keep the last token */
    }
    return this.token;
  }

  isConnected(): boolean {
    return this._isConnected;
  }

  disconnect(): void {
    this.manuallyClosed = true;
    this.stoppedForAuth = false;
    this.clearReconnectTimer();
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
  }

  /**
   * Ask the server for a topic's events. Pass `events` to receive only the
   * matching ones — `subscribe("channel:<schema>", { events: ["messages.*"] })`
   * — or omit it for every event. Subscribes add to what the client already
   * holds on a topic; only the difference goes over the wire. While the
   * socket is down the subscription is kept and sent on the next open.
   */
  subscribe(
    channel: string,
    options?: { events?: readonly string[] },
  ): FluxChannel;
  subscribe(topics: SubscriptionSpec[]): void;
  subscribe(
    channelOrTopics: string | SubscriptionSpec[],
    options?: { events?: readonly string[] },
  ): FluxChannel | void {
    const specs = parseSpecs(
      Array.isArray(channelOrTopics)
        ? channelOrTopics
        : [{ topic: channelOrTopics, events: options?.events }],
    );
    const first = specs[0];
    if (!first) {
      throw new FluxError("at least one topic is required to subscribe");
    }
    const added: TopicSubscription[] = [];
    for (const { topic, events } of specs) {
      let held = this.desired.get(topic);
      if (!held) {
        held = new Set();
        this.desired.set(topic, held);
      }
      const fresh = (events ?? [ALL_EVENTS]).filter((e) => !held.has(e));
      fresh.forEach((e) => held.add(e));
      if (fresh.length > 0) added.push({ topic, events: fresh });
    }
    if (added.length > 0 && this.isOpen()) {
      this.send("flux:subscription", "sb", added.map(toWire), "action");
    }
    if (Array.isArray(channelOrTopics)) {
      return;
    }
    return this.getOrCreateChannel(first.topic);
  }

  /**
   * Stop receiving events. A bare topic drops it whole; a topic with
   * `events` drops only those patterns, and the topic once none is left.
   * The single-topic overload also removes the channel's bound handlers.
   */
  unsubscribe(channel: string): void;
  unsubscribe(topics: SubscriptionSpec[]): void;
  unsubscribe(channelOrTopics: string | SubscriptionSpec[]): void {
    const specs = parseSpecs(
      Array.isArray(channelOrTopics) ? channelOrTopics : [channelOrTopics],
    );
    const first = specs[0];
    if (!first) {
      throw new FluxError("at least one topic is required to unsubscribe");
    }
    const removed: SubscriptionSpec[] = [];
    for (const { topic, events } of specs) {
      const held = this.desired.get(topic);
      if (!events) {
        this.desired.delete(topic);
        removed.push(topic);
        continue;
      }
      if (!held) continue;
      const dropped = events.filter((e) => held.delete(e));
      if (held.size === 0) {
        // Released whole, so the server drops the topic whatever it holds.
        this.desired.delete(topic);
        removed.push(topic);
      } else if (dropped.length > 0) {
        removed.push({ topic, events: dropped });
      }
    }
    // A closed socket has nothing to tell: the server drops a connection's
    // subscriptions with it, and the next open replays only what is left.
    if (removed.length > 0 && this.isOpen()) {
      this.send("flux:subscription", "usb", removed, "action");
    }
    if (!Array.isArray(channelOrTopics)) {
      this.clearChannelHandlers(first.topic);
      this.channels.delete(first.topic);
    }
  }

  sendMessage(channel: string, event: string, data: MessageData): void {
    this.send(channel, event, data);
  }

  /** The topics this client holds (and replays on every reconnect). */
  getSubscribedTopics(): string[] {
    return [...this.desired.keys()];
  }

  /** Every held topic with the event patterns asked of it. */
  getSubscriptions(): TopicSubscription[] {
    return [...this.desired].map(([topic, events]) => ({
      topic,
      events: [...events],
    }));
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

  private buildUrl(token: string): string {
    return buildWebSocketUrl(
      token,
      this.options.orgId,
      this.options.clientId,
      // Tells the server this client re-sends every subscription on
      // connect, so it starts the socket clean.
      { ...this.options.queryParams, replay: "1" },
    );
  }

  private isExpectedPong(content: unknown): boolean {
    if (this.lastSentSeq === null) {
      return false;
    }
    const seq = Number(content);
    return Number.isFinite(seq) && seq === this.lastSentSeq;
  }

  private isOpen(): boolean {
    return (
      this.ws !== null &&
      this.ws.readyState === this.options.webSocketImpl.OPEN
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

  /** A new socket holds nothing server-side: replay everything wanted. */
  private resubscribeTopics(): void {
    const all = this.getSubscriptions().map(toWire);
    if (all.length === 0) {
      return;
    }
    try {
      this.send("flux:subscription", "sb", all, "action");
    } catch {
      /* socket may not be ready yet */
    }
  }
}

interface ParsedSpec {
  topic: string;
  /** null for a bare topic: every event on subscribe, the whole topic on unsubscribe. */
  events: string[] | null;
}

function parseSpecs(specs: readonly SubscriptionSpec[]): ParsedSpec[] {
  const out: ParsedSpec[] = [];
  for (const spec of specs) {
    const topic = normalizeTopic(typeof spec === "string" ? spec : spec?.topic);
    if (!topic) continue;
    const raw = typeof spec === "string" ? undefined : spec.events;
    const events = [
      ...new Set((raw ?? []).map((e) => normalizeTopic(e)).filter(Boolean)),
    ];
    out.push({ topic, events: events.length > 0 ? events : null });
  }
  return out;
}

/** The frame flux sends just before closing a socket whose token it refused. */
function isAuthRejection(message: SocketMessage): boolean {
  return (
    message.type === "error" &&
    message.channel === "flux:error" &&
    message.event === "Unauthorized"
  );
}

/** A bare string when the topic wants every event — the frame older servers read. */
function toWire({ topic, events }: TopicSubscription): SubscriptionSpec {
  if (!events || (events.length === 1 && events[0] === ALL_EVENTS)) {
    return topic;
  }
  return { topic, events: [...events] };
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
