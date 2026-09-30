import 'json.dart';

/// The high-level kind of a [SocketMessage] (`type` on the wire).
abstract final class MessageType {
  static const action = 'action';
  static const event = 'event';
  static const system = 'system';
  static const error = 'error';
  static const ack = 'ack';

  static const values = [action, event, system, error, ack];
}

/// Reserved wire-level event names of the flux protocol.
abstract final class SocketEvent {
  static const ping = 'pi';
  static const pong = 'po';
  static const subscribe = 'sb';
  static const unsubscribe = 'usb';
  static const message = 'm';
  static const reply = 'reply';
}

/// The event pattern that matches every event on a topic.
const allEvents = '*';

/// Connection state reported through `FluxClient.onState` and
/// `FluxClient.states`.
enum ConnectionState { connected, disconnected, error }

/// Alias of [ConnectionState] for Flutter apps, where `package:flutter/widgets.dart`
/// also exports a `ConnectionState` (the `AsyncSnapshot` one).
typedef FluxConnectionState = ConnectionState;

/// Called for every received message.
typedef MessageHandler = void Function(SocketMessage message);

/// Called for transient socket errors (a [FluxException] or the socket's own error).
typedef ErrorHandler = void Function(Object error);

/// Called on every connection state change.
typedef StateHandler = void Function(ConnectionState state);

/// Called for a message whose channel and event match a `FluxClient.bind`.
typedef ChannelEventHandler = void Function(Object? data, SocketMessage message);

/// Optional metadata transmitted alongside a message.
class MessageMeta {
  const MessageMeta({this.seq, this.runId});

  factory MessageMeta.fromJson(Map<String, dynamic> json) =>
      MessageMeta(seq: readInt(json['seq']), runId: readString(json['run_id']));

  final int? seq;

  /// `run_id` on the wire.
  final String? runId;

  Map<String, dynamic> toJson() => {
        if (seq != null) 'seq': seq,
        if (runId != null) 'run_id': runId,
      };
}

/// The JSON envelope exchanged with the flux server.
class SocketMessage {
  const SocketMessage({
    this.type,
    this.channel,
    this.event,
    this.data,
    this.requestId,
    this.timestamp,
    this.meta,
  });

  factory SocketMessage.fromJson(Map<String, dynamic> json) => SocketMessage(
        type: readString(json['type']),
        channel: readString(json['channel']),
        event: readString(json['event']),
        data: json['data'],
        requestId: readString(json['request_id']),
        timestamp: readInt(json['timestamp']),
        meta: readObject(json['meta'], MessageMeta.fromJson),
      );

  /// One of [MessageType]: `action`, `event`, `system`, `error` or `ack`.
  final String? type;
  final String? channel;
  final String? event;

  /// Free-form JSON payload.
  final Object? data;

  /// `request_id` on the wire.
  final String? requestId;

  /// Seconds since the Unix epoch.
  final int? timestamp;
  final MessageMeta? meta;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (channel != null) 'channel': channel,
        if (event != null) 'event': event,
        if (data != null) 'data': data,
        if (requestId != null) 'request_id': requestId,
        if (timestamp != null) 'timestamp': timestamp,
        if (meta != null) 'meta': meta!.toJson(),
      };

  @override
  String toString() => 'SocketMessage(channel: $channel, event: $event, type: $type, data: $data)';
}

/// A topic, narrowed to the events wanted from it.
///
/// The server delivers only events matching one of the patterns: `*` alone is
/// every event, otherwise patterns are compared token by token on `.` with `*`
/// matching exactly one token (`messages.*`, `*.delete`, `messages.insert`).
/// A null or empty [events] means every event (subscribe) or the whole topic
/// (unsubscribe).
class TopicSubscription {
  const TopicSubscription(this.topic, {this.events});

  factory TopicSubscription.fromJson(Map<String, dynamic> json) => TopicSubscription(
        readString(json['topic']) ?? '',
        events: readStringList(json['events']),
      );

  final String topic;
  final List<String>? events;

  Map<String, dynamic> toJson() => {
        'topic': topic,
        if (events != null) 'events': events,
      };

  @override
  bool operator ==(Object other) {
    if (other is! TopicSubscription || other.topic != topic) return false;
    final a = events;
    final b = other.events;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(topic, events == null ? null : Object.hashAll(events!));

  @override
  String toString() =>
      events == null ? 'TopicSubscription($topic)' : 'TopicSubscription($topic, $events)';
}
