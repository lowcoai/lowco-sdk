import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

import 'support.dart';

const _params = MessageSendParams(
  message: A2AMessage(role: 'user', parts: [TextPart(text: 'hi')], messageId: 'm1'),
);

void main() {
  test('token is required', () {
    expect(() => AgentxClient(token: ''), throwsArgumentError);
    expect(() => AgentxClient(token: '  '), throwsArgumentError);
  });

  test('constants mirror the TypeScript SDK', () {
    expect(lowcoBaseUrl, 'https://api.lowco.ai');
    expect(headerOrgId, 'X-Org-Id');
    expect(defaultManagerApiBasePath, '/v1/agentx/manager');
    expect(defaultKbApiBasePath, '/v1/agentx/kb');
    expect(defaultExecutorApiBasePath, '/v1/agentx/executors');
    expect(methodMessageSend, 'message/send');
  });

  test('sends auth, org and default headers; Authorization cannot be overridden', () async {
    final rec = Recorder((_) => envelope([]));
    await rec
        .client(defaultHeaders: {'X-Trace': 't1', 'Authorization': 'nope'})
        .manager
        .listAgents();
    final req = rec.last;
    expect(req.headers['Authorization'], 'Bearer tok_123');
    expect(req.headers[headerOrgId], 'org_1');
    expect(req.headers['X-Trace'], 't1');
    expect(req.headers.containsKey('Content-Type'), isFalse);
  });

  test('no X-Org-Id header without an orgId', () async {
    final rec = Recorder((_) => envelope([]));
    await rec.client(orgId: null).kb.listDatasets();
    expect(rec.last.headers.containsKey(headerOrgId), isFalse);
  });

  test('setOrgId and setHeader apply to every sub-client', () async {
    final rec = Recorder((req) =>
        req.url.path.endsWith('/execute') ? jsonResponse({'jsonrpc': '2.0'}) : envelope([]));
    final client = rec.client()
      ..setOrgId('org_2')
      ..setHeader('X-Extra', '1');
    await client.manager.listAgents();
    await client.kb.listDatasets();
    await client.executor.sendMessage('agent_1', _params);
    await client.executor.health();
    expect(rec.requests, hasLength(4));
    for (final req in rec.requests) {
      expect(req.headers[headerOrgId], 'org_2', reason: req.url.path);
      expect(req.headers['X-Extra'], '1', reason: req.url.path);
      expect(req.headers['Authorization'], 'Bearer tok_123');
    }

    rec.requests.clear();
    client
      ..setOrgId(null)
      ..setHeader('X-Extra', null);
    await client.manager.listModels();
    await client.kb.listKnowledgeBases();
    for (final req in rec.requests) {
      expect(req.headers.containsKey(headerOrgId), isFalse);
      expect(req.headers.containsKey('X-Extra'), isFalse);
    }

    client.setOrgId('');
    await client.manager.listModels();
    expect(rec.last.headers.containsKey(headerOrgId), isFalse);
  });

  test('base path overrides are normalised', () async {
    final rec = Recorder((req) =>
        req.url.path.endsWith('/execute') ? jsonResponse({'jsonrpc': '2.0'}) : envelope([]));
    final client = rec.client(
      managerApiBasePath: '/custom/mgr/',
      kbApiBasePath: 'kb2',
      executorApiBasePath: '//x/exec',
    );
    await client.manager.listAgents();
    expect(rec.last.url.toString(), 'https://api.lowco.ai/custom/mgr/agents');
    await client.kb.listDatasets();
    expect(rec.last.url.toString(), 'https://api.lowco.ai/kb2/datasets');
    await client.executor.sendMessage('a1', _params);
    expect(rec.last.url.toString(), 'https://api.lowco.ai/x/exec/execute');
    await client.manager.health();
    expect(rec.last.url.toString(), 'https://api.lowco.ai/health');
  });

  test('close leaves an injected client open', () async {
    var closed = false;
    final inner = _TrackingClient(() => closed = true);
    AgentxClient(token: 't', httpClient: inner).close();
    expect(closed, isFalse);
  });

  group('errors', () {
    test('use error.message and error.code from the envelope', () async {
      final rec = Recorder((_) => jsonResponse({
            'success': false,
            'error': {'code': 'AGENT_NOT_FOUND', 'message': 'agent not found'},
          }, 404));
      await expectLater(
        rec.client().manager.getAgent('missing'),
        throwsA(isA<AgentxException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'agent not found')
            .having((e) => e.code, 'code', 'AGENT_NOT_FOUND')
            .having((e) => e.body, 'body', contains('AGENT_NOT_FOUND'))
            .having((e) => e.toString(), 'toString', 'AgentxException(404): agent not found')),
      );
    });

    test('stringify a numeric error code', () async {
      final rec = Recorder((_) => jsonResponse({
            'error': {'code': 500, 'message': 'boom'}
          }, 500));
      await expectLater(rec.client().kb.listDatasets(),
          throwsA(isA<AgentxException>().having((e) => e.code, 'code', '500')));
    });

    test('blank error.message falls back to the top-level message', () async {
      final rec = Recorder((_) => jsonResponse({
            'error': {'code': 'X', 'message': '  '},
            'message': 'top-level'
          }, 400));
      await expectLater(
        rec.client().manager.listAgents(),
        throwsA(isA<AgentxException>()
            .having((e) => e.message, 'message', 'top-level')
            .having((e) => e.code, 'code', isNull)),
      );
    });

    test('non-envelope JSON, raw text and empty bodies', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'error': 'streaming not supported'}, 500))
            .client()
            .manager
            .listAgents(),
        throwsA(isA<AgentxException>()
            .having((e) => e.message, 'message', '{"error":"streaming not supported"}')),
      );
      await expectLater(
        Recorder((_) => http.Response(' upstream down ', 502)).client().kb.getDataset('d1'),
        throwsA(isA<AgentxException>()
            .having((e) => e.message, 'message', 'upstream down')
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.code, 'code', isNull)),
      );
      await expectLater(
        Recorder((_) => http.Response('', 503)).client().manager.deleteAgent('a1'),
        throwsA(isA<AgentxException>().having((e) => e.message, 'message', 'agentx: status=503')),
      );
    });

    test('health surfaces HTTP errors', () async {
      await expectLater(
        Recorder((_) => http.Response('down', 503)).client().executor.health(),
        throwsA(isA<AgentxException>().having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('invalid JSON on success', () async {
      await expectLater(
        Recorder((_) => http.Response('<html>', 200)).client().manager.getAgent('a1'),
        throwsA(isA<AgentxException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.body, 'body', '<html>')),
      );
    });

    test('timeout aborts and throws TimeoutException', () async {
      http.BaseRequest? seen;
      final client = AgentxClient(
        token: 't',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient.streaming((req, _) {
          seen = req;
          return Completer<http.StreamedResponse>().future;
        }),
      );
      await expectLater(client.manager.listAgents(), throwsA(isA<TimeoutException>()));
      final trigger = (seen! as http.Abortable).abortTrigger!;
      await trigger.timeout(const Duration(seconds: 1)); // completed by the timeout
    });
  });
}

class _TrackingClient extends http.BaseClient {
  _TrackingClient(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw UnimplementedError();

  @override
  void close() => onClose();
}
