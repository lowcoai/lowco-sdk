import 'dart:convert';

import 'package:lowcoai_workflow/lowcoai_workflow.dart';
import 'package:test/test.dart';

const _meta = {
  'id': 'id1',
  'orgId': 'org_1',
  'createdBy': 'u1',
  'updatedBy': 'u2',
  'createdAt': '2026-01-02T03:04:05Z',
  'updatedAt': '2026-01-03T03:04:05Z',
};

const _uiNode = {
  'id': 'n1',
  'type': 'httpNode',
  'data': {
    'label': 'Call API',
    'config': {'url': 'https://x', 'retries': 3},
  },
  'position': {'x': 10.5, 'y': -4},
  'measured': {'width': 200, 'height': 80},
  'selected': false,
  'dragging': false,
  'parentId': null,
  'zIndex': 2,
};

const _ui = {
  'nodes': [
    _uiNode,
    {'id': 'n2'},
  ],
  'edges': [
    {'id': 'e1', 'source': 'n1', 'target': 'n2', 'type': 'smoothstep', 'label': 'ok'},
  ],
};

const _workflow = {
  ..._meta,
  'name': 'Order sync',
  'description': 'Sync orders',
  'inputData': {'orderId': 'o1', 'n': 1},
  'ui': _ui,
  'tags': ['sales', 'crm'],
  'version': 3,
  'published': true,
};

const _functionEntity = {
  ..._meta,
  'name': 'sum',
  'description': 'adds',
  'body': 'return a + b',
  'version': 2,
  'isActive': true,
};

const _execution = {
  ..._meta,
  'workflowId': 'w1',
  'correlationId': 'c1',
  'version': 3,
  'status': 'completed',
  'context': {'k': 'v'},
  'failedReason': 'none',
  'inputData': ['a', 1],
  'outputData': 'done',
  'workflow': _workflow,
};

const _history = {
  ..._meta,
  'activityId': 'a1',
  'workflowId': 'w1',
  'executionId': 'x1',
  'type': 'http',
  'typeId': 't1',
  'status': 'completed',
  'inputData': {'in': 1},
  'outputData': 42,
  'failedReason': 'r',
};

/// A full wire fixture per model; fromJson -> toJson must return it unchanged.
final fixtures =
    <String, (Map<String, dynamic>, Map<String, dynamic> Function(Map<String, dynamic>))>{
  'ApiEnvelope': (
    {
      'success': true,
      'code': 'OK',
      'message': 'm',
      'data': [1],
      'error': {'e': 1}
    },
    (j) => ApiEnvelope.fromJson(j).toJson()
  ),
  'Variable': ({'id': 'v1', 'name': 'A', 'value': 'b'}, (j) => Variable.fromJson(j).toJson()),
  'Environment': (
    {
      ..._meta,
      'name': 'prod',
      'description': 'd',
      'isDefaultEnv': true,
      'variables': [
        {'id': 'v1', 'name': 'A', 'value': 'b'}
      ],
    },
    (j) => Environment.fromJson(j).toJson()
  ),
  'WorkflowUINode': (_uiNode, (j) => WorkflowUINode.fromJson(j).toJson()),
  'WorkflowUIEdge': (
    {'id': 'e1', 'source': 'a', 'target': 'b', 'type': 't', 'label': 'l'},
    (j) => WorkflowUIEdge.fromJson(j).toJson()
  ),
  'WorkflowUI': (_ui, (j) => WorkflowUI.fromJson(j).toJson()),
  'Workflow': (_workflow, (j) => Workflow.fromJson(j).toJson()),
  'WorkflowUpdateRequest': (
    {..._workflow, 'comment': 'v4'},
    (j) => WorkflowUpdateRequest.fromJson(j).toJson()
  ),
  'RunWorkflowRequest': (
    {
      'workflowId': 'w1',
      'inputData': {'a': 1},
      'environmentId': 'env1',
      'triggeredBy': 'sdk',
      'orgId': 'org_1',
      'activityId': 'a1',
      'executionId': 'x1',
    },
    (j) => RunWorkflowRequest.fromJson(j).toJson()
  ),
  'FunctionEntity': (_functionEntity, (j) => FunctionEntity.fromJson(j).toJson()),
  'FunctionVersionRequest': (
    {'function': _functionEntity, 'comment': 'c'},
    (j) => FunctionVersionRequest.fromJson(j).toJson()
  ),
  'HumanTaskAction': (
    {'text': 'Approve', 'value': 'approve'},
    (j) => HumanTaskAction.fromJson(j).toJson()
  ),
  'HumanTask': (
    {
      ..._meta,
      'message': 'Approve?',
      'actions': [
        {'text': 'Approve', 'value': 'approve'}
      ],
      'assignedTo': 'u3',
      'executionId': 'x1',
      'workflowId': 'w1',
      'answer': 'approve',
      'completed': true,
      'completedAt': '2026-01-04T00:00:00Z',
      'activityId': 'a1',
    },
    (j) => HumanTask.fromJson(j).toJson()
  ),
  'Execution': (_execution, (j) => Execution.fromJson(j).toJson()),
  'ActivityExecutionHistory': (_history, (j) => ActivityExecutionHistory.fromJson(j).toJson()),
  'ActivityHistoryResponse': (
    {
      'id': 'ah1',
      'history': _history,
      'activity': {'name': 'Call API'},
      'workflow': _workflow,
      'execution': _execution,
    },
    (j) => ActivityHistoryResponse.fromJson(j).toJson()
  ),
  'WorkflowPublish': (
    {
      ..._meta,
      'workflowId': 'w1',
      'sourceOrgId': 'org_0',
      'category': 'sales',
      'longDescription': 'Long',
      'workflow': _workflow,
    },
    (j) => WorkflowPublish.fromJson(j).toJson()
  ),
  'WorkflowPublishRequest': (
    {'category': 'sales', 'longDescription': 'Long'},
    (j) => WorkflowPublishRequest.fromJson(j).toJson()
  ),
  'DryRunRequest': (
    {'executionId': 'x1', 'expression': r'$.a', 'typeOfExpression': 'map', 'activityId': 'a1'},
    (j) => DryRunRequest.fromJson(j).toJson()
  ),
};

void main() {
  group('round trips', () {
    fixtures.forEach((name, fixture) {
      test(name, () {
        final (json, roundTrip) = fixture;
        // Through a JSON string, as the client sees it.
        final decoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
        expect(roundTrip(decoded), json);
      });
    });
  });

  group('WorkflowUINode', () {
    test('keeps unknown keys in extra', () {
      final node = WorkflowUINode.fromJson(_uiNode);
      expect(node.id, 'n1');
      expect(node.type, 'httpNode');
      expect(node.data!['label'], 'Call API');
      expect(node.extra.keys,
          unorderedEquals(['position', 'measured', 'selected', 'dragging', 'parentId', 'zIndex']));
      expect(node.extra['parentId'], isNull);
      expect(node.extra.containsKey('parentId'), isTrue);
    });

    test('typed fields win over extra keys with the same name', () {
      const node = WorkflowUINode(id: 'n1', type: 'a', extra: {
        'id': 'other',
        'type': 'b',
        'position': {'x': 1}
      });
      expect(node.toJson(), {
        'id': 'n1',
        'type': 'a',
        'position': {'x': 1}
      });
    });

    test('a whole workflow graph survives a client round trip', () async {
      final wf = Workflow.fromJson(jsonDecode(jsonEncode(_workflow)) as Map<String, dynamic>);
      final body = jsonDecode(jsonEncode(wf)) as Map<String, dynamic>;
      expect(body['ui'], _ui);
    });
  });

  group('lenient decoding', () {
    test('required fields fall back to empty values', () {
      final wf = Workflow.fromJson(const {});
      expect(wf.name, '');
      expect(wf.ui.nodes, isEmpty);
      expect(wf.ui.edges, isEmpty);
      expect(WorkflowUINode.fromJson(const {}).id, '');
      expect(ActivityHistoryResponse.fromJson(const {}).history.activityId, '');
    });

    test('numbers and booleans sent as strings are coerced', () {
      final wf = Workflow.fromJson(const {'name': 'x', 'version': '4', 'published': 'true'});
      expect(wf.version, 4);
      expect(wf.published, isTrue);
    });

    test('toJson omits null fields', () {
      expect(const Environment(name: 'dev').toJson(), {'name': 'dev'});
      expect(const RunWorkflowRequest(workflowId: 'w1').toJson(), {'workflowId': 'w1'});
      expect(const WorkflowUINode(id: 'n').toJson(), {'id': 'n'});
    });
  });
}
