import 'dart:convert';

import 'package:lowcoai_workflow/lowcoai_workflow.dart';
import 'package:test/test.dart';

import 'support.dart';

const _noBody = Object();

/// One endpoint expectation: [call] must send [method] to [path] (the encoded
/// URL path) with [query] and [body] (`_noBody` = no body at all).
class Case {
  const Case(this.name, this.call, this.method, this.path,
      {this.query = const {}, this.body = _noBody});

  final String name;
  final Future<Object?> Function(WorkflowClient c) call;
  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
}

const _q = PaginationQuery(page: 1, limit: 10, sortBy: 'name', sortOrder: 'asc', where: 'x');
const _qWire = {'page': '1', 'limit': '10', 'sortBy': 'name', 'sortOrder': 'asc', 'where': 'x'};

const _ui = WorkflowUI(nodes: [WorkflowUINode(id: 'n1')], edges: []);
const _uiWire = {
  'nodes': [
    {'id': 'n1'}
  ],
  'edges': <Object>[],
};

const _fn = FunctionEntity(name: 'sum', body: 'return a + b');
const _fnWire = {'name': 'sum', 'body': 'return a + b'};

final cases = <Case>[
  // --- workflows -------------------------------------------------------------
  Case('workflows.list', (c) => c.workflows.list(_q), 'GET', '/v1/wf/workflows', query: _qWire),
  Case('workflows.list (no query)', (c) => c.workflows.list(), 'GET', '/v1/wf/workflows'),
  Case('workflows.count', (c) => c.workflows.count(_q), 'GET', '/v1/wf/workflows/count',
      query: _qWire),
  Case('workflows.getById', (c) => c.workflows.getById('w/1'), 'GET', '/v1/wf/workflows/w%2F1'),
  Case('workflows.create', (c) => c.workflows.create(const Workflow(name: 'Flow', ui: _ui)), 'POST',
      '/v1/wf/workflows',
      body: {'name': 'Flow', 'ui': _uiWire}),
  Case(
      'workflows.update',
      (c) => c.workflows
          .update('w1', const WorkflowUpdateRequest(name: 'Flow', ui: _ui, comment: 'v2')),
      'PUT',
      '/v1/wf/workflows/w1',
      body: {'name': 'Flow', 'ui': _uiWire, 'comment': 'v2'}),
  Case('workflows.delete', (c) => c.workflows.delete('w1'), 'DELETE', '/v1/wf/workflows/w1'),
  Case(
      'workflows.run',
      (c) => c.workflows.run(const RunWorkflowRequest(
          workflowId: 'w1',
          inputData: {'orderId': 'o1'},
          environmentId: 'env1',
          activityId: 'a1',
          executionId: 'x1')),
      'POST',
      '/v1/wf/workflows/run',
      body: {
        'workflowId': 'w1',
        'inputData': {'orderId': 'o1'},
        'environmentId': 'env1',
        'activityId': 'a1',
        'executionId': 'x1',
      }),
  Case('workflows.versions', (c) => c.workflows.versions('w1', _q), 'GET',
      '/v1/wf/workflows/w1/versions',
      query: _qWire),
  Case(
      'workflows.publish',
      (c) => c.workflows
          .publish('w1', const WorkflowPublishRequest(category: 'sales', longDescription: 'Long')),
      'POST',
      '/v1/wf/workflows/w1/publish',
      body: {'category': 'sales', 'longDescription': 'Long'}),
  Case('workflows.published', (c) => c.workflows.published(_q), 'GET', '/v1/wf/workflows/published',
      query: _qWire),
  Case('workflows.publishedCount', (c) => c.workflows.publishedCount(_q), 'GET',
      '/v1/wf/workflows/published/count',
      query: _qWire),
  Case('workflows.getPublishedById', (c) => c.workflows.getPublishedById('p1'), 'GET',
      '/v1/wf/workflows/published/p1'),
  Case(
      'workflows.updatePublished',
      (c) => c.workflows.updatePublished(
          'p1', const WorkflowPublishRequest(category: 'ops', longDescription: 'L')),
      'PUT',
      '/v1/wf/workflows/published/p1',
      body: {'category': 'ops', 'longDescription': 'L'}),
  Case('workflows.deletePublished', (c) => c.workflows.deletePublished('p1'), 'DELETE',
      '/v1/wf/workflows/published/p1'),
  Case('workflows.webPublished', (c) => c.workflows.webPublished(_q), 'GET',
      '/v1/wf/workflows/published/web',
      query: _qWire),
  Case('workflows.webPublishedById', (c) => c.workflows.webPublishedById('p1'), 'GET',
      '/v1/wf/workflows/published/web/p1'),
  Case(
      'workflows.searchPublishedTemplates',
      (c) => c.workflows.searchPublishedTemplates(q: 'crm sync', category: 'sales', limit: 5),
      'GET',
      '/v1/wf/workflows/published/web/search',
      query: {'q': 'crm sync', 'category': 'sales', 'limit': '5'}),
  Case(
      'workflows.searchPublishedTemplates (no params)',
      (c) => c.workflows.searchPublishedTemplates(),
      'GET',
      '/v1/wf/workflows/published/web/search'),

  // --- environments ----------------------------------------------------------
  Case('environments.list', (c) => c.environments.list(_q), 'GET', '/v1/wf/environments',
      query: _qWire),
  Case(
      'environments.getById', (c) => c.environments.getById('e1'), 'GET', '/v1/wf/environments/e1'),
  Case('environments.create', (c) => c.environments.create(const Environment(name: 'dev')), 'POST',
      '/v1/wf/environments',
      body: {'name': 'dev'}),
  Case(
      'environments.update',
      (c) => c.environments
          .update('e1', const Environment(name: 'dev', isDefaultEnv: true, variables: [])),
      'PUT',
      '/v1/wf/environments/e1',
      body: {'name': 'dev', 'isDefaultEnv': true, 'variables': <Object>[]}),
  Case('environments.delete', (c) => c.environments.delete('e1'), 'DELETE',
      '/v1/wf/environments/e1'),
  Case('environments.setDefault', (c) => c.environments.setDefault('e1'), 'PATCH',
      '/v1/wf/environments/e1/default'),

  // --- functions -------------------------------------------------------------
  Case('functions.list', (c) => c.functions.list(_q), 'GET', '/v1/wf/functions', query: _qWire),
  Case('functions.getById', (c) => c.functions.getById('f1'), 'GET', '/v1/wf/functions/f1'),
  Case('functions.create', (c) => c.functions.create(_fn), 'POST', '/v1/wf/functions',
      body: _fnWire),
  Case(
      'functions.update',
      (c) => c.functions.update('f1', const FunctionVersionRequest(function: _fn, comment: 'c')),
      'PUT',
      '/v1/wf/functions/f1',
      body: {'function': _fnWire, 'comment': 'c'}),
  Case('functions.delete', (c) => c.functions.delete('f1'), 'DELETE', '/v1/wf/functions/f1'),
  Case('functions.versions', (c) => c.functions.versions('f1', _q), 'GET',
      '/v1/wf/functions/f1/versions',
      query: _qWire),
  Case('functions.execute (default body)', (c) => c.functions.execute('f1'), 'POST',
      '/v1/wf/functions/f1/execute',
      body: <String, Object>{}),
  Case('functions.execute', (c) => c.functions.execute('f1', {'a': 1, 'b': 2}), 'POST',
      '/v1/wf/functions/f1/execute',
      body: {'a': 1, 'b': 2}),

  // --- executions ------------------------------------------------------------
  Case('executions.list', (c) => c.executions.list(_q), 'GET', '/v1/wf/executions', query: _qWire),
  Case('executions.list (full)', (c) => c.executions.list(_q, true), 'GET', '/v1/wf/executions',
      query: {..._qWire, 'full': 'true'}),
  Case('executions.list (full only)', (c) => c.executions.list(null, false), 'GET',
      '/v1/wf/executions',
      query: {'full': 'false'}),
  Case('executions.count', (c) => c.executions.count(_q), 'GET', '/v1/wf/executions/count',
      query: _qWire),
  Case('executions.getById', (c) => c.executions.getById('x1'), 'GET', '/v1/wf/executions/x1'),
  Case('executions.logs', (c) => c.executions.logs('x1'), 'GET', '/v1/wf/executions/x1/logs'),

  // --- activities ------------------------------------------------------------
  Case('activities.list', (c) => c.activities.list(_q), 'GET', '/v1/wf/activities', query: _qWire),
  Case('activities.count', (c) => c.activities.count(), 'GET', '/v1/wf/activities/count'),
  Case('activities.getById', (c) => c.activities.getById('a1'), 'GET', '/v1/wf/activities/a1'),
  Case('activities.logs', (c) => c.activities.logs('a1'), 'GET', '/v1/wf/activities/a1/logs'),

  // --- human tasks -----------------------------------------------------------
  Case('humanTasks.list', (c) => c.humanTasks.list(_q), 'GET', '/v1/wf/human-tasks', query: _qWire),
  Case('humanTasks.getById', (c) => c.humanTasks.getById('h1'), 'GET', '/v1/wf/human-tasks/h1'),
  Case('humanTasks.complete', (c) => c.humanTasks.complete('h1', 'approve'), 'PATCH',
      '/v1/wf/human-tasks/h1/complete',
      body: {'action': 'approve'}),

  // --- analytics -------------------------------------------------------------
  Case('analytics.getDefault', (c) => c.analytics.getDefault(), 'GET', '/v1/wf/analytics'),
  Case('analytics.getById', (c) => c.analytics.getById('w1'), 'GET', '/v1/wf/analytics/w1'),

  // --- dry run ---------------------------------------------------------------
  Case(
      'dryRun.execute',
      (c) => c.dryRun.execute(const DryRunRequest(
          executionId: 'x1', expression: r'$.a', typeOfExpression: 'object', activityId: 'a1')),
      'POST',
      '/v1/wf/dryrun',
      body: {
        'executionId': 'x1',
        'expression': r'$.a',
        'typeOfExpression': 'object',
        'activityId': 'a1'
      }),

  // --- webhooks --------------------------------------------------------------
  Case('webhooks.trigger (defaults)', (c) => c.webhooks.trigger('w1'), 'POST', '/v1/wf/webhook/w1',
      body: <String, Object>{}),
  Case(
      'webhooks.trigger',
      (c) => c.webhooks
          .trigger('w1', payload: {'orderId': 'o1'}, env: 'prod', triggeredBy: 'crm', async: true),
      'POST',
      '/v1/wf/webhook/w1',
      query: {'env': 'prod', 'triggeredBy': 'crm', 'async': 'true'},
      body: {'orderId': 'o1'}),
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
            'count',
            'getById',
            'create',
            'update',
            'delete',
            'run',
            'versions',
            'publish',
            'published',
            'publishedCount',
            'getPublishedById',
            'updatePublished',
            'deletePublished',
            'webPublished',
            'webPublishedById',
            'searchPublishedTemplates',
          ])
            'workflows.$m',
          for (final m in ['list', 'getById', 'create', 'update', 'delete', 'setDefault'])
            'environments.$m',
          for (final m in ['list', 'getById', 'create', 'update', 'delete', 'versions', 'execute'])
            'functions.$m',
          for (final m in ['list', 'count', 'getById', 'logs']) 'executions.$m',
          for (final m in ['list', 'count', 'getById', 'logs']) 'activities.$m',
          for (final m in ['list', 'getById', 'complete']) 'humanTasks.$m',
          'analytics.getDefault',
          'analytics.getById',
          'dryRun.execute',
          // Only the trigger: the orchestrator serves no other webhook route.
          'webhooks.trigger',
        ]));
  });

  group('typed results', () {
    test('lists and nested models', () async {
      final rec = Recorder((_) => envelope([
            {
              'id': 'ah1',
              'history': {
                'activityId': 'a1',
                'workflowId': 'w1',
                'executionId': 'x1',
                'status': 'completed',
                'outputData': {'ok': true},
              },
              'execution': {'workflowId': 'w1', 'status': 'running'},
            }
          ]));
      final items = await rec.client().activities.list();
      expect(items.single.history.status, 'completed');
      expect(items.single.history.outputData, {'ok': true});
      expect(items.single.execution!.status, 'running');
    });

    test('logs, webhooks and analytics maps', () async {
      final logs = Recorder((_) => envelope([
            'a',
            1,
            null,
            {'k': 'v'}
          ]));
      expect(await logs.client().executions.logs('x1'), [
        'a',
        1,
        null,
        {'k': 'v'}
      ]);

      final stats = Recorder((_) => envelope({'total': 3}));
      expect(await stats.client().analytics.getDefault(), {'total': 3});
    });

    test('dryRun returns any JSON value', () async {
      expect(await Recorder((_) => envelope('hello')).client().dryRun.execute(_dry), 'hello');
      expect(await Recorder((_) => envelope([1, 2])).client().dryRun.execute(_dry), [1, 2]);
    });

    test('humanTasks.complete decodes the task', () async {
      final rec = Recorder((_) => envelope({
            'id': 'h1',
            'message': 'Approve?',
            'executionId': 'x1',
            'workflowId': 'w1',
            'activityId': 'a1',
            'completed': true,
            'answer': 'approve',
            'actions': [
              {'text': 'Approve', 'value': 'approve'}
            ],
          }));
      final task = await rec.client().humanTasks.complete('h1', 'approve');
      expect(task.completed, isTrue);
      expect(task.actions!.single.value, 'approve');
    });
  });
}

const _dry = DryRunRequest(
    executionId: 'x1', expression: r'$.a', typeOfExpression: 'string', activityId: 'a1');
