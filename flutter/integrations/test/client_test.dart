import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_integrations/lowcoai_integrations.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('token is required', () {
    expect(() => IntegrationsClient(token: ''), throwsArgumentError);
    expect(() => IntegrationsClient(token: '  '), throwsArgumentError);
    expect(() => IntegrationsHttpClient(token: ''), throwsArgumentError);
  });

  group('headers', () {
    test('auth, org, accept and extra headers; no content type without a body', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'X-Trace': 't1'}).applications.list();
      final req = rec.last;
      expect(req.url.toString(), 'https://api.lowco.ai/v1/integrations/applications');
      expect(req.headers['Authorization'], 'Bearer tok_123');
      expect(req.headers[headerOrgId], 'org_1');
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['X-Trace'], 't1');
      expect(req.headers.containsKey('Content-Type'), isFalse);
      expect(req.body, isEmpty);
    });

    test('content type only when a body is sent, and it wins over extra headers', () async {
      final rec = Recorder((_) => envelope({}));
      await rec.client(headers: {'Content-Type': 'text/plain'}).applications.patchTags('a1', ['x']);
      expect(rec.last.headers['Content-Type'], startsWith('application/json'));
      expect(rec.lastJson, {
        'tags': ['x']
      });
    });

    test('an Authorization header in headers takes precedence over the token', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'Authorization': 'Basic abc'}).applications.list();
      expect(rec.last.headers['Authorization'], 'Basic abc');

      // Header names are case-insensitive (the TS SDK would send both).
      await rec.client(headers: {'authorization': 'Bearer other'}).applications.list();
      expect(rec.last.headers['Authorization'], 'Bearer other');
      expect(rec.last.headers.keys.where((k) => k.toLowerCase() == 'authorization'), hasLength(1));
    });

    test('an X-Org-Id header in headers takes precedence over orgId', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'X-Org-Id': 'org_from_headers'}).applications.list();
      expect(rec.last.headers[headerOrgId], 'org_from_headers');

      await rec.client(headers: {'x-org-id': 'org_lower'}).applications.list();
      expect(rec.last.headers[headerOrgId], 'org_lower');
    });

    test('no X-Org-Id without an orgId', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(orgId: null).applications.list();
      expect(rec.last.headers.containsKey(headerOrgId), isFalse);
      await rec.client(orgId: '').applications.list();
      expect(rec.last.headers.containsKey(headerOrgId), isFalse);
    });

    test('extra headers may override Accept (TS order)', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'Accept': 'application/x-ndjson'}).applications.list();
      expect(rec.last.headers['Accept'], 'application/x-ndjson');
    });

    test('per-request headers on the transport', () async {
      final requests = <http.Request>[];
      final transport = IntegrationsHttpClient(
        token: 'tok',
        orgId: 'org_1',
        headers: {'X-A': 'client'},
        httpClient: MockClient((req) async {
          requests.add(req);
          return envelope({'ok': true});
        }),
      );
      final res = await transport.request('GET', 'v1/integrations/custom',
          query: {'a': 1, 'b': null}, headers: {'X-A': 'request', 'X-Org-Id': 'org_2'});
      expect(res, {'ok': true});
      expect(requests.single.url.toString(), 'https://api.lowco.ai/v1/integrations/custom?a=1');
      expect(requests.single.headers['X-A'], 'request');
      expect(requests.single.headers[headerOrgId], 'org_2');
    });
  });

  group('responses', () {
    test('unwraps the data envelope', () async {
      final rec = Recorder((_) => envelope({'id': 'a1', 'name': 'Slack', 'type': 'http'}));
      final app = await rec.client().applications.getById('a1');
      expect(app.id, 'a1');
      expect(app.name, 'Slack');
    });

    test('payloads without a data key are returned as-is', () async {
      final rec = Recorder((_) => jsonResponse({'id': 'a1', 'name': 'Slack'}, 200));
      expect((await rec.client().applications.getById('a1')).name, 'Slack');

      final arr = Recorder((_) => jsonResponse([
            {'id': 'c1', 'name': 'conn'}
          ], 200));
      expect((await arr.client().connections.list()).single.id, 'c1');

      final rpc = Recorder((_) => jsonResponse({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32601, 'message': 'Method not found', 'data': 'x'}
          }, 200));
      final res = await rpc
          .client()
          .mcp
          .callPublished('k1', const JsonRpcRequest(jsonrpc: '2.0', id: 1, method: 'nope'));
      expect(res.error!.code, -32601);
      expect(res.error!.data, 'x');
    });

    test('an empty body is null and decodes leniently', () async {
      final rec = Recorder((_) => http.Response('', 200));
      final client = rec.client();
      expect(await client.actions.run('x', const RunActionRequest(inputBody: {})), isNull);
      expect(await client.applications.list(), isEmpty);
      expect((await client.applications.getById('a1')).name, '');
      expect(await client.configurations.get(), isEmpty);
      expect(await client.mcp.infoPublished('k'), isEmpty);
      await client.connections.delete('c1');
    });

    test('data: null decodes to empty models and collections', () async {
      final rec = Recorder((_) => envelope(null));
      final client = rec.client();
      expect((await client.triggers.getState('t1')).runCount, 0);
      expect(await client.triggers.listByApplication('a1'), isEmpty);
      expect((await client.oauth.refreshExpiringTokens()).refreshedTokens, isEmpty);
      expect(await client.applications.getSubApplications(), isEmpty);
    });

    test('void methods ignore non-JSON success bodies', () async {
      final rec = Recorder((_) => http.Response('deleted', 200));
      await rec.client().actions.delete('x1');
      expect(rec.last.method, 'DELETE');
    });

    test('non-JSON success bodies of typed methods throw with the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('<html>', 200)).client().applications.getById('a1'),
        throwsA(isA<IntegrationsException>()
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
        'message': 'application not found'
      };
      await expectLater(
        Recorder((_) => jsonResponse(body, 404)).client().applications.getById('nope'),
        throwsA(isA<IntegrationsException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Request failed with status 404')
            .having((e) => e.payload, 'payload', body)
            .having((e) => e.toString(), 'toString', contains('404'))),
      );
    });

    test('non-2xx with a non-JSON body keeps the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('upstream down', 502)).client().connections.list(),
        throwsA(isA<IntegrationsException>()
            .having((e) => e.status, 'status', 502)
            .having((e) => e.message, 'message', 'Request failed with status 502')
            .having((e) => e.payload, 'payload', 'upstream down')),
      );
    });

    test('non-2xx with an empty body has a null payload', () async {
      await expectLater(
        Recorder((_) => http.Response('', 401)).client().triggers.delete('t1'),
        throwsA(isA<IntegrationsException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('transport errors become status 0', () async {
      final client = IntegrationsClient(
        token: 't',
        httpClient: MockClient((_) async => throw http.ClientException('connection refused')),
      );
      await expectLater(
        client.applications.list(),
        throwsA(isA<IntegrationsException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', 'connection refused')
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('timeouts become status 0', () async {
      final client = IntegrationsClient(
        token: 't',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        client.applications.list(),
        throwsA(isA<IntegrationsException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', contains('timed out'))
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('a null timeout disables it', () async {
      final rec = Recorder((_) => envelope([]));
      expect(await rec.client(timeout: null).applications.list(), isEmpty);
    });
  });

  group('query encoding', () {
    test('PaginationQuery fields, extra values and precedence', () {
      const q = PaginationQuery(
        page: 2,
        limit: 50,
        sortBy: 'name',
        sortOrder: 'desc',
        filter: "type='http'",
        tags: 'crm,sales',
        extra: {
          'tags': 'ignored',
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
        'sortBy': 'name',
        'sortOrder': 'desc',
        'filter': "type='http'",
        'tags': 'crm,sales',
        'flag': 'true',
        'off': 'false',
        'ratio': '1.5',
        'whole': '3',
        'obj': '{"a":1}',
        'list': '[1,"x"]',
      });
      expect(const PaginationQuery().toQuery(), isEmpty);
      expect(const PaginationQuery(extra: {'tags': 'a'}).toQuery(), {'tags': 'a'});
    });

    test('query parameters are URL-encoded', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client().applications.list(const PaginationQuery(filter: 'name = "a&b"'));
      expect(rec.last.url.queryParameters, {'filter': 'name = "a&b"'});
      expect(rec.last.url.query, isNot(contains('&b')));
    });

    test('path ids are percent-encoded', () async {
      final rec = Recorder((_) => envelope({}));
      await rec.client().applications.getById('a/b c?d');
      expect(rec.last.url.toString(),
          'https://api.lowco.ai/v1/integrations/applications/a%2Fb%20c%3Fd');
    });
  });

  test('close does not close an injected client', () {
    final tracking = TrackingClient();
    IntegrationsClient(token: 't', httpClient: tracking).close();
    expect(tracking.closed, isFalse);
    IntegrationsClient(token: 't')
      ..close()
      ..close();
  });

  test('model bodies are encoded via toJson and omit nulls', () async {
    final rec = Recorder((_) => envelope({'id': 'c1', 'name': 'Slack'}));
    final conn = await rec
        .client()
        .connections
        .create(const Connection(name: 'Slack', connectionType: 'oauth2', applicationId: 'a1'));
    expect(conn.id, 'c1');
    expect(jsonDecode(rec.last.body),
        {'name': 'Slack', 'connectionType': 'oauth2', 'applicationId': 'a1'});
  });
}
