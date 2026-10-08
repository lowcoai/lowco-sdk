import 'package:http/http.dart' as http;
import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

import 'support.dart';

const _m = '/v1/agentx/manager';

void main() {
  group('ManagerClient', () {
    runEndpoints([
      Endpoint(
        'health hits the host root and accepts plain text',
        (c) => c.manager.health(),
        method: 'GET',
        path: '/health',
        response: () => http.Response('OK', 200),
      ),
      // --- Agents ---------------------------------------------------------
      Endpoint(
        'listAgents with ListParams',
        (c) => c.manager.listAgents(
            const ListParams(pageNo: 2, size: 10, filter: "name='bot'", sort: '-createdAt')),
        method: 'GET',
        path: '$_m/agents',
        query: {'pageNo': '2', 'size': '10', 'filter': "name='bot'", 'sort': '-createdAt'},
        response: () => envelope([
          {
            'id': 'a1',
            'name': 'bot',
            'tools': [
              {'id': 't1', 'source': 'mcp', 'sourceId': 's1', 'name': 'search'}
            ],
            'configurations': {'maxTokens': 1024, 'temperature': 1, 'topK': 5},
            'modelId': 'm1',
          }
        ]),
        check: (r) {
          final agent = (r as List<Agent>).single;
          expect(agent.id, 'a1');
          expect(agent.tools!.single.source, 'mcp');
          expect(agent.configurations!.temperature, 1.0);
          expect(agent.configurations!.maxTokens, 1024);
          expect(agent.modelId, 'm1');
        },
      ),
      Endpoint(
        'listAgents without params sends no query',
        (c) => c.manager.listAgents(),
        method: 'GET',
        path: '$_m/agents',
        response: () => envelope(null),
        check: (r) => expect(r, isEmpty),
      ),
      Endpoint(
        'getAgent',
        (c) => c.manager.getAgent('a1'),
        method: 'GET',
        path: '$_m/agents/a1',
        response: () => envelope({'id': 'a1', 'published': true, 'version': 3}),
        check: (r) {
          expect((r as Agent).published, isTrue);
          expect(r.version, 3);
        },
      ),
      Endpoint(
        'createAgent omits null fields',
        (c) => c.manager
            .createAgent(const Agent(name: 'bot', outputMode: 'last_message', tags: ['x'])),
        method: 'POST',
        path: '$_m/agents',
        body: {
          'name': 'bot',
          'outputMode': 'last_message',
          'tags': ['x']
        },
        response: () => envelope({'id': 'a1', 'name': 'bot'}),
        check: (r) => expect((r as Agent).id, 'a1'),
      ),
      Endpoint(
        'updateAgent',
        (c) => c.manager.updateAgent('a1', const Agent(prompt: 'be nice')),
        method: 'PUT',
        path: '$_m/agents/a1',
        body: {'prompt': 'be nice'},
      ),
      Endpoint(
        'patchAgent',
        (c) => c.manager.patchAgent('a1', const AgentPatch(tags: ['a', 'b'])),
        method: 'PATCH',
        path: '$_m/agents/a1',
        body: {
          'tags': ['a', 'b']
        },
      ),
      Endpoint(
        'getAgentCount returns the raw integer',
        (c) => c.manager.getAgentCount(const ListParams(filter: 'published=true')),
        method: 'GET',
        path: '$_m/agents/count',
        query: {'filter': 'published=true'},
        response: () => jsonResponse(42),
        check: (r) => expect(r, 42),
      ),
      Endpoint(
        'deleteAgent ignores the success body',
        (c) => c.manager.deleteAgent('a1'),
        method: 'DELETE',
        path: '$_m/agents/a1',
        response: () => http.Response('deleted', 200),
      ),
      Endpoint(
        'bulkDeleteAgents posts the ids',
        (c) => c.manager.bulkDeleteAgents(['a1', 'a2']),
        method: 'POST',
        path: '$_m/agents/bulk-delete',
        body: {
          'ids': ['a1', 'a2']
        },
        response: () => http.Response('', 204),
      ),
      Endpoint(
        'getAgentVersions',
        (c) => c.manager.getAgentVersions('a1', const ListParams(size: 5)),
        method: 'GET',
        path: '$_m/agents/a1/versions',
        query: {'size': '5'},
        response: () => envelope([
          {
            'id': 'h1',
            'comment': 'v2',
            'agent': {'name': 'bot'}
          }
        ]),
        check: (r) {
          final h = (r as List<AgentHistory>).single;
          expect(h.comment, 'v2');
          expect(h.agent!.name, 'bot');
        },
      ),
      // --- Published agents ----------------------------------------------
      Endpoint(
        'publishAgent',
        (c) => c.manager.publishAgent('a1', const PublishAgentRequest(category: 'sales')),
        method: 'POST',
        path: '$_m/agents/a1/publish',
        body: {'category': 'sales'},
        response: () => envelope({'id': 'p1', 'agentId': 'a1'}),
        check: (r) => expect((r as AgentPublish).agentId, 'a1'),
      ),
      Endpoint(
        'getPublishedAgent',
        (c) => c.manager.getPublishedAgent('p1'),
        method: 'GET',
        path: '$_m/agents/published/p1',
      ),
      Endpoint(
        'updatePublishedAgent',
        (c) => c.manager
            .updatePublishedAgent('p1', const UpdatePublishedAgentRequest(longDescription: 'l')),
        method: 'PUT',
        path: '$_m/agents/published/p1',
        body: {'longDescription': 'l'},
      ),
      Endpoint(
        'deletePublishedAgent',
        (c) => c.manager.deletePublishedAgent('p1'),
        method: 'DELETE',
        path: '$_m/agents/published/p1',
      ),
      Endpoint(
        'listPublishedAgents',
        (c) => c.manager.listPublishedAgents(const ListParams(pageNo: 1)),
        method: 'GET',
        path: '$_m/agents/published',
        query: {'pageNo': '1'},
        response: () => envelope([
          {'id': 'p1', 'latestVersion': 4}
        ]),
        check: (r) => expect((r as List<AgentPublish>).single.latestVersion, 4),
      ),
      // --- LLM models -----------------------------------------------------
      Endpoint(
        'createModel',
        (c) => c.manager.createModel(const LlmModel(
            name: 'gpt', provider: 'openai', config: {'baseUrl': 'x'}, embedding: false)),
        method: 'POST',
        path: '$_m/models',
        body: {
          'name': 'gpt',
          'provider': 'openai',
          'config': {'baseUrl': 'x'},
          'embedding': false
        },
      ),
      Endpoint(
        'getModel',
        (c) => c.manager.getModel('m1'),
        method: 'GET',
        path: '$_m/models/m1',
        response: () => envelope({'id': 'm1', 'disabled': true}),
        check: (r) => expect((r as LlmModel).disabled, isTrue),
      ),
      Endpoint(
        'updateModel',
        (c) => c.manager.updateModel('m1', const LlmModel(description: 'd')),
        method: 'PUT',
        path: '$_m/models/m1',
        body: {'description': 'd'},
      ),
      Endpoint(
        'listModels',
        (c) => c.manager.listModels(),
        method: 'GET',
        path: '$_m/models',
        response: () => envelope([
          {'id': 'm1'},
          {'id': 'm2'}
        ]),
        check: (r) => expect((r as List<LlmModel>).map((m) => m.id), ['m1', 'm2']),
      ),
      Endpoint(
        'deleteModel',
        (c) => c.manager.deleteModel('m1'),
        method: 'DELETE',
        path: '$_m/models/m1',
      ),
      Endpoint(
        'enableModel wraps the properties',
        (c) => c.manager.enableModel('m1', {'apiKey': 'k', 'n': 1}),
        method: 'PATCH',
        path: '$_m/models/m1/enable',
        body: {
          'properties': {'apiKey': 'k', 'n': 1}
        },
        response: () => envelope({'id': 'm1', 'disabled': false}),
        check: (r) => expect((r as LlmModel).disabled, isFalse),
      ),
      Endpoint(
        'disableModel sends no body',
        (c) => c.manager.disableModel('m1'),
        method: 'PATCH',
        path: '$_m/models/m1/disable',
      ),
      // --- Conversations --------------------------------------------------
      Endpoint(
        'listConversationsByAgent decodes both MessageContent shapes',
        (c) => c.manager.listConversationsByAgent('a1', const ListParams(size: 20)),
        method: 'GET',
        path: '$_m/conversations/a1',
        query: {'size': '20'},
        response: () => envelope([
          {'id': 'c1', 'lastMessage': 'hello', 'count': 2},
          {
            'id': 'c2',
            'lastMessage': [
              {'type': 'text', 'text': 'hi'}
            ]
          },
        ]),
        check: (r) {
          final list = r as List<Conversation>;
          expect(list[0].lastMessage, 'hello');
          expect(list[0].count, 2);
          expect(list[1].lastMessage, [
            {'type': 'text', 'text': 'hi'}
          ]);
        },
      ),
      Endpoint(
        'createConversation posts the agent id',
        (c) => c.manager.createConversation('a1'),
        method: 'POST',
        path: '$_m/conversations',
        body: {'agentId': 'a1'},
        response: () => envelope({'id': 'c1', 'welcomeMessage': 'Hi!'}),
        check: (r) => expect((r as Conversation).welcomeMessage, 'Hi!'),
      ),
      Endpoint(
        'deleteConversation',
        (c) => c.manager.deleteConversation('c1'),
        method: 'DELETE',
        path: '$_m/conversations/c1',
      ),
      Endpoint(
        'getConversationMessages',
        (c) => c.manager.getConversationMessages('c1'),
        method: 'GET',
        path: '$_m/conversations/c1/messages',
        response: () => envelope([
          {
            'id': 'x1',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'hi'}
            ],
            'metadata': {'tokens': 3},
          }
        ]),
        check: (r) {
          final msg = (r as List<ConversationMessage>).single;
          expect(msg.role, 'assistant');
          expect(msg.content, isA<List<Object?>>());
          expect(msg.metadata, {'tokens': 3});
        },
      ),
    ]);

    test('path segments are escaped and slash-trimmed', () async {
      final rec = Recorder();
      await rec.client().manager.getAgent('a b/c?');
      expect(rec.last.url.toString(), 'https://api.lowco.ai/v1/agentx/manager/agents/a%20b%2Fc%3F');
      await rec.client().manager.getModel('/m1/');
      expect(rec.last.url.path, '$_m/models/m1');
    });

    test('count endpoints decode leniently', () async {
      expect(await Recorder((_) => jsonResponse('7')).client().manager.getAgentCount(), 7);
      expect(await Recorder((_) => envelope(3)).client().manager.getAgentCount(), 3); // enveloped
      expect(await Recorder((_) => http.Response('', 204)).client().manager.getAgentCount(), 0);
    });

    test('null data decodes to empty models', () async {
      final rec = Recorder((_) => envelope(null));
      expect((await rec.client().manager.getAgent('a1')).id, isNull);
      expect(await rec.client().manager.getConversationMessages('c1'), isEmpty);
    });
  });
}
