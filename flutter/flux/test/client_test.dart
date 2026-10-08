import 'dart:async';
import 'dart:io';

import 'package:lowcoai_flux/lowcoai_flux.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flux_stub.dart';

Matcher throwsFlux(String message) =>
    throwsA(isA<FluxException>().having((e) => e.message, 'message', message));

void main() {
  group('construction', () {
    test('token and orgId are required, intervals must be positive', () {
      expect(() => FluxClient(token: ' ', orgId: 'org'), throwsFlux('token is required'));
      expect(() => FluxClient(token: 'tok', orgId: ''), throwsFlux('orgId is required'));
      expect(
        () => FluxClient(token: 'tok', orgId: 'org', heartbeatInterval: Duration.zero),
        throwsFlux('heartbeatInterval must be positive'),
      );
      expect(
        () =>
            FluxClient(token: 'tok', orgId: 'org', reconnectInterval: const Duration(seconds: -1)),
        throwsFlux('reconnectInterval must be positive'),
      );
    });

    test('clientId defaults to a random UUID v4', () {
      final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final a = FluxClient(token: 'tok', orgId: 'org');
      final b = FluxClient(token: 'tok', orgId: 'org');
      expect(a.clientId, matches(uuid));
      expect(a.clientId, isNot(b.clientId));
      expect(FluxClient(token: 'tok', orgId: 'org', clientId: 'cli-1').clientId, 'cli-1');
      expect(a.heartbeatInterval, const Duration(seconds: 5));
      expect(a.reconnectInterval, const Duration(seconds: 1));
      expect(a.isConnected, isFalse);
    });
  });

  group('connection', () {
    test('dials wss://api.lowco.ai/v1/ws with token, orgId, cli, extra params and replay=1', () async {
      final stub = await FluxStub.start();
      final client = stub.client(queryParams: {'app': 'crm', 'replay': '0'});
      client.connect();
      await stub.connections.next();

      final dialled = stub.dials.single;
      expect('${dialled.scheme}://${dialled.host}${dialled.path}', wsUrl);
      final want = {
        'token': 'tok_123',
        'orgId': 'org-1',
        'cli': client.clientId,
        'app': 'crm',
        'replay': '1',
      };
      expect(dialled.queryParameters, want);
      expect(stub.requests.single.queryParameters, want);
      expect(stub.requests.single.path, '/v1/ws');
    });

    test('connect() is a no-op while connecting or open', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final states = <ConnectionState>[];
      client.onState(states.add);
      client
        ..connect()
        ..connect();
      await until(() => client.isConnected);
      client.connect();
      expect(stub.dials, hasLength(1));
      expect(states, [ConnectionState.connected]);
    });

    test('disconnect closes, reports disconnected and stops reconnecting', () async {
      final stub = await FluxStub.start();
      final client = stub.client(reconnectInterval: const Duration(milliseconds: 5));
      final states = <ConnectionState>[];
      client.onState(states.add);
      client.connect();
      expect(await stub.opened(client), 0);

      client.disconnect();
      expect(client.isConnected, isFalse);
      expect(states, [ConnectionState.connected, ConnectionState.disconnected]);
      await stub.socketClosed.single.future.timeout(waitTimeout);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stub.dials, hasLength(1));
      expect(states, [ConnectionState.connected, ConnectionState.disconnected]);

      // connect() turns auto-reconnect back on.
      client.connect();
      expect(await stub.opened(client), 1);
    });

    test('a failed dial reports error, then retries with exponential backoff', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      final clock = Stopwatch()..start();
      final dialledAt = <Duration>[];
      final client = FluxClient(
        token: 'tok',
        orgId: 'org',
        reconnectInterval: const Duration(milliseconds: 20),
        channelFactory: (uri) {
          dialledAt.add(clock.elapsed);
          return WebSocketChannel.connect(
              uri.replace(scheme: 'ws', host: '127.0.0.1', port: deadPort));
        },
      );
      addTearDown(client.disconnect);
      final states = <ConnectionState>[];
      final errors = <Object>[];
      client
        ..onState(states.add)
        ..onError(errors.add)
        ..connect();

      await until(() => dialledAt.length >= 4);
      client.disconnect();
      expect(states.take(4), [
        ConnectionState.error,
        ConnectionState.disconnected,
        ConnectionState.error,
        ConnectionState.disconnected,
      ]);
      expect(errors.first, isA<WebSocketChannelException>());
      expect(client.isConnected, isFalse);

      const slack = Duration(milliseconds: 2);
      expect(dialledAt[1] - dialledAt[0],
          greaterThanOrEqualTo(const Duration(milliseconds: 20) - slack));
      expect(dialledAt[2] - dialledAt[1],
          greaterThanOrEqualTo(const Duration(milliseconds: 40) - slack));
      expect(dialledAt[3] - dialledAt[2],
          greaterThanOrEqualTo(const Duration(milliseconds: 80) - slack));

      final dials = dialledAt.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(dialledAt, hasLength(dials));
    });

    test('a throwing channel factory is treated like a failed dial', () async {
      final stub = await FluxStub.start();
      var calls = 0;
      final client = FluxClient(
        token: 'tok',
        orgId: 'org',
        reconnectInterval: const Duration(milliseconds: 5),
        channelFactory: (uri) {
          calls++;
          if (calls == 1) throw StateError('no network');
          return stub.dial(uri);
        },
      );
      addTearDown(client.disconnect);
      final states = <ConnectionState>[];
      final errors = <Object>[];
      client
        ..onState(states.add)
        ..onError(errors.add)
        ..connect();
      await until(() => client.isConnected);
      expect(states, [
        ConnectionState.error,
        ConnectionState.disconnected,
        ConnectionState.connected,
      ]);
      expect(errors.single, isA<StateError>());
    });
  });

  group('subscriptions', () {
    test('a subscribe made while disconnected is sent on open', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.subscribeMany([
        const TopicSubscription('agent:1'),
        const TopicSubscription('channel:s', events: ['messages.*']),
      ]);
      expect(stub.dials, isEmpty);
      client.connect();
      await stub.connections.next();
      await stub.expectFrames(['sb ["agent:1",{"topic":"channel:s","events":["messages.*"]}]']);
    });

    test('subscribe without events is bare', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.connect();
      await until(() => client.isConnected);
      client.subscribe('run:9');
      await stub.expectFrames(['sb ["run:9"]']);
      expect(client.getSubscribedTopics(), ['run:9']);
      expect(client.getSubscriptions(), [
        const TopicSubscription('run:9', events: [allEvents]),
      ]);
    });

    test('subscribing adds only the difference', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.subscribe('channel:s', events: ['messages.*']);
      client.connect();
      await stub.expectFrames(['sb [{"topic":"channel:s","events":["messages.*"]}]']);

      client.subscribe('channel:s', events: ['messages.*', 'tasks.*']);
      await stub.expectFrames(['sb [{"topic":"channel:s","events":["tasks.*"]}]']);

      // Everything already held: nothing goes out, so the next frame is run:1's.
      client.subscribe('channel:s', events: ['tasks.*']);
      client.subscribeMany([
        const TopicSubscription('channel:s', events: ['messages.*'])
      ]);
      client.subscribe('run:1');
      await stub.expectFrames(['sb ["run:1"]']);
      expect(client.getSubscriptions(), [
        const TopicSubscription('channel:s', events: ['messages.*', 'tasks.*']),
        const TopicSubscription('run:1', events: ['*']),
      ]);
    });

    test('partial unsubscribe drops only the given patterns', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.subscribeMany([
        const TopicSubscription('agent:1'),
        const TopicSubscription('channel:s', events: ['messages.*', 'tasks.*']),
      ]);
      client.connect();
      await stub.expectFrames([
        'sb ["agent:1",{"topic":"channel:s","events":["messages.*","tasks.*"]}]',
      ]);

      client.unsubscribeMany([
        const TopicSubscription('channel:s', events: ['messages.*', 'unknown.*']),
      ]);
      client.unsubscribeMany([const TopicSubscription('agent:1')]);
      await stub.expectFrames([
        'usb [{"topic":"channel:s","events":["messages.*"]}]',
        'usb ["agent:1"]',
      ]);
      expect(client.getSubscriptions(), [
        const TopicSubscription('channel:s', events: ['tasks.*']),
      ]);
    });

    test('unsubscribing the last pattern sends the bare topic', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.subscribe('channel:s', events: ['tasks.*']);
      client.connect();
      await stub.expectFrames(['sb [{"topic":"channel:s","events":["tasks.*"]}]']);

      client.unsubscribeMany([
        const TopicSubscription('channel:s', events: ['tasks.*'])
      ]);
      await stub.expectFrames(['usb ["channel:s"]']);
      expect(client.getSubscriptions(), isEmpty);
      expect(client.getSubscribedTopics(), isEmpty);
    });

    test('reconnect replays every subscription, filters included, in one frame', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final states = <ConnectionState>[];
      client.onState(states.add);
      client.subscribeMany([
        const TopicSubscription('agent:1'),
        const TopicSubscription('channel:s', events: ['messages.*']),
      ]);
      client.connect();
      final first = await stub.connections.next();
      await stub.expectFrames(['sb ["agent:1",{"topic":"channel:s","events":["messages.*"]}]']);

      client.subscribe('channel:s', events: ['tasks.*']);
      client.subscribe('run:9');
      await stub.expectFrames([
        'sb [{"topic":"channel:s","events":["tasks.*"]}]',
        'sb ["run:9"]',
      ]);

      // A dropped socket: the new one gets everything still held, filters and all.
      stub.drop(first);
      expect(await stub.connections.next(), 1);
      await stub.expectFrames([
        'sb ["agent:1",{"topic":"channel:s","events":["messages.*","tasks.*"]},"run:9"]',
      ]);
      await until(() => client.isConnected);
      expect(states, [
        ConnectionState.connected,
        ConnectionState.disconnected,
        ConnectionState.connected,
      ]);
    });

    test('unsubscribe while closed sends nothing; the next open replays what is left', () async {
      final stub = await FluxStub.start();
      final client = stub.client(reconnectInterval: const Duration(hours: 1));
      final states = <ConnectionState>[];
      client.onState(states.add);
      client.subscribeMany([
        const TopicSubscription('a'),
        const TopicSubscription('b', events: ['x.*', 'y.*']),
      ]);
      client.connect();
      expect(await stub.connections.next(), 0);
      await stub.expectFrames(['sb ["a",{"topic":"b","events":["x.*","y.*"]}]']);

      stub.drop();
      await until(() => states.contains(ConnectionState.disconnected));
      expect(client.isConnected, isFalse);
      client.unsubscribe('a');
      client.unsubscribeMany([
        const TopicSubscription('b', events: ['x.*'])
      ]);
      expect(client.getSubscriptions(), [
        const TopicSubscription('b', events: ['y.*']),
      ]);

      // connect() cancels the hour-long backoff. Had a usb gone out it would
      // come first; the first frame is the replay of what is left.
      client.connect();
      expect(await stub.connections.next(), 1);
      await stub.expectFrames(['sb [{"topic":"b","events":["y.*"]}]']);
    });

    test('topics and events are trimmed, de-duplicated and blanks dropped', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      client.subscribe(' a ', events: [' x ', 'x', '  ']);
      client.subscribe('b', events: ['   ']);
      client.subscribeMany([const TopicSubscription('  '), const TopicSubscription('c')]);
      expect(client.getSubscriptions(), [
        const TopicSubscription('a', events: ['x']),
        const TopicSubscription('b', events: ['*']),
        const TopicSubscription('c', events: ['*']),
      ]);

      expect(
          () => client.subscribe('  '), throwsFlux('at least one topic is required to subscribe'));
      expect(() => client.subscribeMany([]),
          throwsFlux('at least one topic is required to subscribe'));
      expect(() => client.unsubscribe(''),
          throwsFlux('at least one topic is required to unsubscribe'));
      expect(
        () => client.unsubscribeMany([const TopicSubscription(' ')]),
        throwsFlux('at least one topic is required to unsubscribe'),
      );

      client.connect();
      await stub.expectFrames(['sb [{"topic":"a","events":["x"]},"b","c"]']);
    });
  });

  group('channels and handlers', () {
    test('bind dispatches (data, message) on an exact trimmed match, before message handlers',
        () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final log = <String>[];
      var messages = 0;
      final channel = client.subscribe('run:1');
      final remove = channel.bind('status', (data, msg) => log.add('bind $data ${msg.event}'));
      client.bind(' run:1 ', ' other ', (data, _) => log.add('other $data'));
      client.onMessage((m) {
        messages++;
        log.add('message ${m.event}');
      });
      client.connect();
      await stub.expectFrames(['sb ["run:1"]']);

      stub
        ..send({'channel': ' run:1 ', 'event': 'status ', 'data': 'ok'})
        ..send({'channel': 'run:1', 'event': 'status.x', 'data': 'no'})
        ..send({'channel': 'run:2', 'event': 'status', 'data': 'no'});
      await until(() => messages == 3);
      expect(log, ['bind ok status ', 'message status ', 'message status.x', 'message status']);

      log.clear();
      remove();
      stub
        ..send({'channel': 'run:1', 'event': 'status', 'data': 'ok2'})
        ..send({'channel': 'run:1', 'event': 'other', 'data': 1});
      await until(() => messages == 5);
      expect(log, ['message status', 'other 1', 'message other']);

      log.clear();
      channel.unbind('other');
      stub.send({'channel': 'run:1', 'event': 'other', 'data': 2});
      await until(() => messages == 6);
      expect(log, ['message other']);

      expect(() => client.bind(' ', 'e', (_, __) {}), throwsFlux('channel is required'));
      expect(() => client.bind('c', '', (_, __) {}), throwsFlux('eventName is required'));
      expect(() => client.unbind(''), throwsFlux('channel is required'));
    });

    test('subscribe caches the handle; unsubscribe(topic) clears its handlers; destroy', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final log = <String>[];
      var messages = 0;
      client.onMessage((_) => messages++);
      client.connect();
      expect(await stub.opened(client), 0);

      final channel = client.subscribe('room:1');
      await stub.expectFrames(['sb ["room:1"]']);
      expect(channel.name, 'room:1');
      expect(identical(client.subscribe(' room:1 '), channel), isTrue);
      channel.bind('e', (data, _) => log.add('old $data'));

      client.unsubscribe('room:1');
      await stub.expectFrames(['usb ["room:1"]']);
      final again = client.subscribe('room:1');
      await stub.expectFrames(['sb ["room:1"]']);
      expect(identical(again, channel), isFalse);

      // A remover outliving an unbind must not touch later bindings.
      void first(Object? data, SocketMessage _) => log.add('first $data');
      final staleRemove = again.bind('e', first);
      again.unbind();
      again.bind('e', (data, _) => log.add('new $data'));
      staleRemove();

      stub.send({'channel': 'room:1', 'event': 'e', 'data': 1});
      await until(() => messages == 1);
      expect(log, ['new 1']);

      again.destroy();
      await stub.expectFrames(['usb ["room:1"]']);
      expect(client.getSubscribedTopics(), isEmpty);
      stub.send({'channel': 'room:1', 'event': 'e', 'data': 2});
      await until(() => messages == 2);
      expect(log, ['new 1']);
    });

    test('handler removers and broadcast streams', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final states = <ConnectionState>[];
      final events = <String?>[];
      final errors = <Object>[];
      final removeState = client.onState(states.add);
      final removeMessage = client.onMessage((m) => events.add(m.event));
      final removeError = client.onError(errors.add);
      final streamStates = <ConnectionState>[];
      final streamEvents = <String?>[];
      final streamErrors = <Object>[];
      client.states.listen(streamStates.add);
      client.messages.listen((m) => streamEvents.add(m.event));
      client.errors.listen(streamErrors.add);

      client.connect();
      expect(await stub.opened(client), 0);
      stub
        ..send({'channel': 'c', 'event': 'one'})
        ..send('oops');
      await until(() => streamEvents.length == 1 && streamErrors.length == 1);
      expect(events, ['one']);
      expect(errors, hasLength(1));

      removeState();
      removeMessage();
      removeError();
      stub
        ..send({'channel': 'c', 'event': 'two'})
        ..send('oops');
      await until(() => streamEvents.length == 2 && streamErrors.length == 2);
      expect(events, ['one']);
      expect(errors, hasLength(1));
      expect(streamEvents, ['one', 'two']);

      client.disconnect();
      await until(() => streamStates.length == 2);
      expect(states, [ConnectionState.connected]);
      expect(streamStates, [ConnectionState.connected, ConnectionState.disconnected]);
    });
  });

  group('messages', () {
    test('non-JSON frames are reported and the socket stays up', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final errors = <Object>[];
      final messages = <SocketMessage>[];
      client
        ..onError(errors.add)
        ..onMessage(messages.add)
        ..connect();
      expect(await stub.opened(client), 0);

      stub
        ..send('not json')
        ..send('[1,2]')
        ..send({
          'type': 'event',
          'channel': 'run:1',
          'event': 'done',
          'data': {'ok': true},
          'request_id': 'r1',
          'timestamp': 1700000000,
          'meta': {'seq': 3, 'run_id': 'run-1'},
        });
      await until(() => messages.isNotEmpty);
      expect(
        errors.map((e) => (e as FluxException).message),
        ['received non-JSON message: not json', 'received non-object message: [1,2]'],
      );
      final m = messages.single;
      expect(m.type, MessageType.event);
      expect(m.channel, 'run:1');
      expect(m.data, {'ok': true});
      expect(m.requestId, 'r1');
      expect(m.timestamp, 1700000000);
      expect(m.meta?.seq, 3);
      expect(m.meta?.runId, 'run-1');
      expect(client.isConnected, isTrue);
      expect(stub.dials, hasLength(1));
    });

    test('sendMessage writes an action frame; throws while closed', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      expect(
        () => client.sendMessage('room:1', 'chat', {'text': 'hi'}),
        throwsFlux('websocket is not connected'),
      );
      final channel = client.subscribe('room:1');
      client.connect();
      await stub.expectFrames(['sb ["room:1"]']);

      client.sendMessage('room:1', 'chat', {'text': 'hi'});
      channel.sendMessage('typing', null);

      final chat = (await stub.otherFrames.next()).json;
      expect(chat.keys, ['channel', 'type', 'event', 'data', 'timestamp', 'request_id']);
      expect(chat['channel'], 'room:1');
      expect(chat['type'], 'action');
      expect(chat['event'], 'chat');
      expect(chat['data'], {'text': 'hi'});
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(chat['timestamp'], isA<int>().having((t) => (t - now).abs(), 'skew', lessThan(5)));
      expect(chat['request_id'], isA<String>().having((id) => id.length, 'length', greaterThan(8)));

      final typing = (await stub.otherFrames.next()).json;
      expect(typing['event'], 'typing');
      expect(typing.containsKey('data'), isTrue);
      expect(typing['data'], isNull);
      expect(typing['request_id'], isNot(chat['request_id']));

      client.disconnect();
      expect(() => channel.sendMessage('chat', 1), throwsFlux('websocket is not connected'));
    });
  });

  group('heartbeat', () {
    test('pings flux:health_check with the TS sequence, reset per socket', () async {
      final stub = await FluxStub.start();
      final client = stub.client(heartbeatInterval: const Duration(milliseconds: 25));
      client.connect();

      final first = await stub.pings.next();
      expect(first.json.keys, ['channel', 'type', 'event', 'data', 'timestamp', 'request_id']);
      expect(first.json['channel'], 'flux:health_check');
      expect(first.json['type'], 'action');
      expect(first.json['event'], 'pi');
      expect(first.json['timestamp'], isA<int>());

      // On open the current sequence goes out, then the counter restarts at 1.
      final seq = [first.data];
      for (var i = 0; i < 3; i++) {
        seq.add((await stub.pings.next()).data);
      }
      expect(seq, ['1', '1', '2', '3']);

      stub.drop(0);
      Frame next;
      do {
        next = await stub.pings.next();
      } while (next.socket == 0);
      expect(int.parse(next.data as String), greaterThanOrEqualTo(4));
      expect((await stub.pings.next()).data, '1');
      expect((await stub.pings.next()).data, '2');
    });

    test('a matching pong (string or number) is delivered as a message', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final errors = <Object>[];
      final pongs = <Object?>[];
      client
        ..onError(errors.add)
        ..onMessage((m) {
          if (m.event == 'pong') pongs.add(m.data);
        })
        ..connect();
      expect((await stub.pings.next()).data, '1');

      stub
        ..send({'channel': 'flux:health_check', 'event': 'pong', 'data': '1'})
        ..send({'channel': 'flux:health_check', 'event': 'pong', 'data': 1});
      await until(() => pongs.length == 2);
      expect(pongs, ['1', 1]);
      expect(errors, isEmpty);
      expect(client.isConnected, isTrue);
      expect(stub.dials, hasLength(1));
    });

    test('a pong out of sync reports an error and reconnects', () async {
      final stub = await FluxStub.start();
      final client = stub.client();
      final states = <ConnectionState>[];
      final errors = <Object>[];
      final pongs = <Object?>[];
      client
        ..onState(states.add)
        ..onError(errors.add)
        ..onMessage((m) => pongs.add(m.data))
        ..subscribe('run:1');
      client.connect();
      expect(await stub.connections.next(), 0);
      await stub.expectFrames(['sb ["run:1"]']);

      stub.send({'channel': 'flux:health_check', 'event': 'pong', 'data': '999'});
      expect(await stub.connections.next(), 1);
      await stub.expectFrames(['sb ["run:1"]']);
      await until(() => client.isConnected);

      expect(errors.map((e) => (e as FluxException).message), ['pong out of sync, reconnecting']);
      expect(pongs, isEmpty);
      expect(states, [
        ConnectionState.connected,
        ConnectionState.disconnected,
        ConnectionState.connected,
      ]);
      await stub.socketClosed.first.future.timeout(waitTimeout);
    });
  });

  group('backoff', () {
    test('an open socket does not reset the backoff; the first good pong does', () async {
      final stub = await FluxStub.start();
      final client = stub.client(reconnectInterval: const Duration(milliseconds: 100));
      final pongs = <Object?>[];
      client
        ..onMessage((m) {
          if (m.event == 'pong') pongs.add(m.data);
        })
        ..connect();

      // Two sockets that open and drop before any pong: 100 ms, then 200 ms.
      expect(await stub.opened(client), 0);
      stub.drop();
      expect(await stub.opened(client), 1);
      stub.drop();
      expect(await stub.opened(client), 2);

      // The third answers its ping, so the next drop starts over at 100 ms.
      await stub.pong();
      await until(() => pongs.isNotEmpty);
      stub.drop();
      expect(await stub.opened(client), 3);

      final at = stub.dialledAt;
      const slack = Duration(milliseconds: 2);
      expect(at[1] - at[0], greaterThanOrEqualTo(const Duration(milliseconds: 100) - slack));
      expect(at[2] - at[1], greaterThanOrEqualTo(const Duration(milliseconds: 200) - slack));
      // 400 ms had the backoff kept growing.
      expect(at[3] - at[2], greaterThanOrEqualTo(const Duration(milliseconds: 100) - slack));
      expect(at[3] - at[2], lessThan(const Duration(milliseconds: 300)));
    });
  });

  group('auth rejection', () {
    test('a token rejected after the upgrade keeps growing the backoff', () async {
      final stub = await FluxStub.start();
      // Every token is rejected, but each attempt gets a new one, so the
      // client keeps retrying: it must not reset to 20 ms on each open.
      stub.rejectedTokens.addAll([for (var i = 1; i <= 10; i++) 'tok_$i']);
      var calls = 0;
      final client = stub.client(
        reconnectInterval: const Duration(milliseconds: 20),
        tokenProvider: () => 'tok_${++calls}',
      );
      final errors = <Object>[];
      client
        ..onError(errors.add)
        ..connect();

      // Four sockets the server upgraded, then rejected.
      await until(() => stub.sockets.length >= 4);
      client.disconnect();
      // The token asked for after a rejection is the one retried with.
      expect(stub.tokens.take(4), ['tok_1', 'tok_2', 'tok_3', 'tok_4']);
      expect(errors.take(3), everyElement(isA<FluxUnauthorizedException>()));

      final at = stub.dialledAt;
      const slack = Duration(milliseconds: 2);
      expect(at[1] - at[0], greaterThanOrEqualTo(const Duration(milliseconds: 20) - slack));
      expect(at[2] - at[1], greaterThanOrEqualTo(const Duration(milliseconds: 40) - slack));
      expect(at[3] - at[2], greaterThanOrEqualTo(const Duration(milliseconds: 80) - slack));
    });

    test('a rejected, unchanged token stops reconnecting', () async {
      final stub = await FluxStub.start();
      stub.rejectedTokens.add('tok_123');
      final client = stub.client(reconnectInterval: const Duration(milliseconds: 5));
      final errors = <Object>[];
      final messages = <SocketMessage>[];
      final states = <ConnectionState>[];
      client
        ..onError(errors.add)
        ..onMessage(messages.add)
        ..onState(states.add)
        ..connect();

      expect(await stub.connections.next(), 0);
      await stub.socketClosed.single.future.timeout(waitTimeout);
      await until(() => states.contains(ConnectionState.disconnected));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stub.dials, hasLength(1));
      expect(client.isConnected, isFalse);
      expect(errors.single, isA<FluxUnauthorizedException>());
      expect(errors.single, isA<FluxException>());
      // The server's frame is still delivered as a message.
      expect(messages.single.channel, 'flux:error');
      expect(messages.single.event, 'Unauthorized');
      expect(states.last, ConnectionState.disconnected);

      // connect() tries again even with the same token.
      client.connect();
      expect(await stub.connections.next(), 1);
      await until(() => errors.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stub.dials, hasLength(2));
    });

    test('close code 1008 alone, or the frame alone, is a rejection', () async {
      for (final (frame, close) in [(false, true), (true, false)]) {
        final stub = await FluxStub.start();
        stub
          ..rejectedTokens.add('tok_123')
          ..rejectWithFrame = frame
          ..rejectWithClose = close;
        final client = stub.client(reconnectInterval: const Duration(milliseconds: 5));
        final errors = <Object>[];
        client
          ..onError(errors.add)
          ..connect();

        expect(await stub.connections.next(), 0);
        // Without the close frame the client closes the socket itself.
        await stub.socketClosed.single.future.timeout(waitTimeout);
        await until(() => errors.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(errors.single, isA<FluxUnauthorizedException>(), reason: 'frame=$frame');
        expect(stub.dials, hasLength(1), reason: 'frame=$frame');
      }
    });

    test('a tokenProvider returning a new token reconnects with it', () async {
      final stub = await FluxStub.start();
      stub.rejectedTokens.add('tok_old');
      var calls = 0;
      final client = stub.client(
        token: 'tok_stored',
        tokenProvider: () async => ++calls == 1 ? 'tok_old' : 'tok_new',
      );
      final errors = <Object>[];
      client
        ..onError(errors.add)
        ..connect();

      expect(await stub.connections.next(), 0);
      expect(await stub.opened(client), 1);
      expect(stub.tokens, ['tok_old', 'tok_new']);
      expect(calls, 2, reason: 'asked once per attempt, the rejection included');
      expect(errors.single, isA<FluxUnauthorizedException>());
    });

    test('a throwing or blank tokenProvider falls back to the stored token', () async {
      final stub = await FluxStub.start();
      final answers = <Object?>[StateError('offline'), null, '  ', 'tok_p'];
      var calls = 0;
      final client = stub.client(
        token: 'tok_stored',
        reconnectInterval: const Duration(milliseconds: 5),
        tokenProvider: () async {
          final answer = answers[calls++ % answers.length];
          if (answer is Error) throw answer;
          return answer as String?;
        },
      );
      final errors = <Object>[];
      client
        ..onError(errors.add)
        ..connect();

      for (var i = 0; i < 4; i++) {
        expect(await stub.opened(client), i);
        stub.drop();
      }
      expect(await stub.opened(client), 4);
      // A token from the provider becomes the stored one.
      expect(stub.tokens, ['tok_stored', 'tok_stored', 'tok_stored', 'tok_p', 'tok_p']);
      expect(errors.whereType<StateError>(), hasLength(2));
    });

    test('setToken resumes a stopped client with a different token', () async {
      final stub = await FluxStub.start();
      stub.rejectedTokens.add('tok_123');
      final client = stub.client(reconnectInterval: const Duration(milliseconds: 5));
      final errors = <Object>[];
      client
        ..onError(errors.add)
        ..connect();
      expect(await stub.connections.next(), 0);
      await until(() => errors.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(stub.dials, hasLength(1));

      // The rejected token again, or a blank one: still stopped.
      client
        ..setToken('tok_123')
        ..setToken('   ');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(stub.dials, hasLength(1));

      client.setToken('tok_fresh');
      expect(stub.dials, hasLength(2), reason: 'reconnects at once');
      expect(await stub.opened(client), 1);
      expect(stub.tokens, ['tok_123', 'tok_fresh']);

      // While connected, setToken only changes the token of the next attempt.
      client.setToken('tok_next');
      stub.drop();
      expect(await stub.opened(client), 2);
      expect(stub.tokens.last, 'tok_next');
    });

    test('setToken after disconnect() does not reconnect', () async {
      final stub = await FluxStub.start();
      stub.rejectedTokens.add('tok_123');
      final client = stub.client();
      final errors = <Object>[];
      client
        ..onError(errors.add)
        ..connect();
      await until(() => errors.isNotEmpty);
      client
        ..disconnect()
        ..setToken('tok_fresh');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stub.dials, hasLength(1));
    });

    test('connect() while the provider is pending is a no-op; disconnect() wins', () async {
      final stub = await FluxStub.start();
      final pending = <Completer<String?>>[];
      final client = stub.client(tokenProvider: () {
        final c = Completer<String?>();
        pending.add(c);
        return c.future;
      });

      client
        ..connect()
        ..connect();
      expect(pending, hasLength(1));
      client.disconnect();
      pending.single.complete('tok_late');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stub.dials, isEmpty);

      // A connect() after the disconnect() asks again; the stale answer is dropped.
      client.connect();
      expect(pending, hasLength(2));
      pending.last.complete('tok_now');
      expect(await stub.opened(client), 0);
      expect(stub.tokens, ['tok_now']);
    });
  });

  group('singleton', () {
    test('getInstance creates and connects once; destroyInstance tears it down', () async {
      final stub = await FluxStub.start();
      addTearDown(FluxClient.destroyInstance);

      expect(
        () => FluxClient.getInstance(),
        throwsFlux('FluxClient.getInstance: token and orgId are required on first call'),
      );
      expect(() => FluxClient.getInstance(token: 'tok'), throwsFlux('orgId is required'));

      final client = FluxClient.getInstance(
        token: 'tok',
        orgId: 'org',
        reconnectInterval: const Duration(milliseconds: 5),
        channelFactory: stub.dial,
      );
      await stub.connections.next();
      await until(() => client.isConnected);
      expect(identical(FluxClient.getInstance(), client), isTrue);
      expect(identical(FluxClient.getInstance(token: 'x', orgId: 'y'), client), isTrue);

      FluxClient.destroyInstance();
      expect(client.isConnected, isFalse);
      expect(() => FluxClient.getInstance(), throwsA(isA<FluxException>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stub.dials, hasLength(1));
    });
  });
}
