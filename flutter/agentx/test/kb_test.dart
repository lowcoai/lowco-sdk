import 'package:http/http.dart' as http;
import 'package:lowcoai_agentx/lowcoai_agentx.dart';
import 'package:test/test.dart';

import 'support.dart';

const _kb = '/v1/agentx/kb';

void main() {
  group('KBClient', () {
    runEndpoints([
      Endpoint(
        'health hits the host root',
        (c) => c.kb.health(),
        method: 'GET',
        path: '/health',
        response: () => http.Response('OK', 200),
      ),
      // --- Knowledge bases ------------------------------------------------
      Endpoint(
        'listKnowledgeBases',
        (c) => c.kb.listKnowledgeBases(const ListParams(pageNo: 1, size: 25)),
        method: 'GET',
        path: '$_kb/knowledges',
        query: {'pageNo': '1', 'size': '25'},
        response: () => envelope([
          {'id': 'k1', 'name': 'docs', 'connectionId': 'q1', 'modelId': 'm1'}
        ]),
        check: (r) {
          final kb = (r as List<KnowledgeBase>).single;
          expect(kb.connectionId, 'q1');
          expect(kb.modelId, 'm1');
        },
      ),
      Endpoint(
        'createKnowledgeBase',
        (c) => c.kb.createKnowledgeBase(const KnowledgeBase(name: 'docs', modelId: 'm1')),
        method: 'POST',
        path: '$_kb/knowledges',
        body: {'name': 'docs', 'modelId': 'm1'},
        response: () => envelope({'id': 'k1'}),
        check: (r) => expect((r as KnowledgeBase).id, 'k1'),
      ),
      Endpoint(
        'getKnowledgeBase',
        (c) => c.kb.getKnowledgeBase('k1'),
        method: 'GET',
        path: '$_kb/knowledges/k1',
      ),
      Endpoint(
        'updateKnowledgeBase',
        (c) => c.kb.updateKnowledgeBase('k1', const KnowledgeBase(description: 'd')),
        method: 'PUT',
        path: '$_kb/knowledges/k1',
        body: {'description': 'd'},
      ),
      Endpoint(
        'getKnowledgeBaseCount returns the raw integer',
        (c) => c.kb.getKnowledgeBaseCount(const ListParams(filter: "name='docs'")),
        method: 'GET',
        path: '$_kb/knowledges/count',
        query: {'filter': "name='docs'"},
        response: () => jsonResponse(9),
        check: (r) => expect(r, 9),
      ),
      // --- Datasets -------------------------------------------------------
      Endpoint(
        'listDatasets',
        (c) => c.kb.listDatasets(const ListParams(sort: 'name')),
        method: 'GET',
        path: '$_kb/datasets',
        query: {'sort': 'name'},
        response: () => envelope([
          {'id': 'd1', 'knowledgeBaseId': 'k1', 'content': 'text'}
        ]),
        check: (r) => expect((r as List<Dataset>).single.knowledgeBaseId, 'k1'),
      ),
      Endpoint(
        'createDataset',
        (c) => c.kb.createDataset(const Dataset(name: 'faq', knowledgeBaseId: 'k1')),
        method: 'POST',
        path: '$_kb/datasets',
        body: {'name': 'faq', 'knowledgeBaseId': 'k1'},
      ),
      Endpoint(
        'getDataset',
        (c) => c.kb.getDataset('d1'),
        method: 'GET',
        path: '$_kb/datasets/d1',
        response: () => envelope({'id': 'd1', 'name': 'faq'}),
        check: (r) => expect((r as Dataset).name, 'faq'),
      ),
      Endpoint(
        'updateDataset',
        (c) => c.kb.updateDataset('d1', const Dataset(content: 'new')),
        method: 'PUT',
        path: '$_kb/datasets/d1',
        body: {'content': 'new'},
      ),
      Endpoint(
        'deleteDataset',
        (c) => c.kb.deleteDataset('d1'),
        method: 'DELETE',
        path: '$_kb/datasets/d1',
        response: () => http.Response('', 204),
      ),
      Endpoint(
        'getDatasetCount returns the raw integer',
        (c) => c.kb.getDatasetCount(),
        method: 'GET',
        path: '$_kb/datasets/count',
        response: () => jsonResponse(0),
        check: (r) => expect(r, 0),
      ),
      // --- Embeddings -----------------------------------------------------
      Endpoint(
        'storeEmbeddings returns the message',
        (c) => c.kb.storeEmbeddings(const EmbeddingDbRequest(
            modelId: 'm1', texts: 'hello', collection: 'kb_k1', distance: 'Cosine')),
        method: 'POST',
        path: '$_kb/embeddings',
        body: {'modelId': 'm1', 'texts': 'hello', 'collection': 'kb_k1', 'distance': 'Cosine'},
        response: () => envelope('embeddings stored'),
        check: (r) => expect(r, 'embeddings stored'),
      ),
    ]);

    test('storeEmbeddings with no data yields an empty string', () async {
      expect(
          await Recorder((_) => envelope(null))
              .client()
              .kb
              .storeEmbeddings(const EmbeddingDbRequest()),
          '');
    });
  });
}
