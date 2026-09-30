import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_workflow/lowcoai_workflow.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('token is required', () {
    expect(() => WorkflowClient(token: ''), throwsArgumentError);
    expect(() => WorkflowClient(token: '  '), throwsArgumentError);
    expect(() => WorkflowHttpClient(token: ''), throwsArgumentError);
  });

  group('headers', () {
    test('auth, org, accept and extra headers; no content type without a body', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'X-Trace': 't1'}).workflows.list();
      final req = rec.last;
      expect(req.url.toString(), 'https://api.lowco.ai/v1/wf/workflows');
      expect(req.headers['Authorization'], 'Bearer tok_123');
      expect(req.headers[headerOrgId], 'org_1');
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['X-Trace'], 't1');
      expect(req.headers.containsKey('Content-Type'), isFalse);
      expect(req.body, isEmpty);
    });

    test('content type only when a body is sent, and it wins over extra headers', () async {
      final rec = Recorder((_) => envelope({}));
      await rec.client(headers: {'Content-Type': 'text/plain'}).humanTasks.complete('h1', 'ok');
      expect(rec.last.headers['Content-Type'], startsWith('application/json'));
      expect(rec.lastJson, {'action': 'ok'});
    });

    test('an Authorization header in headers takes precedence over the token', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'Authorization': 'Basic abc'}).workflows.list();
      expect(rec.last.headers['Authorization'], 'Basic abc');

      // Header names are case-insensitive (the TS SDK would send both).
      await rec.client(headers: {'authorization': 'Bearer other'}).workflows.list();
      expect(rec.last.headers['Authorization'], 'Bearer other');
      expect(rec.last.headers.keys.where((k) => k.toLowerCase() == 'authorization'), hasLength(1));
    });

    test('an X-Org-Id header in headers takes precedence over orgId', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'X-Org-Id': 'org_from_headers'}).workflows.list();
      expect(rec.last.headers[headerOrgId], 'org_from_headers');

      await rec.client(headers: {'x-org-id': 'org_lower'}).workflows.list();
      expect(rec.last.headers[headerOrgId], 'org_lower');
    });

    test('no X-Org-Id without an orgId', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(orgId: null).workflows.list();
      expect(rec.last.headers.containsKey(headerOrgId), isFalse);
      await rec.client(orgId: '').workflows.list();
      expect(rec.last.headers.containsKey(headerOrgId), isFalse);
    });

    test('extra headers may override Accept (TS order)', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'Accept': 'application/x-ndjson'}).workflows.list();
      expect(rec.last.headers['Accept'], 'application/x-ndjson');
    });

    test('per-request headers on the transport', () async {
      final requests = <http.Request>[];
      final transport = WorkflowHttpClient(
        token: 'tok',
        orgId: 'org_1',
        headers: {'X-A': 'client'},
        httpClient: MockClient((req) async {
          requests.add(req);
          return envelope({'ok': true});
        }),
      );
      final res = await transport.request('GET', 'v1/wf/custom',
          query: {'a': 1, 'b': null}, headers: {'X-A': 'request', 'X-Org-Id': 'org_2'});
      expect(res, {'ok': true});
      expect(requests.single.url.toString(), 'https://api.lowco.ai/v1/wf/custom?a=1');
      expect(requests.single.headers['X-A'], 'request');
      expect(requests.single.headers[headerOrgId], 'org_2');
    });
  });

  group('responses', () {
    test('unwraps the data envelope', () async {
      final rec = Recorder((_) => envelope({'id': 'w1', 'name': 'Flow'}));
      final wf = await rec.client().workflows.getById('w1');
      expect(wf.id, 'w1');
      expect(wf.name, 'Flow');
    });

    test('payloads without a data key are returned as-is', () async {
      final rec = Recorder((_) => jsonResponse({'id': 'w1', 'name': 'Flow'}, 200));
      expect((await rec.client().workflows.getById('w1')).name, 'Flow');

      final arr = Recorder((_) => jsonResponse([
            {'id': 'w1', 'name': 'a'}
          ], 200));
      expect((await arr.client().workflows.list()).single.id, 'w1');

      final num = Recorder((_) => jsonResponse(42, 200));
      expect(await num.client().workflows.count(), 42);
    });

    test('count returns the unwrapped number or object', () async {
      expect(await Recorder((_) => envelope(7)).client().executions.count(), 7);
      expect(
          await Recorder((_) => envelope({'total': 7})).client().activities.count(), {'total': 7});
    });

    test('an empty body is null and decodes leniently', () async {
      final rec = Recorder((_) => http.Response('', 200));
      final client = rec.client();
      expect(await client.workflows.count(), isNull);
      expect(await client.workflows.list(), isEmpty);
      expect((await client.workflows.getById('w1')).name, '');
      expect(await client.workflows.run(const RunWorkflowRequest(workflowId: 'w1')), isEmpty);
      expect(await client.dryRun.execute(_dryRun), isNull);
      await client.workflows.delete('w1');
    });

    test('data: null decodes to empty models and collections', () async {
      final rec = Recorder((_) => envelope(null));
      final client = rec.client();
      expect((await client.environments.getById('e1')).id, isNull);
      expect(await client.environments.list(), isEmpty);
      expect(await client.executions.logs('x1'), isEmpty);
    });

    test('void methods ignore non-JSON success bodies', () async {
      final rec = Recorder((_) => http.Response('deleted', 200));
      await rec.client().workflows.deletePublished('p1');
      expect(rec.last.method, 'DELETE');
    });

    test('non-JSON success bodies of typed methods throw with the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('<html>', 200)).client().workflows.getById('w1'),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.message, 'message', startsWith('Invalid JSON response'))
            .having((e) => e.payload, 'payload', '<html>')),
      );
    });
  });

  group('errors', () {
    test('non-2xx with a JSON body', () async {
      final body = {
        'success': false,
        'error': {'code': 'NOT_FOUND'},
        'message': 'workflow not found'
      };
      await expectLater(
        Recorder((_) => jsonResponse(body, 404)).client().workflows.getById('nope'),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Request failed with status 404')
            .having((e) => e.payload, 'payload', body)
            .having((e) => e.toString(), 'toString', contains('404'))),
      );
    });

    test('non-2xx with a non-JSON body keeps the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('upstream down', 502)).client().workflows.list(),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 502)
            .having((e) => e.message, 'message', 'Request failed with status 502')
            .having((e) => e.payload, 'payload', 'upstream down')),
      );
    });

    test('non-2xx with an empty body has a null payload', () async {
      await expectLater(
        Recorder((_) => http.Response('', 503)).client().workflows.delete('w1'),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 503)
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('transport errors become status 0', () async {
      final client = WorkflowClient(
        token: 't',
        httpClient: MockClient((_) async => throw http.ClientException('connection refused')),
      );
      await expectLater(
        client.workflows.list(),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', 'connection refused')
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('timeouts become status 0', () async {
      final client = WorkflowClient(
        token: 't',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        client.workflows.list(),
        throwsA(isA<WorkflowException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', contains('timed out'))
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('a null timeout disables it', () async {
      final rec = Recorder((_) => envelope([]));
      expect(await rec.client(timeout: null).workflows.list(), isEmpty);
    });
  });

  group('query encoding', () {
    test('PaginationQuery fields, extra values and precedence', () {
      const q = PaginationQuery(
        page: 2,
        limit: 50,
        sortBy: 'createdAt',
        sortOrder: 'desc',
        where: "status='active'",
        extra: {
          'page': 9,
          'flag': true,
          'off': false,
          'ratio': 1.5,
          'whole': 3.0,
          'skip': null,
          'obj': {'a': 1},
          'list': [1, 'x'],
        },
      );
      expect(q.toQuery(), {
        'page': '2',
        'limit': '50',
        'sortBy': 'createdAt',
        'sortOrder': 'desc',
        'where': "status='active'",
        'flag': 'true',
        'off': 'false',
        'ratio': '1.5',
        'whole': '3',
        'obj': '{"a":1}',
        'list': '[1,"x"]',
      });
      expect(const PaginationQuery().toQuery(), isEmpty);
      expect(const PaginationQuery(extra: {'page': 4}).toQuery(), {'page': '4'});
    });

    test('query parameters are URL-encoded', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client().workflows.list(const PaginationQuery(where: 'name = "a&b"'));
      expect(rec.last.url.queryParameters, {'where': 'name = "a&b"'});
      expect(rec.last.url.query, isNot(contains('&b')));
    });

    test('path ids are percent-encoded', () async {
      final rec = Recorder((_) => envelope({}));
      await rec.client().workflows.getById('a/b c?d');
      expect(rec.last.url.toString(), 'https://api.lowco.ai/v1/wf/workflows/a%2Fb%20c%3Fd');
    });
  });

  test('close does not close an injected client', () {
    final tracking = TrackingClient();
    WorkflowClient(token: 't', httpClient: tracking).close();
    expect(tracking.closed, isFalse);
    // An internally created client can be closed repeatedly.
    WorkflowClient(token: 't')
      ..close()
      ..close();
  });

  test('model bodies are encoded via toJson and omit nulls', () async {
    final rec = Recorder((_) => envelope({'id': 'e1', 'name': 'prod'}));
    final env = await rec.client().environments.create(const Environment(
          name: 'prod',
          variables: [Variable(name: 'API_URL', value: 'https://x')],
        ));
    expect(env.id, 'e1');
    expect(jsonDecode(rec.last.body), {
      'name': 'prod',
      'variables': [
        {'name': 'API_URL', 'value': 'https://x'}
      ],
    });
  });
}

const _dryRun = DryRunRequest(
    executionId: 'x1', expression: r'$.a', typeOfExpression: 'string', activityId: 'a1');
