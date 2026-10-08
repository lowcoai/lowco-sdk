import 'package:lowcoai_flux/lowcoai_flux.dart';
import 'package:test/test.dart';

void main() {
  test('wire constants', () {
    expect(wsUrl, 'wss://api.lowco.ai/v1/ws');
    expect(allEvents, '*');
    expect(MessageType.values, ['action', 'event', 'system', 'error', 'ack']);
    expect(
      [
        SocketEvent.ping,
        SocketEvent.pong,
        SocketEvent.subscribe,
        SocketEvent.unsubscribe,
        SocketEvent.message,
        SocketEvent.reply,
      ],
      ['pi', 'po', 'sb', 'usb', 'm', 'reply'],
    );
    expect(ConnectionState.values.map((s) => s.name), ['connected', 'disconnected', 'error']);
    const FluxConnectionState alias = ConnectionState.error;
    expect(alias, ConnectionState.error);
  });

  test('buildWebSocketUrl encodes params and lets extras override in place', () {
    expect(
      buildWebSocketUrl('t k&1', 'org_1', 'cli-1', {'app': 'crm'}),
      'wss://api.lowco.ai/v1/ws?token=t+k%261&orgId=org_1&cli=cli-1&app=crm',
    );
    expect(
      buildWebSocketUrl('tok', 'org', 'cli', {'token': 'other', 'replay': '1'}),
      'wss://api.lowco.ai/v1/ws?token=other&orgId=org&cli=cli&replay=1',
    );
    expect(
        buildWebSocketUrl('tok', 'org', 'cli'), 'wss://api.lowco.ai/v1/ws?token=tok&orgId=org&cli=cli');
  });

  test('generateClientId returns distinct UUID v4 values', () {
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final ids = List.generate(50, (_) => generateClientId());
    expect(ids, everyElement(matches(uuid)));
    expect(ids.toSet(), hasLength(50));
  });

  test('SocketMessage maps request_id / run_id, reads leniently and omits nulls', () {
    final m = SocketMessage.fromJson({
      'type': 'ack',
      'channel': 'run:1',
      'event': 'status',
      'data': [1, 'two'],
      'request_id': 'r1',
      'timestamp': '1700000000',
      'meta': {'seq': 4.0, 'run_id': 'run-1'},
    });
    expect(m.type, MessageType.ack);
    expect(m.data, [1, 'two']);
    expect(m.requestId, 'r1');
    expect(m.timestamp, 1700000000);
    expect(m.meta?.seq, 4);
    expect(m.meta?.runId, 'run-1');
    expect(m.toJson(), {
      'type': 'ack',
      'channel': 'run:1',
      'event': 'status',
      'data': [1, 'two'],
      'request_id': 'r1',
      'timestamp': 1700000000,
      'meta': {'seq': 4, 'run_id': 'run-1'},
    });

    expect(SocketMessage.fromJson(const {}).toJson(), isEmpty);
    expect(const SocketMessage(channel: 'c', meta: MessageMeta()).toJson(),
        {'channel': 'c', 'meta': {}});
  });

  test('TopicSubscription equality and JSON', () {
    expect(const TopicSubscription('a', events: ['x', 'y']),
        const TopicSubscription('a', events: ['x', 'y']));
    expect(
      const TopicSubscription('a', events: ['x', 'y']).hashCode,
      const TopicSubscription('a', events: ['x', 'y']).hashCode,
    );
    expect(const TopicSubscription('a', events: ['x']),
        isNot(const TopicSubscription('a', events: ['y'])));
    expect(const TopicSubscription('a'), isNot(const TopicSubscription('a', events: ['*'])));
    expect(const TopicSubscription('a').toJson(), {'topic': 'a'});
    expect(const TopicSubscription('a', events: ['x']).toJson(), {
      'topic': 'a',
      'events': ['x'],
    });
    expect(
      TopicSubscription.fromJson({
        'topic': 'a',
        'events': ['x'],
      }),
      const TopicSubscription('a', events: ['x']),
    );
  });

  test('FluxException', () {
    const e = FluxException('boom');
    expect(e.message, 'boom');
    expect('$e', 'FluxException: boom');
  });
}
