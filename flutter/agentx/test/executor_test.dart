import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

import 'support.dart';

const _params = MessageSendParams(
  message: A2AMessage(
    role: 'user',
    parts: [TextPart(text: 'hi')],
    messageId: 'm1',
    contextId: 'ctx1',
  ),
  configuration: MessageSendConfiguration(blocking: true),
  chatType: 'chat',
);

const _expectedRequest = {
  'jsonrpc': '2.0',
  'method': 'message/send',
  'params': {
    'message': {
      'role': 'user',
      'parts': [
        {'kind': 'text', 'text': 'hi'}
      ],
      'messageId': 'm1',
      'kind': 'message',
      'contextId': 'ctx1',
    },
    'configuration': {'blocking': true},
    'chatType': 'chat',
  },
  'id': 'agent_1',
};

const _reply = {
  'kind': 'message',
  'role': 'assistant',
  'messageId': 'r1',
  'parts': [
    {'kind': 'text', 'text': 'héllo 👋'}
  ],
};

/// The body of an SSE reply with every awkward feature the parser handles:
/// a heartbeat comment, `event:`/`id:`/`retry:` fields, CRLF line endings,
/// multi-line data, an event without data and a trailing event without a
/// terminating blank line.
final _sse = ': ping\n\n'
    'event: message\r\ndata: ${jsonEncode(_reply)}\r\n\r\n'
    'id: 2\ndata: line one\ndata:line two\n\n'
    'retry: 1000\n\n'
    'data: trailing';

final _expectedEvents = [jsonEncode(_reply), 'line one\nline two', 'trailing'];

/// A client whose `/execute` reply streams [body] (or answers [status]).
class _Sse {
  _Sse(Stream<List<int>> Function(http.BaseRequest req) body,
      {int status = 200, Duration? timeout = const Duration(seconds: 30)}) {
    client = AgentxClient(
      token: 'tok_123',
      orgId: 'org_1',
      timeout: timeout,
      httpClient: MockClient.streaming((req, bodyStream) async {
        requests.add(req);
        bodies.add(await bodyStream.bytesToString());
        return http.StreamedResponse(body(req), status,
            headers: {'content-type': 'text/event-stream'});
      }),
    );
  }

  late final AgentxClient client;
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];

  Future<void> get abortTrigger => (requests.single as http.Abortable).abortTrigger!;
}

int _indexOfBytes(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

List<List<int>> _split(List<int> bytes, int size) => [
      for (var i = 0; i < bytes.length; i += size)
        bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size)
    ];

void main() {
  group('sendMessage', () {
    test('posts a JSON-RPC message/send request and returns the raw response', () async {
      final rec =
          Recorder((_) => jsonResponse({'jsonrpc': '2.0', 'id': 'agent_1', 'result': _reply}));
      final resp = await rec.client().executor.sendMessage('agent_1', _params);
      expect(rec.last.method, 'POST');
      expect(rec.last.url.toString(), 'https://api.lowco.ai/v1/agentx/executors/execute');
      expect(rec.last.headers['Accept'], 'application/json');
      expect(rec.last.headers['Content-Type'], startsWith('application/json'));
      expect(rec.lastJson, _expectedRequest);

      expect(resp.jsonrpc, '2.0');
      expect(resp.id, 'agent_1');
      expect(resp.error, isNull);
      final msg = A2AMessage.fromJson(resp.result! as Map<String, dynamic>);
      expect(msg.role, 'assistant');
      expect((msg.parts.single as TextPart).text, 'héllo 👋');
    });

    test('is not enveloped', () async {
      final rec = Recorder((_) => jsonResponse({
            'jsonrpc': '2.0',
            'id': 7,
            'result': {'data': 'kept'}
          }));
      final resp = await rec.client().executor.sendMessage('agent_1', _params);
      expect(resp.result, {'data': 'kept'});
      expect(resp.id, 7);
    });

    test('surfaces JSON-RPC errors in the response', () async {
      final rec = Recorder((_) => jsonResponse({
            'jsonrpc': '2.0',
            'id': 'agent_1',
            'error': {
              'code': -32601,
              'message': 'Method not found',
              'data': {'method': 'x'}
            },
          }));
      final resp = await rec.client().executor.sendMessage('agent_1', _params);
      expect(resp.result, isNull);
      expect(resp.error!.code, JSONRPCErrorCodes.methodNotFound);
      expect(resp.error!.message, 'Method not found');
      expect(resp.error!.data, {'method': 'x'});
    });

    test('an empty reply yields a bare response carrying the agent id', () async {
      for (final reply in [http.Response('', 204), http.Response('  ', 200)]) {
        final resp = await Recorder((_) => reply).client().executor.sendMessage('agent_1', _params);
        expect(resp.jsonrpc, '2.0');
        expect(resp.id, 'agent_1');
        expect(resp.result, isNull);
        expect(resp.error, isNull);
      }
    });

    test('HTTP errors throw AgentxException', () async {
      await expectLater(
        Recorder((_) => jsonResponse({
              'error': {'code': 'QUOTA_EXCEEDED', 'message': 'out of credits'}
            }, 402)).client().executor.sendMessage('agent_1', _params),
        throwsA(isA<AgentxException>()
            .having((e) => e.statusCode, 'statusCode', 402)
            .having((e) => e.code, 'code', 'QUOTA_EXCEEDED')
            .having((e) => e.message, 'message', 'out of credits')),
      );
    });
  });

  group('streamMessage', () {
    test('sends the same JSON-RPC body with Accept: text/event-stream', () async {
      final sse = _Sse((_) => Stream.value(utf8.encode(_sse)));
      final events = await sse.client.executor.streamMessage('agent_1', _params).toList();
      expect(events.map((e) => e.data), _expectedEvents);

      final req = sse.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://api.lowco.ai/v1/agentx/executors/execute');
      expect(req.headers['Accept'], 'text/event-stream');
      expect(req.headers['Authorization'], 'Bearer tok_123');
      expect(req.headers[headerOrgId], 'org_1');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sse.bodies.single), _expectedRequest);

      final msg = tryParseMessage(events.first)!;
      expect(msg.messageId, 'r1');
      expect((msg.parts.single as TextPart).text, 'héllo 👋');
      expect(tryParseMessage(events[1]), isNull);
    });

    test('is lazy: nothing is sent until the stream is listened to', () async {
      final sse = _Sse((_) => Stream.value(utf8.encode(_sse)));
      sse.client.executor.streamMessage('agent_1', _params);
      await Future<void>.delayed(Duration.zero);
      expect(sse.requests, isEmpty);
    });

    test('handles every chunk split (mid-event, mid-CRLF, mid-UTF-8 sequence)', () async {
      final bytes = utf8.encode(_sse);
      for (var size = 1; size <= bytes.length; size++) {
        final sse = _Sse((_) => Stream.fromIterable(_split(bytes, size)));
        final events = await sse.client.executor.streamMessage('agent_1', _params).toList();
        expect(events.map((e) => e.data), _expectedEvents, reason: 'chunk size $size');
      }
    });

    test('splits inside a four-byte emoji and between CR and LF', () async {
      final bytes = utf8.encode(_sse);
      final emoji = _indexOfBytes(bytes, utf8.encode('👋'));
      final crlf = _indexOfBytes(bytes, [13, 10, 13, 10]);
      final data = _indexOfBytes(bytes, utf8.encode('data: line one'));
      expect([emoji, crlf, data], everyElement(greaterThan(0)));
      // Inside the emoji twice, between each CR and LF, inside "data:" and
      // inside the trailing event.
      final cuts = [emoji + 1, emoji + 3, crlf + 1, crlf + 3, data + 2, bytes.length - 3]..sort();
      final chunks = <List<int>>[];
      var from = 0;
      for (final cut in cuts) {
        chunks.add(bytes.sublist(from, cut));
        from = cut;
      }
      chunks.add(bytes.sublist(from));
      final sse = _Sse((_) => Stream.fromIterable(chunks));
      final events = await sse.client.executor.streamMessage('agent_1', _params).toList();
      expect(events.map((e) => e.data), _expectedEvents);
    });

    test('has no timeout', () async {
      final sse = _Sse(
        (_) async* {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          yield utf8.encode('data: late\n\n');
        },
        timeout: const Duration(milliseconds: 10),
      );
      final events = await sse.client.executor.streamMessage('agent_1', _params).toList();
      expect(events.single.data, 'late');
    });

    test('a non-2xx reply is a stream error', () async {
      final sse = _Sse(
        (_) => Stream.value(utf8.encode(jsonEncode({
          'error': {'code': 'FORBIDDEN', 'message': 'org mismatch'}
        }))),
        status: 403,
      );
      await expectLater(
        sse.client.executor.streamMessage('agent_1', _params).toList(),
        throwsA(isA<AgentxException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'org mismatch')
            .having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('a transport error mid-stream is forwarded', () async {
      final sse = _Sse((_) async* {
        yield utf8.encode('data: one\n\n');
        throw http.ClientException('connection reset');
      });
      final seen = <String>[];
      await expectLater(
        sse.client.executor
            .streamMessage('agent_1', _params)
            .map((e) => seen.add(e.data))
            .drain<void>(),
        throwsA(isA<http.ClientException>()),
      );
      expect(seen, ['one']);
    });

    test('breaking out of await-for aborts the request', () async {
      final body = StreamController<List<int>>();
      final sse = _Sse((_) => body.stream);
      body.add(utf8.encode('data: first\n\n'));
      await for (final ev in sse.client.executor.streamMessage('agent_1', _params)) {
        expect(ev.data, 'first');
        break;
      }
      await sse.abortTrigger.timeout(const Duration(seconds: 1));
      expect(body.hasListener, isFalse);
    });

    test('cancelling while the server is silent aborts immediately', () async {
      // Behave like a real client: an abort injects RequestAbortedException
      // into the body and closes it.
      final body = StreamController<List<int>>();
      final sse = _Sse((req) {
        (req as http.Abortable).abortTrigger!.then((_) {
          body
            ..addError(http.RequestAbortedException(req.url))
            ..close();
        });
        return body.stream;
      });
      final got = <String>[];
      final sub = sse.client.executor.streamMessage('agent_1', _params).listen(
            (ev) => got.add(ev.data),
            onError: (Object e) => fail('unexpected error $e'),
          );
      body.add(utf8.encode('data: first\n\n'));
      await pumpEventQueue();
      expect(got, ['first']);

      var aborted = false;
      unawaited(sse.abortTrigger.then((_) => aborted = true));
      await sub.cancel();
      await pumpEventQueue();
      expect(aborted, isTrue);
      expect(body.hasListener, isFalse);
    });
  });

  test('executor health hits the host root', () async {
    final rec = Recorder((_) => http.Response('OK', 200));
    await rec.client().executor.health();
    expect(rec.last.method, 'GET');
    expect(rec.last.url.toString(), 'https://api.lowco.ai/health');
  });
}
