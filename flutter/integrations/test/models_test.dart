import 'dart:convert';

import 'package:lowcoai_integrations/lowcoai_integrations.dart';
import 'package:test/test.dart';

const _meta = {
  'id': 'id1',
  'orgId': 'org_1',
  'createdBy': 'u1',
  'updatedBy': 'u2',
  'createdAt': '2026-01-02T03:04:05Z',
  'updatedAt': '2026-01-03T03:04:05Z',
};

const _application = {
  ..._meta,
  'name': 'Slack',
  'description': 'Chat',
  'icon': 'https://icon',
  'type': 'http',
  'subType': 'oauth2',
  'operationConfig': {'baseUrl': 'https://slack.com/api'},
  'authConfig': {'clientId': 'x'},
  'supportProtocol': ['rest', 'mcp'],
  'tags': ['chat'],
  'version': 2,
  'mcpKey': 'k1',
  'publishedUrl': 'https://mcp',
};

const _connection = {
  ..._meta,
  'name': 'Sales',
  'description': 'Sales workspace',
  'connectionType': 'oauth2',
  'applicationType': 'http',
  'applicationSubType': 'oauth2',
  'connectionStatus': 'active',
  'applicationId': 'a1',
  'properties': {'team': 'T1'},
  'isDefault': true,
};

const _authToken = {
  ..._meta,
  'requestId': 'r1',
  'applicationId': 'a1',
  'credentialId': 'c1',
  'token': 'tok',
  'refreshToken': 'ref',
  'expiresIn': 3600,
  'expiry': '2026-01-04T00:00:00Z',
  'tokenType': 'Bearer',
};

const _postman = {
  'name': 'Users',
  'description': 'User endpoints',
  'auth': {'type': 'bearer'},
  'event': [
    {'listen': 'prerequest'}
  ],
  'variable': null,
  'item': [
    {
      'name': 'List users',
      'request': {
        'method': 'GET',
        'url': {'raw': '{{baseUrl}}/users'},
      },
      'response': <Object>[],
      'id': 'req-1',
    },
    {
      'name': 'Admins',
      'item': [
        {
          'name': 'Promote',
          'request': {'method': 'POST'},
        },
      ],
    },
  ],
};

/// A full wire fixture per model; fromJson -> toJson must return it unchanged.
final fixtures =
    <String, (Map<String, dynamic>, Map<String, dynamic> Function(Map<String, dynamic>))>{
  'ApiEnvelope': (
    {
      'success': false,
      'code': 'E',
      'message': 'm',
      'data': {'a': 1},
      'error': 'boom'
    },
    (j) => ApiEnvelope.fromJson(j).toJson()
  ),
  'Application': (_application, (j) => Application.fromJson(j).toJson()),
  'ApplicationWithCount': (
    {..._application, 'count': 5},
    (j) => ApplicationWithCount.fromJson(j).toJson()
  ),
  'ApplicationWithConnection': (
    {
      ..._application,
      'connections': [_connection],
      'actionId': 'x1',
    },
    (j) => ApplicationWithConnection.fromJson(j).toJson()
  ),
  'ApplicationHistory': (
    {..._meta, 'application': _application, 'comment': 'v2'},
    (j) => ApplicationHistory.fromJson(j).toJson()
  ),
  'PatchTagsRequest': (
    {
      'tags': ['a', 'b']
    },
    (j) => PatchTagsRequest.fromJson(j).toJson()
  ),
  'RunApplicationRequest': (
    {
      'credentialId': 'c1',
      'inputBody': {'q': 1}
    },
    (j) => RunApplicationRequest.fromJson(j).toJson()
  ),
  'HttpActionType': (
    {
      'type': 'http',
      'metadata': {'method': 'POST'}
    },
    (j) => HttpActionType.fromJson(j).toJson()
  ),
  'ApplicationAction': (
    {
      ..._meta,
      'applicationId': 'a1',
      'name': 'Send',
      'groupName': 'Messages',
      'description': 'Send a message',
      'action': {
        'type': 'http',
        'metadata': {'path': '/chat.postMessage'}
      },
      'properties': [
        {'name': 'channel'}
      ],
    },
    (j) => ApplicationAction.fromJson(j).toJson()
  ),
  'RunActionRequest': (
    {
      'credentialId': 'c1',
      'inputBody': {'to': 'a'}
    },
    (j) => RunActionRequest.fromJson(j).toJson()
  ),
  'PostmanFolder': (_postman, (j) => PostmanFolder.fromJson(j).toJson()),
  'Connection': (_connection, (j) => Connection.fromJson(j).toJson()),
  'ConnectionResponse': (_connection, (j) => ConnectionResponse.fromJson(j).toJson()),
  'SetAsDefaultRequest': ({'applicationId': 'a1'}, (j) => SetAsDefaultRequest.fromJson(j).toJson()),
  'ApplicationTrigger': (
    {
      ..._meta,
      'name': 'on insert',
      'description': 'd',
      'operationConfig': {
        'table': 'leads',
        'events': ['insert']
      },
      'applicationId': 'a1',
      'webhookUrl': 'https://hook',
    },
    (j) => ApplicationTrigger.fromJson(j).toJson()
  ),
  'TriggerState': (
    {
      'triggerId': 't1',
      'orgId': 'org_1',
      'cursor': {'lsn': '0/16B6C50'},
      'lastRunAt': '2026-01-02T00:00:00Z',
      'lastError': 'e',
      'runCount': 9,
      'leasedBy': 'worker-1',
      'leasedUntil': '2026-01-02T00:01:00Z',
      'updatedAt': '2026-01-02T00:00:01Z',
    },
    (j) => TriggerState.fromJson(j).toJson()
  ),
  'ConnectionCreateRequest': (
    {'applicationId': 'a1', 'name': 'n', 'description': 'd'},
    (j) => ConnectionCreateRequest.fromJson(j).toJson()
  ),
  'CallbackRequest': ({'state': 's', 'code': 'c'}, (j) => CallbackRequest.fromJson(j).toJson()),
  'OAuthLoginUrl': ({'url': 'https://auth'}, (j) => OAuthLoginUrl.fromJson(j).toJson()),
  'OAuthCallbackResult': ({'success': 'ok'}, (j) => OAuthCallbackResult.fromJson(j).toJson()),
  'AuthToken': (_authToken, (j) => AuthToken.fromJson(j).toJson()),
  'RefreshExpiringTokensResult': (
    {
      'checked': 3,
      'refreshed': 1,
      'skipped': 1,
      'failed': 1,
      'refreshedTokens': [_authToken],
      'failures': [
        {'credentialId': 'c2', 'error': 'invalid_grant'}
      ],
    },
    (j) => RefreshExpiringTokensResult.fromJson(j).toJson()
  ),
  'JsonRpcRequest': (
    {
      'jsonrpc': '2.0',
      'id': 'req-1',
      'method': 'tools/call',
      'params': {
        'name': 'send',
        'arguments': {'to': 'a'}
      },
    },
    (j) => JsonRpcRequest.fromJson(j).toJson()
  ),
  'JsonRpcError': (
    {
      'code': -32602,
      'message': 'Invalid params',
      'data': {'field': 'to'}
    },
    (j) => JsonRpcError.fromJson(j).toJson()
  ),
  'JsonRpcResponse': (
    {
      'jsonrpc': '2.0',
      'id': 7,
      'result': {
        'content': [
          {'type': 'text', 'text': 'ok'}
        ]
      },
      'error': {'code': -1, 'message': 'x'},
    },
    (j) => JsonRpcResponse.fromJson(j).toJson()
  ),
  'McpToolsResponse': (
    {
      'tools': [
        {
          'name': 'send',
          'inputSchema': {'type': 'object'}
        }
      ]
    },
    (j) => McpToolsResponse.fromJson(j).toJson()
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

  group('PostmanFolder', () {
    test('keeps unknown keys in extra, recursively', () {
      final folder = PostmanFolder.fromJson(_postman);
      expect(folder.name, 'Users');
      expect(folder.extra.keys, unorderedEquals(['description', 'auth', 'event', 'variable']));
      expect(folder.extra.containsKey('variable'), isTrue);
      final request = folder.item!.first;
      expect(request.request!['method'], 'GET');
      expect(request.extra, {'response': <Object>[], 'id': 'req-1'});
      expect(folder.item![1].item!.single.name, 'Promote');
    });

    test('typed fields win over extra keys with the same name', () {
      const folder = PostmanFolder(name: 'a', extra: {'name': 'b', 'id': 'f1'});
      expect(folder.toJson(), {'name': 'a', 'id': 'f1'});
    });
  });

  group('lenient decoding', () {
    test('required fields fall back to empty values', () {
      final app = ApplicationWithConnection.fromJson(const {});
      expect(app.name, '');
      expect(app.type, '');
      expect(app.connections, isEmpty);
      expect(ApplicationAction.fromJson(const {}).action.type, '');
      expect(TriggerState.fromJson(const {}).runCount, 0);
    });

    test('numbers sent as strings are coerced', () {
      expect(TriggerState.fromJson(const {'triggerId': 't', 'runCount': '5'}).runCount, 5);
    });

    test('toJson omits null fields', () {
      expect(const ConnectionCreateRequest(applicationId: 'a1').toJson(), {'applicationId': 'a1'});
      expect(const JsonRpcRequest(jsonrpc: '2.0', method: 'ping').toJson(),
          {'jsonrpc': '2.0', 'method': 'ping'});
      expect(const PostmanFolder().toJson(), isEmpty);
    });
  });
}
