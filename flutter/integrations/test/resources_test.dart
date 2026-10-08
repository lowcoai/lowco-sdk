import 'dart:convert';

import 'package:lowcoai_integrations/lowcoai_integrations.dart';
import 'package:test/test.dart';

import 'support.dart';

const _noBody = Object();

/// One endpoint expectation: [call] must send [method] to [path] (the encoded
/// URL path) with [query] and [body] (`_noBody` = no body at all).
class Case {
  const Case(this.name, this.call, this.method, this.path,
      {this.query = const {}, this.body = _noBody});

  final String name;
  final Future<Object?> Function(IntegrationsClient c) call;
  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
}

const _q = PaginationQuery(
    page: 1, limit: 10, sortBy: 'name', sortOrder: 'asc', filter: 'x', tags: 'crm,sales');
const _qWire = {
  'page': '1',
  'limit': '10',
  'sortBy': 'name',
  'sortOrder': 'asc',
  'filter': 'x',
  'tags': 'crm,sales',
};

const _app = Application(name: 'Slack', type: 'http', subType: 'oauth2', tags: ['chat']);
const _appWire = {
  'name': 'Slack',
  'type': 'http',
  'subType': 'oauth2',
  'tags': ['chat'],
};

const _action = ApplicationAction(
    applicationId: 'a1', name: 'Send', action: HttpActionType(type: 'http', metadata: {'m': 1}));
const _actionWire = {
  'applicationId': 'a1',
  'name': 'Send',
  'action': {
    'type': 'http',
    'metadata': {'m': 1}
  },
};

const _conn = Connection(name: 'Sales', connectionType: 'oauth2', applicationId: 'a1');
const _connWire = {'name': 'Sales', 'connectionType': 'oauth2', 'applicationId': 'a1'};

const _trigger = ApplicationTrigger(name: 'on insert', applicationId: 'a1');
const _triggerWire = {'name': 'on insert', 'applicationId': 'a1'};

final cases = <Case>[
  // --- applications ----------------------------------------------------------
  Case('applications.list', (c) => c.applications.list(_q), 'GET', '/v1/integrations/applications',
      query: _qWire),
  Case('applications.list (no query)', (c) => c.applications.list(), 'GET',
      '/v1/integrations/applications'),
  Case('applications.getById', (c) => c.applications.getById('a/1'), 'GET',
      '/v1/integrations/applications/a%2F1'),
  Case('applications.create', (c) => c.applications.create(_app), 'POST',
      '/v1/integrations/applications',
      body: _appWire),
  Case('applications.update', (c) => c.applications.update('a1', _app), 'PUT',
      '/v1/integrations/applications/a1',
      body: _appWire),
  Case('applications.delete', (c) => c.applications.delete('a1'), 'DELETE',
      '/v1/integrations/applications/a1'),
  Case('applications.patchTags', (c) => c.applications.patchTags('a1', ['crm', 'sales']), 'PATCH',
      '/v1/integrations/applications/a1/tags',
      body: {
        'tags': ['crm', 'sales']
      }),
  Case(
      'applications.run',
      (c) => c.applications
          .run('a1', const RunApplicationRequest(credentialId: 'c1', inputBody: {'q': 1})),
      'POST',
      '/v1/integrations/applications/a1/run',
      body: {
        'credentialId': 'c1',
        'inputBody': {'q': 1}
      }),
  Case(
      'applications.loadActions',
      (c) => c.applications.loadActions(
          'a1',
          const PostmanFolder(name: 'Users', item: [
            PostmanFolder(name: 'List users', request: {'method': 'GET'})
          ], extra: {
            'description': 'd'
          })),
      'POST',
      '/v1/integrations/applications/a1/load-actions',
      body: {
        'name': 'Users',
        'item': [
          {
            'name': 'List users',
            'request': {'method': 'GET'}
          }
        ],
        'description': 'd',
      }),
  Case('applications.versions', (c) => c.applications.versions('a1', _q), 'GET',
      '/v1/integrations/applications/a1/versions',
      query: _qWire),
  Case('applications.regenerateMcpKey', (c) => c.applications.regenerateMcpKey('a1'), 'GET',
      '/v1/integrations/applications/a1/regenerate-mcp-key'),
  Case('applications.getMcpTools', (c) => c.applications.getMcpTools('a1'), 'GET',
      '/v1/integrations/applications/a1/mcp/tools'),
  Case('applications.getSubApplications', (c) => c.applications.getSubApplications(), 'GET',
      '/v1/integrations/applications/types'),
  Case(
      'applications.getApplicationsWithTriggers',
      (c) => c.applications.getApplicationsWithTriggers(),
      'GET',
      '/v1/integrations/applications/by-trigger'),

  // --- actions ---------------------------------------------------------------
  Case('actions.list', (c) => c.actions.list(_q), 'GET', '/v1/integrations/actions', query: _qWire),
  Case('actions.getById', (c) => c.actions.getById('x1'), 'GET', '/v1/integrations/actions/x1'),
  Case('actions.create', (c) => c.actions.create('a1', _action), 'POST',
      '/v1/integrations/applications/a1/action',
      body: _actionWire),
  Case('actions.update', (c) => c.actions.update('x1', _action), 'PUT',
      '/v1/integrations/actions/x1',
      body: _actionWire),
  Case('actions.delete', (c) => c.actions.delete('x1'), 'DELETE', '/v1/integrations/actions/x1'),
  Case('actions.listByApplication', (c) => c.actions.listByApplication('a1'), 'GET',
      '/v1/integrations/applications/a1/actions'),
  Case('actions.run', (c) => c.actions.run('x1', const RunActionRequest(inputBody: {'to': 'a'})),
      'POST', '/v1/integrations/actions/x1/run',
      body: {
        'inputBody': {'to': 'a'}
      }),
  Case('actions.resolveCredentials', (c) => c.actions.resolveCredentials(['x1', 'x2']), 'POST',
      '/v1/integrations/actions/allCredential',
      body: ['x1', 'x2']),

  // --- connections -----------------------------------------------------------
  Case('connections.list', (c) => c.connections.list(_q), 'GET', '/v1/integrations/connections',
      query: _qWire),
  Case('connections.getById', (c) => c.connections.getById('c1'), 'GET',
      '/v1/integrations/connections/c1'),
  Case('connections.create', (c) => c.connections.create(_conn), 'POST',
      '/v1/integrations/connections',
      body: _connWire),
  Case('connections.update', (c) => c.connections.update('c1', _conn), 'PUT',
      '/v1/integrations/connections/c1',
      body: _connWire),
  Case('connections.delete', (c) => c.connections.delete('c1'), 'DELETE',
      '/v1/integrations/connections/c1'),
  Case('connections.listByApplication', (c) => c.connections.listByApplication('a1'), 'GET',
      '/v1/integrations/applications/a1/connections'),
  Case('connections.setAsDefault', (c) => c.connections.setAsDefault('c1', 'a1'), 'PATCH',
      '/v1/integrations/connections/c1/setDefault',
      body: {'applicationId': 'a1'}),

  // --- triggers --------------------------------------------------------------
  Case('triggers.listByApplication', (c) => c.triggers.listByApplication('a1', _q), 'GET',
      '/v1/integrations/applications/a1/triggers',
      query: _qWire),
  Case('triggers.listByApplication (no query)', (c) => c.triggers.listByApplication('a1'), 'GET',
      '/v1/integrations/applications/a1/triggers'),
  Case('triggers.getById', (c) => c.triggers.getById('t1'), 'GET', '/v1/integrations/triggers/t1'),
  Case('triggers.create', (c) => c.triggers.create(_trigger), 'POST', '/v1/integrations/triggers',
      body: _triggerWire),
  Case('triggers.update', (c) => c.triggers.update('t1', _trigger), 'PUT',
      '/v1/integrations/triggers/t1',
      body: _triggerWire),
  Case('triggers.delete', (c) => c.triggers.delete('t1'), 'DELETE', '/v1/integrations/triggers/t1'),
  Case('triggers.getState', (c) => c.triggers.getState('t1'), 'GET',
      '/v1/integrations/triggers/t1/state'),

  // --- oauth -----------------------------------------------------------------
  Case(
      'oauth.login',
      (c) => c.oauth.login('app_slack',
          const ConnectionCreateRequest(applicationId: 'app_slack', name: 'Slack — Sales')),
      'POST',
      '/v1/integrations/oauth/app_slack/login',
      body: {'applicationId': 'app_slack', 'name': 'Slack — Sales'}),
  Case('oauth.callback', (c) => c.oauth.callback(const CallbackRequest(state: 's', code: 'c')),
      'POST', '/v1/integrations/oauth/callback',
      body: {'state': 's', 'code': 'c'}),
  Case('oauth.getTokenByCredentialId', (c) => c.oauth.getTokenByCredentialId('c1'), 'GET',
      '/v1/integrations/connections/c1/token'),
  Case('oauth.refreshTokenByCredentialId', (c) => c.oauth.refreshTokenByCredentialId('c1'), 'POST',
      '/v1/integrations/connections/c1/token/refresh'),
  Case('oauth.refreshExpiringTokens', (c) => c.oauth.refreshExpiringTokens(), 'POST',
      '/v1/integrations/oauth/tokens/refresh-expiring'),

  // --- configurations --------------------------------------------------------
  Case('configurations.get', (c) => c.configurations.get(), 'GET',
      '/v1/integrations/configurations'),

  // --- mcp -------------------------------------------------------------------
  Case(
      'mcp.callPublished',
      (c) => c.mcp.callPublished(
          'key 1',
          const JsonRpcRequest(
              jsonrpc: '2.0', id: 7, method: 'tools/call', params: {'name': 'send'})),
      'POST',
      '/v1/integrations/applications/published/key%201',
      body: {
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'tools/call',
        'params': {'name': 'send'}
      }),
  Case('mcp.infoPublished', (c) => c.mcp.infoPublished('k1'), 'GET',
      '/v1/integrations/applications/published/k1'),
];

void main() {
  group('endpoints', () {
    for (final tc in cases) {
      test(tc.name, () async {
        final rec = Recorder((_) => envelope({}));
        await tc.call(rec.client());
        final req = rec.requests.single;
        expect(req.method, tc.method);
        expect(req.url.host, 'api.lowco.ai');
        expect(req.url.path, tc.path);
        expect(req.url.queryParameters, tc.query);
        if (identical(tc.body, _noBody)) {
          expect(req.body, isEmpty);
          expect(req.headers.containsKey('Content-Type'), isFalse);
        } else {
          expect(req.headers['Content-Type'], startsWith('application/json'));
          expect(jsonDecode(req.body), tc.body);
        }
      });
    }
  });

  test('every resource is exercised', () {
    final covered = cases.map((c) => c.name.split(' ').first).toSet();
    expect(
        covered,
        containsAll(<String>[
          for (final m in [
            'list',
            'getById',
            'create',
            'update',
            'delete',
            'patchTags',
            'run',
            'loadActions',
            'versions',
            'regenerateMcpKey',
            'getMcpTools',
            'getSubApplications',
            'getApplicationsWithTriggers',
          ])
            'applications.$m',
          for (final m in [
            'list',
            'getById',
            'create',
            'update',
            'delete',
            'listByApplication',
            'run',
            'resolveCredentials',
          ])
            'actions.$m',
          for (final m in [
            'list',
            'getById',
            'create',
            'update',
            'delete',
            'listByApplication',
            'setAsDefault',
          ])
            'connections.$m',
          for (final m in [
            'listByApplication',
            'getById',
            'create',
            'update',
            'delete',
            'getState'
          ])
            'triggers.$m',
          for (final m in [
            'login',
            'callback',
            'getTokenByCredentialId',
            'refreshTokenByCredentialId',
            'refreshExpiringTokens',
          ])
            'oauth.$m',
          'configurations.get',
          'mcp.callPublished',
          'mcp.infoPublished',
        ]));
  });

  group('typed results', () {
    test('applications.list decodes counts', () async {
      final rec = Recorder((_) => envelope([
            {'id': 'a1', 'name': 'Slack', 'type': 'http', 'subType': 'oauth2', 'count': 4}
          ]));
      final apps = await rec.client().applications.list();
      expect(apps.single.count, 4);
      expect(apps.single.subType, 'oauth2');
    });

    test('sub application config', () async {
      final config = {
        'database': ['postgres', 'mysql'],
        'http': ['http', 'oauth2'],
      };
      final rec = Recorder((_) => envelope(config));
      expect(await rec.client().applications.getSubApplications(), config);
      expect(await rec.client().configurations.get(), config);
    });

    test('resolveCredentials decodes applications with connections', () async {
      final rec = Recorder((_) => envelope([
            {
              'id': 'a1',
              'name': 'Slack',
              'type': 'http',
              'subType': 'oauth2',
              'actionId': 'x1',
              'connections': [
                {
                  'id': 'c1',
                  'name': 'Sales',
                  'connectionType': 'oauth2',
                  'applicationId': 'a1',
                  'isDefault': true
                }
              ],
            }
          ]));
      final res = await rec.client().actions.resolveCredentials(['x1']);
      expect(res.single.actionId, 'x1');
      expect(res.single.connections.single.isDefault, isTrue);
    });

    test('oauth results', () async {
      final login = Recorder((_) => envelope({'url': 'https://slack.com/oauth'}));
      expect(
          (await login
                  .client()
                  .oauth
                  .login('a1', const ConnectionCreateRequest(applicationId: 'a1')))
              .url,
          'https://slack.com/oauth');

      final refresh = Recorder((_) => envelope({
            'checked': 3,
            'refreshed': 1,
            'skipped': 1,
            'failed': 1,
            'refreshedTokens': [
              {'applicationId': 'a1', 'credentialId': 'c1', 'token': 't', 'expiresIn': 3600}
            ],
            'failures': [
              {'credentialId': 'c2', 'error': 'invalid_grant'}
            ],
          }));
      final result = await refresh.client().oauth.refreshExpiringTokens();
      expect(result.checked, 3);
      expect(result.refreshedTokens.single.expiresIn, 3600);
      expect(result.failures.single['error'], 'invalid_grant');
    });

    test('run returns any JSON value', () async {
      expect(
          await Recorder((_) => envelope({'ok': true}))
              .client()
              .actions
              .run('x1', const RunActionRequest(inputBody: {})),
          {'ok': true});
      expect(
          await Recorder((_) => envelope('text'))
              .client()
              .applications
              .run('a1', const RunApplicationRequest(inputBody: {})),
          'text');
    });

    test('mcp tools and trigger state', () async {
      final tools = Recorder((_) => envelope({
            'tools': [
              {'name': 'send', 'inputSchema': {}}
            ]
          }));
      expect((await tools.client().applications.getMcpTools('a1')).tools.single['name'], 'send');

      final state = Recorder((_) => envelope({'triggerId': 't1', 'runCount': 12}));
      expect((await state.client().triggers.getState('t1')).runCount, 12);
    });
  });
}
