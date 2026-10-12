import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_lowcodb/lowcoai_lowcodb.dart';
import 'package:test/test.dart';

/// Records every request and answers with [respond].
class Recorder {
  Recorder([http.Response Function(http.Request)? respond])
      : _respond = respond ?? ((_) => envelope(null));

  final http.Response Function(http.Request) _respond;
  final requests = <http.Request>[];

  http.Request get last => requests.last;
  Object? get lastJson => jsonDecode(last.body);

  LowcodbClient client({
    String baseUrl = lowcoBaseUrl,
    String apiBasePath = defaultApiBasePath,
    Map<String, String>? defaultHeaders,
    Duration? timeout = const Duration(seconds: 30),
  }) =>
      LowcodbClient(
        token: 'tok_123',
        orgId: 'org_1',
        baseUrl: baseUrl,
        apiBasePath: apiBasePath,
        defaultHeaders: defaultHeaders,
        timeout: timeout,
        httpClient: MockClient((req) async {
          requests.add(req);
          return _respond(req);
        }),
      );
}

const gatewayUrl = 'https://api.lowco.ai/gateway/h1';

/// Answers the manager's gateway discovery for any schema; everything else via [respond].
http.Response Function(http.Request) gatewayAware(http.Response Function(http.Request) respond,
        {String hash = 'h1'}) =>
    (req) {
      if (req.url.path.contains('/bases/gateway-by-schema/')) {
        return envelope({
          'gatewayId': 'gw-1',
          'hash': hash,
          'contextPath': '/gateway/$hash',
          'url': 'https://api.lowco.ai/gateway/$hash',
          'internalUrl': 'http://gateway-svc-gw-1.prod.svc:80/gateway/$hash',
          'gatewayType': 'dedicated',
        });
      }
      return respond(req);
    };

http.Response envelope(Object? data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status,
        headers: {'content-type': 'application/json'});

http.Response jsonResponse(Object? body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('token is required', () {
    expect(() => LowcodbClient(token: '  '), throwsArgumentError);
  });

  test('sends auth, org and default headers', () async {
    final rec = Recorder((_) => envelope([]));
    await rec.client(defaultHeaders: {'X-Trace': 't1'}).listBases();
    final req = rec.last;
    expect(req.url.toString(), 'https://api.lowco.ai/v1/lowcodb/bases');
    expect(req.headers['Authorization'], 'Bearer tok_123');
    expect(req.headers[headerOrgId], 'org_1');
    expect(req.headers['Accept'], 'application/json');
    expect(req.headers['X-Trace'], 't1');
    expect(req.headers.containsKey('Content-Type'), isFalse);
  });

  test('setOrgId and setHeader', () async {
    final rec = Recorder((_) => envelope([]));
    final client = rec.client()
      ..setOrgId(null)
      ..setHeader('X-Extra', '1');
    await client.listTables();
    expect(rec.last.headers.containsKey(headerOrgId), isFalse);
    expect(rec.last.headers['X-Extra'], '1');
    client
      ..setOrgId('org_2')
      ..setHeader('X-Extra', null);
    await client.listTables();
    expect(rec.last.headers[headerOrgId], 'org_2');
    expect(rec.last.headers.containsKey('X-Extra'), isFalse);
  });

  test('unwraps the envelope and omits null fields from bodies', () async {
    final rec = Recorder((_) => envelope({'id': 'b1', 'name': 'crm', 'schema': 'app_crm'}));
    final base = await rec.client().createBase(const Base(name: 'crm', baseType: 'internal'));
    expect(base.id, 'b1');
    expect(base.schema, 'app_crm');
    expect(rec.last.method, 'POST');
    expect(rec.last.headers['Content-Type'], startsWith('application/json'));
    expect(rec.lastJson, {'name': 'crm', 'baseType': 'internal'});
  });

  test('null data and empty bodies decode leniently', () async {
    expect((await Recorder((_) => envelope(null)).client().getBase('b1')).id, isNull);
    expect(await Recorder((_) => envelope(null)).client().listBases(), isEmpty);
    expect(
        await Recorder(gatewayAware((_) => http.Response('', 204)))
            .client()
            .getRecord('s', 't', 'r'),
        isEmpty);
  });

  test('list params become query parameters', () async {
    final rec = Recorder(gatewayAware((_) => envelope([
          {'id': 'r1', 'name': 'Ada'}
        ])));
    final rows = await rec.client().listRecords('app_crm', 'leads',
        const ListParams(pageNo: 2, size: 50, filter: "status='open'", sort: '-createdAt'));
    expect(rows.single['name'], 'Ada');
    expect(rec.last.url.path, '/gateway/h1/v1/leads');
    expect(rec.last.url.queryParameters, {
      'pageNo': '2',
      'size': '50',
      'filter': "status='open'",
      'sort': '-createdAt',
    });
  });

  test('path segments are escaped', () async {
    final rec = Recorder(gatewayAware((_) => envelope({})));
    await rec.client().getRecord('my schema', 'a/b', 'id?1');
    expect(rec.requests.first.url.toString(),
        'https://api.lowco.ai/v1/lowcodb/bases/gateway-by-schema/my%20schema');
    expect(rec.last.url.toString(), 'https://api.lowco.ai/gateway/h1/v1/a%2Fb/id%3F1');
  });

  test('baseUrl and apiBasePath overrides', () async {
    final rec = Recorder((_) => envelope([]));
    await rec.client(baseUrl: 'http://lowcodb-service:8080/', apiBasePath: '/api/').listViews();
    expect(rec.last.url.toString(), 'http://lowcodb-service:8080/api/views');
  });

  test('health hits the root and accepts plain text', () async {
    final rec = Recorder((_) => http.Response('OK', 200));
    await rec.client().health();
    expect(rec.last.url.toString(), 'https://api.lowco.ai/health');
  });

  test('void methods ignore non-JSON success bodies', () async {
    final rec = Recorder((_) => http.Response('deleted', 200));
    await rec.client().deleteTrigger('t1');
    expect(rec.last.method, 'DELETE');
    expect(rec.last.url.path, '/v1/lowcodb/triggers/t1');
  });

  test('deleteBulkRecords sends a body', () async {
    final rec = Recorder(gatewayAware((_) => envelope(null)));
    await rec.client().deleteBulkRecords('app_crm', 'leads', ['r1', 'r2']);
    expect(rec.last.method, 'DELETE');
    expect(rec.lastJson, ['r1', 'r2']);
  });

  test('exportBaseCollection returns bytes', () async {
    final rec = Recorder((_) => http.Response.bytes([0, 1, 2], 200));
    expect(await rec.client().exportBaseCollection('b1'), [0, 1, 2]);
    expect(rec.last.url.path, '/v1/lowcodb/bases/b1/export');
  });

  test('validateField is not enveloped', () async {
    final rec = Recorder((_) => jsonResponse({
          'value': 1,
          'errors': [
            {'rule': 'min', 'error': 'too small'}
          ]
        }, 200));
    final res = await rec.client().validateField(const Field(value: 1, dataType: 'number'));
    expect(res.errors!.single.rule, 'min');
    expect(rec.lastJson, {'value': 1, 'dataType': 'number'});
  });

  test('transaction and event bodies', () async {
    final rec = Recorder(gatewayAware((_) => envelope({
          'results': [
            {'id': 'r1'}
          ]
        })));
    final client = rec.client();
    final res = await client.executeTransaction('app_crm', [
      const TransactionOperation(type: 'create', table: 'leads', record: {'a': 1}),
    ]);
    expect(res.results!.single['id'], 'r1');
    expect(rec.last.url.path, '/gateway/h1/v1/transactions');
    expect(rec.lastJson, {
      'operations': [
        {
          'type': 'create',
          'table': 'leads',
          'record': {'a': 1}
        }
      ]
    });

    await client.publishEvent(
        'app_crm', const PublishEventInput(eventType: 'lead.qualified', tableName: 'leads'));
    expect(rec.last.url.path, '/v1/lowcodb/events/publish');
    expect(
        rec.lastJson, {'schema': 'app_crm', 'eventType': 'lead.qualified', 'tableName': 'leads'});
  });

  test('functions execute and invoke', () async {
    final rec = Recorder(gatewayAware((_) => envelope({'ok': true})));
    final client = rec.client();
    await client.executeFunction('f1');
    expect(rec.lastJson, <String, dynamic>{});
    expect(rec.last.url.path, '/v1/lowcodb/functions/f1/execute');

    expect(await client.invokeFunction('app_crm', 'score-lead', method: 'GET'), {'ok': true});
    expect(rec.last.method, 'GET');
    expect(rec.last.body, isEmpty);
    expect(rec.last.url.path, '/gateway/h1/v1/fn/score-lead');

    await client.invokeFunction('app_crm', 'score-lead', body: {'leadId': 'l1'});
    expect(rec.last.method, 'POST');
    expect(rec.lastJson, {'leadId': 'l1'});
  });

  test('dashboard dates are ISO-8601 UTC', () async {
    final rec = Recorder((_) => envelope({}));
    await rec.client().getMetricsDashboard(
        range: '24h',
        from: DateTime.utc(2026, 1, 2, 3, 4, 5, 678),
        to: DateTime.utc(2026, 1, 3),
        baseId: 'b1');
    expect(rec.last.url.queryParameters, {
      'range': '24h',
      'from': '2026-01-02T03:04:05.678Z',
      'to': '2026-01-03T00:00:00.000Z',
      'baseId': 'b1',
    });
  });

  test('nested models decode', () async {
    final rec = Recorder((_) => envelope({
          'id': 't1',
          'columns': [
            {'name': 'email', 'dataType': 'text'}
          ],
          'metadata': {'color': 'red'},
        }));
    final table = await rec.client().getTable('t1');
    expect(table.columns!.single.dataType, 'text');
    expect(table.metadata, {'color': 'red'});
  });

  group('errors', () {
    test('prefer details over an opaque platform code', () async {
      final rec = Recorder((_) => jsonResponse({
            'error': {'code': 500, 'message': 'AAS-00105', 'details': 'lead score must be > 0'}
          }, 500));
      await expectLater(
        rec.client().invokeFunction('app_crm', 'score-lead', body: {}),
        throwsA(isA<LowcodbException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.message, 'message', 'lead score must be > 0')
            .having((e) => e.code, 'code', 500)
            .having((e) => e.body, 'body', contains('AAS-00105'))),
      );
    });

    test('keep a human message', () async {
      final rec = Recorder((_) => jsonResponse({
            'error': {'code': 'NOT_FOUND', 'message': 'base not found', 'details': 'x'}
          }, 404));
      await expectLater(
        rec.client().getBase('missing'),
        throwsA(isA<LowcodbException>()
            .having((e) => e.message, 'message', 'base not found')
            .having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    test('fall back to top-level message, raw text and status', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'message': 'bad'}, 400)).client().listBases(),
        throwsA(isA<LowcodbException>().having((e) => e.message, 'message', 'bad')),
      );
      await expectLater(
        Recorder((_) => http.Response(' upstream down ', 502)).client().listBases(),
        throwsA(isA<LowcodbException>()
            .having((e) => e.message, 'message', 'upstream down')
            .having((e) => e.statusCode, 'statusCode', 502)),
      );
      await expectLater(
        Recorder((_) => http.Response('', 503)).client().deleteBase('b1'),
        throwsA(isA<LowcodbException>().having((e) => e.message, 'message', 'lowcodb: status=503')),
      );
    });

    test('invalid JSON on success', () async {
      await expectLater(
        Recorder((_) => http.Response('<html>', 200)).client().getBase('b1'),
        throwsA(isA<LowcodbException>().having((e) => e.body, 'body', '<html>')),
      );
    });

    test('timeout', () async {
      final client = LowcodbClient(
        token: 't',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(client.listBases(), throwsA(isA<TimeoutException>()));
    });
  });

  // --- gateway routing -------------------------------------------------------

  test('data calls resolve the gateway once and cache it', () async {
    final rec = Recorder(gatewayAware(
        (req) => envelope(req.method == 'GET' && !req.url.path.endsWith('/r1') ? [] : {})));
    final client = rec.client();
    await client.listRecords('app_crm', 'leads');
    await client.countViewRecords('app_crm', 'hot leads');
    await client.createBulkRecords('app_crm', 'leads', [
      {'a': 1}
    ]);
    final discoveries = rec.requests.where((r) => r.url.path.contains('gateway-by-schema'));
    expect(discoveries.length, 1);
    final data = rec.requests
        .where((r) => r.url.path.contains('/gateway/'))
        .map((r) => '${r.method} ${r.url.path}');
    expect(data, [
      'GET /gateway/h1/v1/leads',
      'GET /gateway/h1/v1/views/hot%20leads/count',
      'POST /gateway/h1/v1/leads/bulk'
    ]);
  });

  test('pinned gateways skip discovery; api keys travel as X-Api-Key', () async {
    final rec = Recorder((_) => envelope({}));
    final client = LowcodbClient(
      token: 'lc_secret',
      orgId: 'org_1',
      gateways: {'app_crm': '/gateway/pinned', 'other': 'http://gw.internal:8080/gateway/x'},
      httpClient: MockClient((req) async {
        rec.requests.add(req);
        return envelope({});
      }),
    );
    await client.getRecord('app_crm', 'leads', 'r1');
    await client.getRecord('other', 'leads', 'r1');
    expect(rec.requests.map((r) => r.url.toString()), [
      'https://api.lowco.ai/gateway/pinned/v1/leads/r1',
      'http://gw.internal:8080/gateway/x/v1/leads/r1'
    ]);
    expect(rec.last.headers[headerApiKey], 'lc_secret');
    expect(rec.last.headers.containsKey('Authorization'), isFalse);
  });

  test('internal origin uses the in-cluster url', () async {
    final rec = Recorder(gatewayAware((_) => envelope({})));
    final client = LowcodbClient(
      token: 'tok',
      gatewayOrigin: GatewayOrigin.internal,
      httpClient: MockClient((req) async {
        rec.requests.add(req);
        return gatewayAware((_) => envelope({}))(req);
      }),
    );
    await client.getRecord('app_crm', 'leads', 'r1');
    expect(rec.last.url.toString(), 'http://gateway-svc-gw-1.prod.svc/gateway/h1/v1/leads/r1');
  });

  test('a stale gateway is re-resolved once', () async {
    final hashes = ['old', 'new'];
    final rec = Recorder((req) {
      if (req.url.path.contains('gateway-by-schema')) {
        final h = hashes.removeAt(0);
        return envelope({
          'gatewayId': 'gw',
          'hash': h,
          'contextPath': '/gateway/$h',
          'url': 'https://api.lowco.ai/gateway/$h'
        });
      }
      if (req.url.path.contains('/gateway/old/')) return http.Response('route not found', 404);
      return envelope({'id': 'r1'});
    });
    final row = await rec.client().getRecord('app_crm', 'leads', 'r1');
    expect(row['id'], 'r1');
    expect(rec.requests.where((r) => r.url.path.contains('/gateway/')).map((r) => r.url.path),
        ['/gateway/old/v1/leads/r1', '/gateway/new/v1/leads/r1']);
  });

  test('402 QUOTA_EXCEEDED is typed', () async {
    final rec = Recorder(gatewayAware((_) => jsonResponse({
          'code': 'QUOTA_EXCEEDED',
          'message': 'plan cap reached',
          'meter': 'app_crm_leads_create',
          'consumed': 100,
          'included': 100,
          'hard_cap': 100,
          'period_end': '2026-11-01T00:00:00Z',
          'app_key': 'crm',
          'upgrade': {
            'app_key': 'crm',
            'plans': ['pro']
          },
        }, 402)));
    await expectLater(
      rec.client().createRecord('app_crm', 'leads', {}),
      throwsA(isA<QuotaExceededException>()
          .having((e) => e.statusCode, 'status', 402)
          .having((e) => e.meter, 'meter', 'app_crm_leads_create')
          .having((e) => e.hardCap, 'hardCap', 100)
          .having((e) => e.upgradeAppKey, 'upgradeAppKey', 'crm')
          .having((e) => e.upgradePlans, 'plans', ['pro'])),
    );
  });

  test('GatewayClient addresses a gateway directly', () async {
    final rec = Recorder((_) => envelope({'results': []}));
    final gw = rec.client().gateway('/gateway/direct');
    expect(gw.url, 'https://api.lowco.ai/gateway/direct');
    await gw.executeTransaction(const []);
    await gw.invokeFunction('score-lead', body: {'id': 1});
    expect(rec.requests.map((r) => r.url.path),
        ['/gateway/direct/v1/transactions', '/gateway/direct/v1/fn/score-lead']);
  });
}
