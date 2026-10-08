import 'dart:convert';

import 'models.dart';
import 'transport.dart';

/// The agent-kb (knowledge-base) service routes (knowledge bases, datasets,
/// embeddings).
///
/// Obtain it from `AgentxClient.kb`; the constructor is internal.
class KBClient {
  KBClient(this._t, String apiBasePath) : _base = trimSlashes(apiBasePath);

  final Transport _t;
  final String _base;

  String _path(List<String> parts) => _t.joinPath(_base, parts);

  // --- Health --------------------------------------------------------------

  /// `GET /health` at the host root.
  Future<void> health() => _t.requestVoid('GET', '/health');

  // --- Knowledge bases -----------------------------------------------------

  Future<List<KnowledgeBase>> listKnowledgeBases([ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['knowledges']), query: params?.toQuery(), enveloped: true),
      KnowledgeBase.fromJson);

  Future<KnowledgeBase> createKnowledgeBase(KnowledgeBase kb) async => decodeOne(
      await _t.request('POST', _path(['knowledges']), body: kb, enveloped: true),
      KnowledgeBase.fromJson);

  Future<KnowledgeBase> getKnowledgeBase(String id) async => decodeOne(
      await _t.request('GET', _path(['knowledges', id]), enveloped: true), KnowledgeBase.fromJson);

  Future<KnowledgeBase> updateKnowledgeBase(String id, KnowledgeBase kb) async => decodeOne(
      await _t.request('PUT', _path(['knowledges', id]), body: kb, enveloped: true),
      KnowledgeBase.fromJson);

  /// The `/knowledges/count` endpoint returns a raw integer, not an envelope.
  Future<int> getKnowledgeBaseCount([ListParams? params]) async => decodeCount(await _t
      .request('GET', _path(['knowledges', 'count']), query: params?.toQuery(), enveloped: false));

  // --- Datasets ------------------------------------------------------------

  Future<List<Dataset>> listDatasets([ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['datasets']), query: params?.toQuery(), enveloped: true),
      Dataset.fromJson);

  Future<Dataset> createDataset(Dataset dataset) async => decodeOne(
      await _t.request('POST', _path(['datasets']), body: dataset, enveloped: true),
      Dataset.fromJson);

  Future<Dataset> getDataset(String id) async => decodeOne(
      await _t.request('GET', _path(['datasets', id]), enveloped: true), Dataset.fromJson);

  Future<Dataset> updateDataset(String id, Dataset dataset) async => decodeOne(
      await _t.request('PUT', _path(['datasets', id]), body: dataset, enveloped: true),
      Dataset.fromJson);

  Future<void> deleteDataset(String id) => _t.requestVoid('DELETE', _path(['datasets', id]));

  /// The `/datasets/count` endpoint returns a raw integer, not an envelope.
  Future<int> getDatasetCount([ListParams? params]) async => decodeCount(await _t
      .request('GET', _path(['datasets', 'count']), query: params?.toQuery(), enveloped: false));

  // --- Embeddings ----------------------------------------------------------

  /// Persists embeddings into the vector store; returns the service's
  /// success message (empty when the service sends none).
  Future<String> storeEmbeddings(EmbeddingDbRequest req) async {
    final data = await _t.request('POST', _path(['embeddings']), body: req, enveloped: true);
    return data == null ? '' : (data is String ? data : jsonEncode(data));
  }
}
