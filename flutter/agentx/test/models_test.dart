import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

/// Exhaustive over the sealed hierarchy: adding a subclass breaks the build.
String describe(Part part) => switch (part) {
      TextPart(:final text) => 'text:$text',
      FilePart(file: FileWithBytes(:final bytes)) => 'bytes:$bytes',
      FilePart(file: FileWithURI(:final uri)) => 'uri:$uri',
      DataPart(:final data) => 'data:${data.keys.join(',')}',
      UnknownPart(:final kind) => 'unknown:$kind',
    };

void main() {
  group('Part', () {
    test('decodes each kind', () {
      final parts = [
        {
          'kind': 'text',
          'text': 'hi',
          'metadata': {'lang': 'en'}
        },
        {
          'kind': 'file',
          'file': {'name': 'a.png', 'mimeType': 'image/png', 'bytes': 'AAEC'}
        },
        {
          'kind': 'file',
          'file': {'uri': 'https://x/a.pdf'}
        },
        {
          'kind': 'data',
          'data': {'a': 1, 'b': 2}
        },
      ].map(Part.fromJson).toList();
      expect(parts.map(describe), ['text:hi', 'bytes:AAEC', 'uri:https://x/a.pdf', 'data:a,b']);
      expect(parts.map((p) => p.kind), ['text', 'file', 'file', 'data']);
      expect(parts.first.metadata, {'lang': 'en'});
      final file = (parts[1] as FilePart).file;
      expect(file.name, 'a.png');
      expect(file.mimeType, 'image/png');
    });

    test('unknown kinds keep the raw map and never throw', () {
      final raw = {
        'kind': 'audio',
        'audio': {'url': 'x'},
        'metadata': {'m': 1}
      };
      final part = Part.fromJson(raw);
      expect(part, isA<UnknownPart>());
      expect(part.kind, 'audio');
      expect(part.metadata, {'m': 1});
      expect(part.toJson(), raw);
      expect((part as UnknownPart).raw, raw);
    });

    test('missing kind or a malformed known kind becomes UnknownPart', () {
      for (final raw in <Map<String, dynamic>>[
        {},
        {'text': 'no kind'},
        {'kind': 7},
        {'kind': 'text'},
        {'kind': 'text', 'text': 1},
        {'kind': 'file', 'file': 'not-a-map'},
        {'kind': 'data', 'data': null},
        {'kind': 'data', 'data': []},
      ]) {
        final part = Part.fromJson(raw);
        expect(part, isA<UnknownPart>(), reason: '$raw');
        expect(part.toJson(), raw);
      }
      expect(Part.fromJson({'kind': 7}).kind, '7');
      expect(Part.fromJson({}).kind, '');
    });

    test('toJson emits kind and omits null metadata', () {
      expect(const TextPart(text: 'hi').toJson(), {'kind': 'text', 'text': 'hi'});
      expect(const DataPart(data: {'x': 1}, metadata: {'m': true}).toJson(), {
        'kind': 'data',
        'data': {'x': 1},
        'metadata': {'m': true}
      });
      expect(const FilePart(file: FileWithURI(uri: 'u')).toJson(), {
        'kind': 'file',
        'file': {'uri': 'u'}
      });
      expect(const FilePart(file: FileWithBytes(bytes: 'b', name: 'n')).toJson(), {
        'kind': 'file',
        'file': {'name': 'n', 'bytes': 'b'}
      });
    });
  });

  group('FilePayload', () {
    test('is chosen by the presence of bytes vs uri', () {
      expect(FilePayload.fromJson({'bytes': 'AA'}), isA<FileWithBytes>());
      expect(FilePayload.fromJson({'uri': 'u'}), isA<FileWithURI>());
      // Both present: bytes win.
      final both = FilePayload.fromJson({'bytes': 'AA', 'uri': 'u'});
      expect((both as FileWithBytes).bytes, 'AA');
      // Neither: an empty URI rather than an exception.
      final neither = FilePayload.fromJson({'name': 'x'});
      expect((neither as FileWithURI).uri, '');
      expect(neither.name, 'x');
    });
  });

  group('A2AMessage', () {
    test('round-trips', () {
      final json = {
        'role': 'assistant',
        'parts': [
          {'kind': 'text', 'text': 'hi'},
          {'kind': 'mystery', 'x': 1},
        ],
        'messageId': 'm1',
        'kind': 'message',
        'metadata': {'memberId': 'a1'},
        'extensions': ['e1'],
        'referenceTaskIds': ['t0'],
        'taskId': 't1',
        'contextId': 'c1',
      };
      final msg = A2AMessage.fromJson(json);
      expect(msg.parts.map((p) => p.runtimeType), [TextPart, UnknownPart]);
      expect(msg.toJson(), json);
    });

    test('defaults and null omission', () {
      const msg = A2AMessage(role: 'user', parts: [], messageId: 'm1');
      expect(msg.kind, 'message');
      expect(msg.toJson(), {'role': 'user', 'parts': [], 'messageId': 'm1', 'kind': 'message'});
    });

    test('decodes an empty object leniently', () {
      final msg = A2AMessage.fromJson({});
      expect(msg.role, '');
      expect(msg.parts, isEmpty);
      expect(msg.messageId, '');
      expect(msg.kind, 'message');
    });
  });

  group('send params', () {
    test('toJson nests and omits nulls', () {
      const params = MessageSendParams(
        message: A2AMessage(role: 'user', parts: [TextPart(text: 'q')], messageId: 'm1'),
        configuration: MessageSendConfiguration(
          acceptedOutputModes: ['text'],
          historyLength: 5,
          pushNotificationConfig: PushNotificationConfig(
            url: 'https://hook',
            authentication: PushNotificationAuthenticationInfo(schemes: ['Bearer']),
          ),
        ),
        metadata: {'k': 'v'},
      );
      final json = params.toJson();
      expect(json, {
        'message': {
          'role': 'user',
          'parts': [
            {'kind': 'text', 'text': 'q'}
          ],
          'messageId': 'm1',
          'kind': 'message',
        },
        'configuration': {
          'acceptedOutputModes': ['text'],
          'historyLength': 5,
          'pushNotificationConfig': {
            'url': 'https://hook',
            'authentication': {
              'schemes': ['Bearer']
            },
          },
        },
        'metadata': {'k': 'v'},
      });
      expect(MessageSendParams.fromJson(json).toJson(), json);
    });
  });

  group('JSON-RPC', () {
    test('request toJson omits null params and id', () {
      expect(const JSONRPCRequest(method: methodMessageSend).toJson(),
          {'jsonrpc': '2.0', 'method': 'message/send'});
    });

    test('response decodes result, error and a numeric id', () {
      final resp = JSONRPCResponse.fromJson({
        'jsonrpc': '2.0',
        'id': 3,
        'error': {'code': A2AErrorCodes.taskNotFound, 'message': 'no task'},
      });
      expect(resp.id, 3);
      expect(resp.error!.code, -32001);
      expect(resp.toJson(), {
        'jsonrpc': '2.0',
        'error': {'code': -32001, 'message': 'no task'},
        'id': 3
      });
      expect(const JSONRPCResponse().toJson(), {'jsonrpc': '2.0'});
    });

    test('error codes mirror the TypeScript constants', () {
      expect(JSONRPCErrorCodes.parseError, -32700);
      expect(JSONRPCErrorCodes.invalidRequest, -32600);
      expect(JSONRPCErrorCodes.methodNotFound, -32601);
      expect(JSONRPCErrorCodes.invalidParams, -32602);
      expect(JSONRPCErrorCodes.internalError, -32603);
      expect(A2AErrorCodes.taskNotFound, -32001);
      expect(A2AErrorCodes.taskNotCancelable, -32002);
      expect(A2AErrorCodes.pushNotificationNotSupported, -32003);
      expect(A2AErrorCodes.unsupportedOperation, -32004);
      expect(A2AErrorCodes.contentTypeNotSupported, -32005);
      expect(A2AErrorCodes.invalidAgentResponse, -32006);
    });
  });

  group('tryParseMessage', () {
    test('decodes a JSON object', () {
      final msg = tryParseMessage(const StreamEvent(
          '{"kind":"message","role":"assistant","messageId":"r1","parts":[{"kind":"text","text":"x"}]}'));
      expect(msg!.messageId, 'r1');
      expect((msg.parts.single as TextPart).text, 'x');
    });

    test('returns null for invalid JSON or a non-object', () {
      expect(tryParseMessage(const StreamEvent('not json')), isNull);
      expect(tryParseMessage(const StreamEvent('[1,2]')), isNull);
      expect(tryParseMessage(const StreamEvent('"text"')), isNull);
    });
  });

  group('manager / kb models', () {
    test('toJson omits null fields', () {
      expect(const Agent().toJson(), isEmpty);
      expect(
          const Agent(name: 'bot', published: false).toJson(), {'name': 'bot', 'published': false});
      expect(const LlmModel(id: 'm1', name: 'gpt').toJson(), {'id': 'm1', 'name': 'gpt'});
      expect(const Dataset().toJson(), isEmpty);
    });

    test('Agent decodes nested objects leniently', () {
      final agent = Agent.fromJson({
        'id': 'a1',
        'orgId': 'o1',
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': null,
        'configurations': {'maxTokens': '256', 'temperature': 0.2, 'topK': 3.0},
        'capabilities': {'streaming': true, 'pushNotifications': 'false'},
        'skills': [
          {
            'id': 's1',
            'name': ['search'],
            'tags': ['web'],
            'inputModes': ['text']
          },
          'garbage',
        ],
        'routingConfig': {'haltCondition': 'done'},
        'applicationWithCredential': {'slack': 'cred_1'},
        'subAgentPattern': 'supervisor',
        'subAgents': ['a2'],
        'memoryType': 'lowco',
        'knowledgeBaseIds': ['k1'],
        'version': 2,
      });
      expect(agent.orgId, 'o1');
      expect(agent.createdAt, '2026-01-01T00:00:00Z');
      expect(agent.updatedAt, isNull);
      expect(agent.configurations!.maxTokens, 256);
      expect(agent.configurations!.temperature, 0.2);
      expect(agent.configurations!.topK, 3);
      expect(agent.capabilities!.streaming, isTrue);
      expect(agent.capabilities!.pushNotifications, isFalse);
      expect(agent.skills!.single.name, ['search']);
      expect(agent.routingConfig!.haltCondition, 'done');
      expect(agent.applicationWithCredential, {'slack': 'cred_1'});
      expect(agent.subAgentPattern, 'supervisor');
      expect(agent.knowledgeBaseIds, ['k1']);
      expect(Agent.fromJson(agent.toJson()).toJson(), agent.toJson());
    });

    test('AgentPublish carries a nested agent', () {
      final p = AgentPublish.fromJson({
        'id': 'p1',
        'agent': {'name': 'bot'},
        'sourceOrgId': 'o1',
        'category': 'sales',
      });
      expect(p.agent!.name, 'bot');
      expect(p.toJson(), {
        'id': 'p1',
        'agent': {'name': 'bot'},
        'sourceOrgId': 'o1',
        'category': 'sales',
      });
    });

    test('APIErrorPayload and AgentInfo', () {
      final e = APIErrorPayload.fromJson({
        'code': 404,
        'message': 'nope',
        'details': {'id': 'x'}
      });
      expect(e.code, '404');
      expect(e.details, {'id': 'x'});
      expect(AgentInfo.fromJson({'id': 'a1', 'welcomeMessage': 'hi'}).welcomeMessage, 'hi');
    });
  });
}
