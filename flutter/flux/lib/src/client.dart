import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'errors.dart';
import 'json.dart';
import 'types.dart';
import 'utils.dart';

/// Opens a WebSocket to [uri]. [FluxClient] defaults to
/// [WebSocketChannel.connect]; tests (or apps that need a custom HTTP client,
/// proxy or headers) inject their own.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

const _defaultHeartbeatInterval = Duration(seconds: 5);
const _defaultReconnectInterval = Duration(seconds: 1);
const _maxReconnectInterval = Duration(seconds: 30);

const _subscriptionChannel = 'flux:subscription';
const _healthCheckChannel = 'flux:health_check';
const _pongReply = 'pong';
const _normalClosure = 1000;

/// WebSocket client for the flux realtime service.
///
/// One instance owns a single connection, automatically reconnects with
/// exponential backoff, and replays every subscription (event filters
/// included) on each reconnect.
class FluxClient {
  /// Creates a client for `wss://ws.lowco.ai/`. Nothing is dialled until
  /// [connect] is called.
  ///
  /// Throws [FluxException] when [token] or [orgId] is blank, or when an
  /// interval is not positive.
  FluxClient({
    required String token,
    required String orgId,
    String? clientId,
    this.heartbeatInterval = _defaultHeartbeatInterval,
    this.reconnectInterval = _defaultReconnectInterval,
    Map<String, String>? queryParams,
    WebSocketChannelFactory? channelFactory,
  })  : _token = token,
        _orgId = orgId,
        clientId = clientId == null || clientId.trim().isEmpty ? generateClientId() : clientId,
        _queryParams = Map.unmodifiable(queryParams ?? const <String, String>{}),
        _channelFactory = channelFactory ?? WebSocketChannel.connect {
    if (token.trim().isEmpty) throw const FluxException('token is required');
    if (orgId.trim().isEmpty) throw const FluxException('orgId is required');
    if (heartbeatInterval <= Duration.zero) {
      throw const FluxException('heartbeatInterval must be positive');
    }
    if (reconnectInterval <= Duration.zero) {
      throw const FluxException('reconnectInterval must be positive');
    }
  }

  static FluxClient? _instance;

  /// Returns the process-wide singleton, creating and connecting it on the
  /// first call. Later calls ignore the arguments.
  ///
  /// Throws [FluxException] when no instance exists yet and [token] / [orgId]
  /// are missing.
  static FluxClient getInstance({
    String? token,
    String? orgId,
    String? clientId,
    Duration? heartbeatInterval,
    Duration? reconnectInterval,
    Map<String, String>? queryParams,
    WebSocketChannelFactory? channelFactory,
  }) {
    final existing = _instance;
    if (existing != null) return existing;
    if (token == null && orgId == null) {
      throw const FluxException(
          'FluxClient.getInstance: token and orgId are required on first call');
    }
    final created = FluxClient(
      token: token ?? '',
      orgId: orgId ?? '',
      clientId: clientId,
      heartbeatInterval: heartbeatInterval ?? _defaultHeartbeatInterval,
      reconnectInterval: reconnectInterval ?? _defaultReconnectInterval,
      queryParams: queryParams,
      channelFactory: channelFactory,
    );
    _instance = created;
    created.connect();
    return created;
  }

  /// Disconnects and clears the singleton (if any).
  static void destroyInstance() {
    _instance?.disconnect();
    _instance = null;
  }

  final String _token;
  final String _orgId;

  /// Sent as the `cli` query parameter; a random UUID unless given.
  final String clientId;

  /// Ping cadence (default 5 s).
  final Duration heartbeatInterval;

  /// Initial reconnect backoff (default 1 s). It doubles after every failed
  /// attempt and is capped at 30 s.
  final Duration reconnectInterval;

  final Map<String, String> _queryParams;
  final WebSocketChannelFactory _channelFactory;

  _Connection? _conn;
  int _pingSeq = 1;
  int? _lastSentSeq;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  Timer? _heartbeatTimer;
  bool _manuallyClosed = false;
  bool _connected = false;

  /// What this client wants delivered: topic -> event patterns ([allEvents] =
  /// every event). It is the client's own record rather than a mirror of the
  /// server's acks, so a reconnect replays it in full, and a subscribe made
  /// while the socket is down is simply sent on the next open.
  final Map<String, Set<String>> _desired = {};

  final Set<MessageHandler> _messageHandlers = {};
  final Set<ErrorHandler> _errorHandlers = {};
  final Set<StateHandler> _stateHandlers = {};
  final Map<String, Map<String, Set<ChannelEventHandler>>> _channelHandlers = {};
  final Map<String, FluxChannel> _channels = {};

  final _messages = StreamController<SocketMessage>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _states = StreamController<ConnectionState>.broadcast();

  /// Every received message (broadcast; the same events as [onMessage]).
  Stream<SocketMessage> get messages => _messages.stream;

  /// Transient socket errors (broadcast; the same events as [onError]).
  Stream<Object> get errors => _errors.stream;

  /// Connection state changes (broadcast; the same events as [onState]).
  Stream<ConnectionState> get states => _states.stream;

  /// True once the socket has opened, false again when it closes.
  bool get isConnected => _connected;

  /// Opens the socket. A no-op while a socket is open or connecting; clears a
  /// previous [disconnect] so auto-reconnect is back on.
  void connect() {
    if (_conn != null) return;
    _manuallyClosed = false;
    _clearReconnectTimer();

    final WebSocketChannel channel;
    try {
      channel = _channelFactory(Uri.parse(_buildUrl()));
    } catch (error) {
      // A factory that throws is treated like a socket that failed to open.
      _emitState(ConnectionState.error);
      _emitError(error);
      _emitState(ConnectionState.disconnected);
      _scheduleReconnect();
      return;
    }

    final conn = _Connection(channel);
    _conn = conn;
    conn.subscription = channel.stream.listen(
      (data) => _onData(conn, data),
      onError: (Object error) => _onSocketError(conn, error),
      onDone: () => _onClosed(conn),
    );
    unawaited(channel.ready.then(
      (_) => _onOpen(conn),
      onError: (Object error) {
        _onSocketError(conn, error);
        _onClosed(conn);
      },
    ));
  }

  /// Closes the socket and stops auto-reconnect until the next [connect].
  void disconnect() {
    _manuallyClosed = true;
    _clearReconnectTimer();
    _stopHeartbeat();
    final conn = _conn;
    _conn = null;
    _connected = false;
    if (conn != null && !conn.closed) {
      conn.closed = true;
      conn.close();
      _emitState(ConnectionState.disconnected);
    }
  }

  /// Asks the server for a topic's events and returns its (cached) handle.
  ///
  /// Pass [events] to receive only the matching ones
  /// (`subscribe('channel:<schema>', events: ['messages.*'])`) or omit it for
  /// every event. Subscribes add to what the client already holds on a topic;
  /// only the difference goes over the wire. While the socket is down the
  /// subscription is kept and sent on the next open.
  FluxChannel subscribe(String topic, {List<String>? events}) {
    final specs = _parseSpecs([TopicSubscription(topic, events: events)]);
    if (specs.isEmpty) {
      throw const FluxException('at least one topic is required to subscribe');
    }
    _addSubscriptions(specs);
    return _getOrCreateChannel(specs.first.topic);
  }

  /// Subscribes to a batch of topics, each with its own event filter, in one
  /// frame. Does not create channel handles.
  void subscribeMany(List<TopicSubscription> topics) {
    final specs = _parseSpecs(topics);
    if (specs.isEmpty) {
      throw const FluxException('at least one topic is required to subscribe');
    }
    _addSubscriptions(specs);
  }

  /// Drops [topic] whole, removes its bound handlers and forgets its handle.
  void unsubscribe(String topic) {
    final specs = _parseSpecs([TopicSubscription(topic)]);
    if (specs.isEmpty) {
      throw const FluxException('at least one topic is required to unsubscribe');
    }
    _removeSubscriptions(specs);
    final name = specs.first.topic;
    _channelHandlers.remove(name);
    _channels.remove(name);
  }

  /// Stops receiving events for a batch of topics. An entry without events
  /// drops its topic whole; an entry with events drops only those patterns,
  /// and the topic once none is left. Bound handlers are kept.
  void unsubscribeMany(List<TopicSubscription> topics) {
    final specs = _parseSpecs(topics);
    if (specs.isEmpty) {
      throw const FluxException('at least one topic is required to unsubscribe');
    }
    _removeSubscriptions(specs);
  }

  /// Sends an `action` message on [channel]. Throws [FluxException] when the
  /// socket is not open.
  void sendMessage(String channel, String event, Object? data) => _send(channel, event, data);

  /// The topics this client holds (and replays on every reconnect).
  List<String> getSubscribedTopics() => _desired.keys.toList();

  /// Every held topic with the event patterns asked of it.
  List<TopicSubscription> getSubscriptions() => [
        for (final entry in _desired.entries)
          TopicSubscription(entry.key, events: List.unmodifiable(entry.value)),
      ];

  /// Registers a handler for every received message; returns its remover.
  void Function() onMessage(MessageHandler handler) {
    _messageHandlers.add(handler);
    return () => _messageHandlers.remove(handler);
  }

  /// Registers a handler for transient socket errors; returns its remover.
  void Function() onError(ErrorHandler handler) {
    _errorHandlers.add(handler);
    return () => _errorHandlers.remove(handler);
  }

  /// Registers a connection-state handler; returns its remover.
  void Function() onState(StateHandler handler) {
    _stateHandlers.add(handler);
    return () => _stateHandlers.remove(handler);
  }

  /// Registers [handler] for messages on [channel] whose event is [event]
  /// (both compared trimmed, exactly). Returns its remover.
  void Function() bind(String channel, String event, ChannelEventHandler handler) {
    final name = normalizeTopic(channel);
    final eventName = normalizeTopic(event);
    if (name.isEmpty) throw const FluxException('channel is required');
    if (eventName.isEmpty) throw const FluxException('eventName is required');

    final eventMap = _channelHandlers.putIfAbsent(name, () => {});
    final handlers = eventMap.putIfAbsent(eventName, () => {});
    handlers.add(handler);

    return () {
      handlers.remove(handler);
      if (handlers.isEmpty && identical(eventMap[eventName], handlers)) {
        eventMap.remove(eventName);
      }
      if (eventMap.isEmpty && identical(_channelHandlers[name], eventMap)) {
        _channelHandlers.remove(name);
      }
    };
  }

  /// Removes handlers bound on [channel]: all of them, those of [event], or
  /// just [handler] for [event].
  void unbind(String channel, [String? event, ChannelEventHandler? handler]) {
    final name = normalizeTopic(channel);
    if (name.isEmpty) throw const FluxException('channel is required');
    final eventMap = _channelHandlers[name];
    if (eventMap == null) return;
    if (event == null || event.isEmpty) {
      _channelHandlers.remove(name);
      return;
    }
    final eventName = normalizeTopic(event);
    if (eventName.isEmpty) return;
    final handlers = eventMap[eventName];
    if (handlers == null) return;
    if (handler == null) {
      eventMap.remove(eventName);
    } else {
      handlers.remove(handler);
      if (handlers.isEmpty) eventMap.remove(eventName);
    }
    if (eventMap.isEmpty) _channelHandlers.remove(name);
  }

  // -- connection lifecycle ---------------------------------------------------

  bool _isCurrent(_Connection conn) => identical(_conn, conn) && !conn.closed;

  bool get _isOpen {
    final conn = _conn;
    return conn != null && conn.open && !conn.closed;
  }

  void _onOpen(_Connection conn) {
    if (!_isCurrent(conn)) return;
    conn.open = true;
    _connected = true;
    _reconnectAttempt = 0;
    _emitState(ConnectionState.connected);
    // A state handler may have disconnected already.
    if (!_isCurrent(conn)) return;
    _startHeartbeat();
    _resubscribeTopics();
  }

  void _onData(_Connection conn, Object? raw) {
    if (!_isCurrent(conn)) return;
    final text = switch (raw) {
      final String s => s,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => '$raw',
    };
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      _emitError(FluxException('received non-JSON message: $text'));
      return;
    }
    if (decoded is! Map) {
      _emitError(FluxException('received non-object message: $text'));
      return;
    }
    final message = SocketMessage.fromJson(readMap(decoded)!);
    if (message.event == _pongReply && !_isExpectedPong(message.data)) {
      _emitError(const FluxException('pong out of sync, reconnecting'));
      _onClosed(conn, closeSocket: true);
      return;
    }
    _emitChannelEvent(message);
    _emitMessage(message);
  }

  void _onSocketError(_Connection conn, Object error) {
    if (!_isCurrent(conn)) return;
    _emitState(ConnectionState.error);
    _emitError(error);
  }

  void _onClosed(_Connection conn, {bool closeSocket = false}) {
    if (conn.closed) return;
    conn.closed = true;
    if (closeSocket) conn.close();
    if (!identical(_conn, conn)) return;
    _conn = null;
    _connected = false;
    _stopHeartbeat();
    _emitState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // A state handler may have called connect() or disconnect() meanwhile.
    if (_manuallyClosed || _conn != null || _reconnectTimer != null) return;
    // Computed in doubles: 2^attempt must not overflow after many failures.
    final micros = math.min(
      reconnectInterval.inMicroseconds * math.pow(2.0, _reconnectAttempt),
      _maxReconnectInterval.inMicroseconds,
    );
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(microseconds: micros.round()), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _clearReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  String _buildUrl() => buildWebSocketUrl(
        _token,
        _orgId,
        clientId,
        // Tells the server this client re-sends every subscription on
        // connect, so it starts the socket clean.
        {..._queryParams, 'replay': '1'},
      );

  // -- heartbeat --------------------------------------------------------------

  void _startHeartbeat() {
    _stopHeartbeat();
    _trySend(_healthCheckChannel, SocketEvent.ping, '$_pingSeq');
    _lastSentSeq = _pingSeq;
    _pingSeq = 1;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _lastSentSeq = _pingSeq;
      _trySend(_healthCheckChannel, SocketEvent.ping, '$_pingSeq');
      _pingSeq += 1;
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  bool _isExpectedPong(Object? content) {
    final last = _lastSentSeq;
    if (last == null) return false;
    final num? seq = switch (content) {
      final num n => n,
      final String s => num.tryParse(s.trim()),
      _ => null,
    };
    return seq != null && seq.isFinite && seq == last;
  }

  // -- sending ----------------------------------------------------------------

  void _send(String channel, String event, Object? data, [String type = MessageType.action]) {
    final conn = _conn;
    if (conn == null || !conn.open || conn.closed) {
      throw const FluxException('websocket is not connected');
    }
    final frame = jsonEncode(<String, Object?>{
      'channel': channel,
      'type': type,
      'event': event,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'request_id': generateRequestId(),
    });
    conn.channel.sink.add(frame);
  }

  void _trySend(String channel, String event, Object? data) {
    try {
      _send(channel, event, data);
    } catch (error) {
      _emitError(error);
    }
  }

  // -- subscriptions ----------------------------------------------------------

  void _addSubscriptions(List<_ParsedSpec> specs) {
    final added = <Object>[];
    for (final spec in specs) {
      final held = _desired.putIfAbsent(spec.topic, () => <String>{});
      final fresh = [
        for (final e in spec.events ?? const [allEvents])
          if (!held.contains(e)) e,
      ];
      held.addAll(fresh);
      if (fresh.isNotEmpty) added.add(_toWire(spec.topic, fresh));
    }
    if (added.isNotEmpty && _isOpen) {
      _send(_subscriptionChannel, SocketEvent.subscribe, added, MessageType.action);
    }
  }

  void _removeSubscriptions(List<_ParsedSpec> specs) {
    final removed = <Object>[];
    for (final spec in specs) {
      final events = spec.events;
      if (events == null) {
        _desired.remove(spec.topic);
        removed.add(spec.topic);
        continue;
      }
      final held = _desired[spec.topic];
      if (held == null) continue;
      final dropped = <String>[];
      for (final e in events) {
        if (held.remove(e)) dropped.add(e);
      }
      if (held.isEmpty) {
        // Released whole, so the server drops the topic whatever it holds.
        _desired.remove(spec.topic);
        removed.add(spec.topic);
      } else if (dropped.isNotEmpty) {
        removed.add({'topic': spec.topic, 'events': dropped});
      }
    }
    // A closed socket has nothing to tell: the server drops a connection's
    // subscriptions with it, and the next open replays only what is left.
    if (removed.isNotEmpty && _isOpen) {
      _send(_subscriptionChannel, SocketEvent.unsubscribe, removed, MessageType.action);
    }
  }

  /// A new socket holds nothing server-side: replay everything wanted.
  void _resubscribeTopics() {
    final all = [for (final entry in _desired.entries) _toWire(entry.key, entry.value.toList())];
    if (all.isEmpty) return;
    try {
      _send(_subscriptionChannel, SocketEvent.subscribe, all, MessageType.action);
    } catch (_) {
      // The socket may already be gone; the next open replays again.
    }
  }

  FluxChannel _getOrCreateChannel(String name) =>
      _channels.putIfAbsent(name, () => FluxChannel._(this, name));

  // -- dispatch ---------------------------------------------------------------

  void _emitChannelEvent(SocketMessage message) {
    final channel = normalizeTopic(message.channel);
    final event = normalizeTopic(message.event);
    if (channel.isEmpty || event.isEmpty) return;
    final handlers = _channelHandlers[channel]?[event];
    if (handlers == null || handlers.isEmpty) return;
    for (final handler in List.of(handlers)) {
      if (handlers.contains(handler)) _guard(() => handler(message.data, message));
    }
  }

  void _emitMessage(SocketMessage message) {
    for (final handler in List.of(_messageHandlers)) {
      if (_messageHandlers.contains(handler)) _guard(() => handler(message));
    }
    _messages.add(message);
  }

  void _emitError(Object error) {
    for (final handler in List.of(_errorHandlers)) {
      if (_errorHandlers.contains(handler)) _guard(() => handler(error));
    }
    _errors.add(error);
  }

  void _emitState(ConnectionState state) {
    for (final handler in List.of(_stateHandlers)) {
      if (_stateHandlers.contains(handler)) _guard(() => handler(state));
    }
    _states.add(state);
  }

  /// A throwing handler is reported to the current zone (like an uncaught
  /// exception in a JS event handler) without starving the other handlers.
  static void _guard(void Function() call) {
    try {
      call();
    } catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  }
}

/// A bare topic string when the topic wants every event (the frame older
/// servers read), otherwise `{topic, events}`.
Object _toWire(String topic, List<String>? events) {
  if (events == null || (events.length == 1 && events.first == allEvents)) {
    return topic;
  }
  return {
    'topic': topic,
    'events': [...events]
  };
}

List<_ParsedSpec> _parseSpecs(List<TopicSubscription> specs) {
  final out = <_ParsedSpec>[];
  for (final spec in specs) {
    final topic = normalizeTopic(spec.topic);
    if (topic.isEmpty) continue;
    final events = <String>{
      for (final e in spec.events ?? const <String>[])
        if (normalizeTopic(e).isNotEmpty) normalizeTopic(e),
    }.toList();
    out.add(_ParsedSpec(topic, events.isEmpty ? null : events));
  }
  return out;
}

class _ParsedSpec {
  _ParsedSpec(this.topic, this.events);

  final String topic;

  /// Null for a bare topic: every event on subscribe, the whole topic on
  /// unsubscribe.
  final List<String>? events;
}

/// One dialled socket. Events from a socket that is no longer current (or
/// that was closed locally) are ignored.
class _Connection {
  _Connection(this.channel);

  final WebSocketChannel channel;
  StreamSubscription<dynamic>? subscription;
  bool open = false;
  bool closed = false;

  void close() {
    final sub = subscription;
    subscription = null;
    try {
      unawaited(channel.sink.close(_normalClosure).then<void>((_) {}, onError: (Object _) {}));
    } catch (_) {
      // Already closed.
    }
    unawaited(sub?.cancel());
  }
}

/// Convenience handle for a single channel, returned by [FluxClient.subscribe].
class FluxChannel {
  FluxChannel._(this._client, this.name);

  final FluxClient _client;

  /// The (trimmed) topic name.
  final String name;

  /// Registers [handler] for [event] on this channel; returns its remover.
  void Function() bind(String event, ChannelEventHandler handler) =>
      _client.bind(name, event, handler);

  /// Removes this channel's handlers: all, those of [event], or just [handler].
  void unbind([String? event, ChannelEventHandler? handler]) =>
      _client.unbind(name, event, handler);

  /// Drops the topic, its handlers and this handle.
  void unsubscribe() => _client.unsubscribe(name);

  /// Unbinds every handler and unsubscribes.
  void destroy() {
    _client.unbind(name);
    _client.unsubscribe(name);
  }

  /// Sends an `action` message on this channel (requires an open socket).
  void sendMessage(String event, Object? data) => _client.sendMessage(name, event, data);

  @override
  String toString() => 'FluxChannel($name)';
}
