import 'models.dart';
import 'transport.dart';

/// The agent-manager service routes (agents, versions, published agents, LLM
/// models, conversations).
///
/// Obtain it from `AgentxClient.manager`; the constructor is internal.
class ManagerClient {
  ManagerClient(this._t, String apiBasePath) : _base = trimSlashes(apiBasePath);

  final Transport _t;
  final String _base;

  String _path(List<String> parts) => _t.joinPath(_base, parts);

  // --- Health --------------------------------------------------------------

  /// `GET /health` at the host root.
  Future<void> health() => _t.requestVoid('GET', '/health');

  // --- Agents --------------------------------------------------------------

  Future<List<Agent>> listAgents([ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['agents']), query: params?.toQuery(), enveloped: true),
      Agent.fromJson);

  Future<Agent> getAgent(String id) async =>
      decodeOne(await _t.request('GET', _path(['agents', id]), enveloped: true), Agent.fromJson);

  Future<Agent> createAgent(Agent agent) async => decodeOne(
      await _t.request('POST', _path(['agents']), body: agent, enveloped: true), Agent.fromJson);

  Future<Agent> updateAgent(String id, Agent agent) async => decodeOne(
      await _t.request('PUT', _path(['agents', id]), body: agent, enveloped: true), Agent.fromJson);

  Future<Agent> patchAgent(String id, AgentPatch patch) async => decodeOne(
      await _t.request('PATCH', _path(['agents', id]), body: patch, enveloped: true),
      Agent.fromJson);

  /// The `/agents/count` endpoint returns a raw integer, not an envelope.
  Future<int> getAgentCount([ListParams? params]) async => decodeCount(await _t
      .request('GET', _path(['agents', 'count']), query: params?.toQuery(), enveloped: false));

  Future<void> deleteAgent(String id) => _t.requestVoid('DELETE', _path(['agents', id]));

  /// Deletes several agents in one call (`POST /agents/bulk-delete`).
  Future<void> bulkDeleteAgents(List<String> ids) =>
      _t.requestVoid('POST', _path(['agents', 'bulk-delete']), body: {'ids': ids});

  Future<List<AgentHistory>> getAgentVersions(String id, [ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['agents', id, 'versions']),
          query: params?.toQuery(), enveloped: true),
      AgentHistory.fromJson);

  // --- Published agents ----------------------------------------------------

  Future<AgentPublish> publishAgent(String agentId, PublishAgentRequest req) async => decodeOne(
      await _t.request('POST', _path(['agents', agentId, 'publish']), body: req, enveloped: true),
      AgentPublish.fromJson);

  Future<AgentPublish> getPublishedAgent(String id) async => decodeOne(
      await _t.request('GET', _path(['agents', 'published', id]), enveloped: true),
      AgentPublish.fromJson);

  Future<AgentPublish> updatePublishedAgent(String id, UpdatePublishedAgentRequest req) async =>
      decodeOne(
          await _t.request('PUT', _path(['agents', 'published', id]), body: req, enveloped: true),
          AgentPublish.fromJson);

  Future<void> deletePublishedAgent(String id) =>
      _t.requestVoid('DELETE', _path(['agents', 'published', id]));

  Future<List<AgentPublish>> listPublishedAgents([ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['agents', 'published']),
          query: params?.toQuery(), enveloped: true),
      AgentPublish.fromJson);

  // --- LLM models ----------------------------------------------------------

  Future<LlmModel> createModel(LlmModel model) async => decodeOne(
      await _t.request('POST', _path(['models']), body: model, enveloped: true), LlmModel.fromJson);

  Future<LlmModel> getModel(String id) async =>
      decodeOne(await _t.request('GET', _path(['models', id]), enveloped: true), LlmModel.fromJson);

  Future<LlmModel> updateModel(String id, LlmModel model) async => decodeOne(
      await _t.request('PUT', _path(['models', id]), body: model, enveloped: true),
      LlmModel.fromJson);

  Future<List<LlmModel>> listModels([ListParams? params]) async => decodeMany(
      await _t.request('GET', _path(['models']), query: params?.toQuery(), enveloped: true),
      LlmModel.fromJson);

  Future<void> deleteModel(String id) => _t.requestVoid('DELETE', _path(['models', id]));

  /// Enables a model, sending `{"properties": properties}`.
  Future<LlmModel> enableModel(String id, Map<String, dynamic> properties) async => decodeOne(
      await _t.request('PATCH', _path(['models', id, 'enable']),
          body: {'properties': properties}, enveloped: true),
      LlmModel.fromJson);

  Future<LlmModel> disableModel(String id) async => decodeOne(
      await _t.request('PATCH', _path(['models', id, 'disable']), enveloped: true),
      LlmModel.fromJson);

  // --- Conversations -------------------------------------------------------

  Future<List<Conversation>> listConversationsByAgent(String agentId, [ListParams? params]) async =>
      decodeMany(
          await _t.request('GET', _path(['conversations', agentId]),
              query: params?.toQuery(), enveloped: true),
          Conversation.fromJson);

  /// Starts a conversation with [agentId] (`POST /conversations`).
  Future<Conversation> createConversation(String agentId) async => decodeOne(
      await _t.request('POST', _path(['conversations']),
          body: {'agentId': agentId}, enveloped: true),
      Conversation.fromJson);

  Future<void> deleteConversation(String id) =>
      _t.requestVoid('DELETE', _path(['conversations', id]));

  Future<List<ConversationMessage>> getConversationMessages(String conversationId) async =>
      decodeMany(
          await _t.request('GET', _path(['conversations', conversationId, 'messages']),
              enveloped: true),
          ConversationMessage.fromJson);
}
