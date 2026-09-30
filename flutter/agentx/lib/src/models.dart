// Wire models for the agentx manager and knowledge-base services. Field names
// match the JSON the services send and accept; `toJson` omits null fields so
// partial updates only send what you set.
//
// Generated with scratchpad/dartgen.py (specs/agentx_models.py); the executor
// (A2A / JSON-RPC) types live in a2a.dart.

import 'json.dart';

/// Conversation message content: either a plain [String] or a
/// `List<Map<String, dynamic>>` of content blocks. The agent-manager treats it
/// as opaque polymorphic JSON, so it is passed through untouched.
typedef MessageContent = Object?;

/// Metadata fields shared by every agentx entity.
abstract class BaseEntity {
  const BaseEntity({
    this.id,
    this.orgId,
    this.prn,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final String? id;
  final String? orgId;
  final String? prn;

  /// ISO-8601 timestamp.
  final String? createdAt;

  /// ISO-8601 timestamp.
  final String? updatedAt;

  final String? createdBy;
  final String? updatedBy;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (orgId != null) 'orgId': orgId,
        if (prn != null) 'prn': prn,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (createdBy != null) 'createdBy': createdBy,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };
}

/// The `error` object of the services' `{ success, data, error, message }` envelope.
class APIErrorPayload {
  const APIErrorPayload({
    this.code,
    this.message,
    this.details,
  });

  factory APIErrorPayload.fromJson(Map<String, dynamic> json) => APIErrorPayload(
        code: readString(json['code']),
        message: readString(json['message']),
        details: readMap(json['details']),
      );

  final String? code;
  final String? message;
  final Map<String, dynamic>? details;

  Map<String, dynamic> toJson() => {
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (details != null) 'details': details,
      };
}

class CustomRoutingConfig {
  const CustomRoutingConfig({
    this.haltCondition,
    this.routerFunction,
  });

  factory CustomRoutingConfig.fromJson(Map<String, dynamic> json) => CustomRoutingConfig(
        haltCondition: readString(json['haltCondition']),
        routerFunction: readString(json['routerFunction']),
      );

  final String? haltCondition;
  final String? routerFunction;

  Map<String, dynamic> toJson() => {
        if (haltCondition != null) 'haltCondition': haltCondition,
        if (routerFunction != null) 'routerFunction': routerFunction,
      };
}

class AgentTool {
  const AgentTool({
    this.id,
    this.source,
    this.sourceId,
    this.name,
  });

  factory AgentTool.fromJson(Map<String, dynamic> json) => AgentTool(
        id: readString(json['id']),
        source: readString(json['source']),
        sourceId: readString(json['sourceId']),
        name: readString(json['name']),
      );

  final String? id;
  final String? source;
  final String? sourceId;
  final String? name;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (source != null) 'source': source,
        if (sourceId != null) 'sourceId': sourceId,
        if (name != null) 'name': name,
      };
}

class AgentCapabilities {
  const AgentCapabilities({
    this.streaming,
    this.pushNotifications,
    this.stateTransitionHistory,
    this.extensions,
  });

  factory AgentCapabilities.fromJson(Map<String, dynamic> json) => AgentCapabilities(
        streaming: readBool(json['streaming']),
        pushNotifications: readBool(json['pushNotifications']),
        stateTransitionHistory: readBool(json['stateTransitionHistory']),
        extensions: readBool(json['extensions']),
      );

  final bool? streaming;
  final bool? pushNotifications;
  final bool? stateTransitionHistory;
  final bool? extensions;

  Map<String, dynamic> toJson() => {
        if (streaming != null) 'streaming': streaming,
        if (pushNotifications != null) 'pushNotifications': pushNotifications,
        if (stateTransitionHistory != null) 'stateTransitionHistory': stateTransitionHistory,
        if (extensions != null) 'extensions': extensions,
      };
}

class AgentSkill {
  const AgentSkill({
    this.id,
    this.description,
    this.name,
    this.tags,
    this.examples,
    this.inputModes,
    this.outputModes,
  });

  factory AgentSkill.fromJson(Map<String, dynamic> json) => AgentSkill(
        id: readString(json['id']),
        description: readString(json['description']),
        name: readStringList(json['name']),
        tags: readStringList(json['tags']),
        examples: readString(json['examples']),
        inputModes: readStringList(json['inputModes']),
        outputModes: readStringList(json['outputModes']),
      );

  final String? id;
  final String? description;
  final List<String>? name;
  final List<String>? tags;
  final String? examples;
  final List<String>? inputModes;
  final List<String>? outputModes;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (description != null) 'description': description,
        if (name != null) 'name': name,
        if (tags != null) 'tags': tags,
        if (examples != null) 'examples': examples,
        if (inputModes != null) 'inputModes': inputModes,
        if (outputModes != null) 'outputModes': outputModes,
      };
}

class AgentConfiguration {
  const AgentConfiguration({
    this.maxTokens,
    this.maxIterations,
    this.temperature,
    this.topK,
  });

  factory AgentConfiguration.fromJson(Map<String, dynamic> json) => AgentConfiguration(
        maxTokens: readInt(json['maxTokens']),
        maxIterations: readInt(json['maxIterations']),
        temperature: readDouble(json['temperature']),
        topK: readInt(json['topK']),
      );

  final int? maxTokens;
  final int? maxIterations;
  final double? temperature;
  final int? topK;

  Map<String, dynamic> toJson() => {
        if (maxTokens != null) 'maxTokens': maxTokens,
        if (maxIterations != null) 'maxIterations': maxIterations,
        if (temperature != null) 'temperature': temperature,
        if (topK != null) 'topK': topK,
      };
}

/// An agent definition managed by the agent-manager.
class Agent extends BaseEntity {
  const Agent({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.name,
    this.description,
    this.modelName,
    this.prompt,
    this.provider,
    this.tools,
    this.knowledgeBaseIds,
    this.configurations,
    this.outputMode,
    this.iconUrl,
    this.documentationUrl,
    this.capabilities,
    this.skills,
    this.memoryType,
    this.subAgentPattern,
    this.subAgents,
    this.routingConfig,
    this.published,
    this.version,
    this.applicationWithCredential,
    this.welcomeMessage,
    this.tags,
    this.modelId,
  });

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        name: readString(json['name']),
        description: readString(json['description']),
        modelName: readString(json['modelName']),
        prompt: readString(json['prompt']),
        provider: readString(json['provider']),
        tools: readObjectList(json['tools'], AgentTool.fromJson),
        knowledgeBaseIds: readStringList(json['knowledgeBaseIds']),
        configurations: readObject(json['configurations'], AgentConfiguration.fromJson),
        outputMode: readString(json['outputMode']),
        iconUrl: readString(json['iconUrl']),
        documentationUrl: readString(json['documentationUrl']),
        capabilities: readObject(json['capabilities'], AgentCapabilities.fromJson),
        skills: readObjectList(json['skills'], AgentSkill.fromJson),
        memoryType: readString(json['memoryType']),
        subAgentPattern: readString(json['subAgentPattern']),
        subAgents: readStringList(json['subAgents']),
        routingConfig: readObject(json['routingConfig'], CustomRoutingConfig.fromJson),
        published: readBool(json['published']),
        version: readInt(json['version']),
        applicationWithCredential: readStringMap(json['applicationWithCredential']),
        welcomeMessage: readString(json['welcomeMessage']),
        tags: readStringList(json['tags']),
        modelId: readString(json['modelId']),
      );

  final String? name;
  final String? description;
  final String? modelName;
  final String? prompt;
  final String? provider;
  final List<AgentTool>? tools;
  final List<String>? knowledgeBaseIds;
  final AgentConfiguration? configurations;

  /// `full_response` or `last_message`.
  final String? outputMode;

  final String? iconUrl;
  final String? documentationUrl;
  final AgentCapabilities? capabilities;
  final List<AgentSkill>? skills;

  /// `lowco`.
  final String? memoryType;

  /// Multi-agent pattern: `hierarchy`, `supervisor`, `network` or `planner`.
  final String? subAgentPattern;

  final List<String>? subAgents;
  final CustomRoutingConfig? routingConfig;
  final bool? published;
  final int? version;
  final Map<String, String>? applicationWithCredential;
  final String? welcomeMessage;
  final List<String>? tags;

  /// Server-enriched field populated by `listAgents`.
  final String? modelId;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (modelName != null) 'modelName': modelName,
        if (prompt != null) 'prompt': prompt,
        if (provider != null) 'provider': provider,
        if (tools != null) 'tools': tools!.map((e) => e.toJson()).toList(),
        if (knowledgeBaseIds != null) 'knowledgeBaseIds': knowledgeBaseIds,
        if (configurations != null) 'configurations': configurations!.toJson(),
        if (outputMode != null) 'outputMode': outputMode,
        if (iconUrl != null) 'iconUrl': iconUrl,
        if (documentationUrl != null) 'documentationUrl': documentationUrl,
        if (capabilities != null) 'capabilities': capabilities!.toJson(),
        if (skills != null) 'skills': skills!.map((e) => e.toJson()).toList(),
        if (memoryType != null) 'memoryType': memoryType,
        if (subAgentPattern != null) 'subAgentPattern': subAgentPattern,
        if (subAgents != null) 'subAgents': subAgents,
        if (routingConfig != null) 'routingConfig': routingConfig!.toJson(),
        if (published != null) 'published': published,
        if (version != null) 'version': version,
        if (applicationWithCredential != null)
          'applicationWithCredential': applicationWithCredential,
        if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
        if (tags != null) 'tags': tags,
        if (modelId != null) 'modelId': modelId,
      };
}

class AgentInfo {
  const AgentInfo({
    this.id,
    this.name,
    this.modelName,
    this.welcomeMessage,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        id: readString(json['id']),
        name: readString(json['name']),
        modelName: readString(json['modelName']),
        welcomeMessage: readString(json['welcomeMessage']),
      );

  final String? id;
  final String? name;
  final String? modelName;
  final String? welcomeMessage;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (modelName != null) 'modelName': modelName,
        if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
      };
}

/// A version snapshot of an agent.
class AgentHistory extends BaseEntity {
  const AgentHistory({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.agent,
    this.comment,
  });

  factory AgentHistory.fromJson(Map<String, dynamic> json) => AgentHistory(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        agent: readObject(json['agent'], Agent.fromJson),
        comment: readString(json['comment']),
      );

  final Agent? agent;
  final String? comment;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (agent != null) 'agent': agent!.toJson(),
        if (comment != null) 'comment': comment,
      };
}

/// Body of `patchAgent` (tags only).
class AgentPatch {
  const AgentPatch({
    this.tags,
  });

  factory AgentPatch.fromJson(Map<String, dynamic> json) => AgentPatch(
        tags: readStringList(json['tags']),
      );

  final List<String>? tags;

  Map<String, dynamic> toJson() => {
        if (tags != null) 'tags': tags,
      };
}

/// A published (marketplace) agent.
class AgentPublish extends BaseEntity {
  const AgentPublish({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.agent,
    this.sourceOrgId,
    this.agentId,
    this.longDescription,
    this.category,
    this.latestVersion,
  });

  factory AgentPublish.fromJson(Map<String, dynamic> json) => AgentPublish(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        agent: readObject(json['agent'], Agent.fromJson),
        sourceOrgId: readString(json['sourceOrgId']),
        agentId: readString(json['agentId']),
        longDescription: readString(json['longDescription']),
        category: readString(json['category']),
        latestVersion: readInt(json['latestVersion']),
      );

  final Agent? agent;
  final String? sourceOrgId;
  final String? agentId;
  final String? longDescription;
  final String? category;

  /// Server-enriched field populated by `listPublishedAgents`.
  final int? latestVersion;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (agent != null) 'agent': agent!.toJson(),
        if (sourceOrgId != null) 'sourceOrgId': sourceOrgId,
        if (agentId != null) 'agentId': agentId,
        if (longDescription != null) 'longDescription': longDescription,
        if (category != null) 'category': category,
        if (latestVersion != null) 'latestVersion': latestVersion,
      };
}

class PublishAgentRequest {
  const PublishAgentRequest({
    this.longDescription,
    this.category,
  });

  factory PublishAgentRequest.fromJson(Map<String, dynamic> json) => PublishAgentRequest(
        longDescription: readString(json['longDescription']),
        category: readString(json['category']),
      );

  final String? longDescription;
  final String? category;

  Map<String, dynamic> toJson() => {
        if (longDescription != null) 'longDescription': longDescription,
        if (category != null) 'category': category,
      };
}

class UpdatePublishedAgentRequest {
  const UpdatePublishedAgentRequest({
    this.longDescription,
    this.category,
    this.agentId,
  });

  factory UpdatePublishedAgentRequest.fromJson(Map<String, dynamic> json) =>
      UpdatePublishedAgentRequest(
        longDescription: readString(json['longDescription']),
        category: readString(json['category']),
        agentId: readString(json['agentId']),
      );

  final String? longDescription;
  final String? category;
  final String? agentId;

  Map<String, dynamic> toJson() => {
        if (longDescription != null) 'longDescription': longDescription,
        if (category != null) 'category': category,
        if (agentId != null) 'agentId': agentId,
      };
}

/// An LLM model registration.
class LlmModel extends BaseEntity {
  const LlmModel({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.name,
    this.description,
    this.provider,
    this.icon,
    this.disabled,
    this.config,
    this.embedding,
  });

  factory LlmModel.fromJson(Map<String, dynamic> json) => LlmModel(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        name: readString(json['name']),
        description: readString(json['description']),
        provider: readString(json['provider']),
        icon: readString(json['icon']),
        disabled: readBool(json['disabled']),
        config: readMap(json['config']),
        embedding: readBool(json['embedding']),
      );

  final String? name;
  final String? description;
  final String? provider;
  final String? icon;
  final bool? disabled;
  final Map<String, dynamic>? config;
  final bool? embedding;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (provider != null) 'provider': provider,
        if (icon != null) 'icon': icon,
        if (disabled != null) 'disabled': disabled,
        if (config != null) 'config': config,
        if (embedding != null) 'embedding': embedding,
      };
}

class Conversation extends BaseEntity {
  const Conversation({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.chatType,
    this.lastMessage,
    this.count,
    this.welcomeMessage,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        chatType: readString(json['chatType']),
        lastMessage: json['lastMessage'],
        count: readInt(json['count']),
        welcomeMessage: readString(json['welcomeMessage']),
      );

  final String? chatType;

  /// A [MessageContent]. Server-enriched on `listConversationsByAgent`.
  final MessageContent lastMessage;

  final int? count;

  /// Server-enriched on `createConversation` when this is the first conversation.
  final String? welcomeMessage;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (chatType != null) 'chatType': chatType,
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (count != null) 'count': count,
        if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
      };
}

class ConversationMessage extends BaseEntity {
  const ConversationMessage({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.conversationId,
    this.role,
    this.content,
    this.memberId,
    this.chatType,
    this.metadata,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) => ConversationMessage(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        conversationId: readString(json['conversationId']),
        role: readString(json['role']),
        content: json['content'],
        memberId: readString(json['memberId']),
        chatType: readString(json['chatType']),
        metadata: readMap(json['metadata']),
      );

  final String? conversationId;
  final String? role;

  /// A [MessageContent]: a `String` or a list of block maps.
  final MessageContent content;

  final String? memberId;
  final String? chatType;
  final Map<String, dynamic>? metadata;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (conversationId != null) 'conversationId': conversationId,
        if (role != null) 'role': role,
        if (content != null) 'content': content,
        if (memberId != null) 'memberId': memberId,
        if (chatType != null) 'chatType': chatType,
        if (metadata != null) 'metadata': metadata,
      };
}

class KnowledgeBase extends BaseEntity {
  const KnowledgeBase({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.name,
    this.description,
    this.connectionId,
    this.modelId,
  });

  factory KnowledgeBase.fromJson(Map<String, dynamic> json) => KnowledgeBase(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        name: readString(json['name']),
        description: readString(json['description']),
        connectionId: readString(json['connectionId']),
        modelId: readString(json['modelId']),
      );

  final String? name;
  final String? description;
  final String? connectionId;
  final String? modelId;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (connectionId != null) 'connectionId': connectionId,
        if (modelId != null) 'modelId': modelId,
      };
}

class Dataset extends BaseEntity {
  const Dataset({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.name,
    this.knowledgeBaseId,
    this.content,
  });

  factory Dataset.fromJson(Map<String, dynamic> json) => Dataset(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        name: readString(json['name']),
        knowledgeBaseId: readString(json['knowledgeBaseId']),
        content: readString(json['content']),
      );

  final String? name;
  final String? knowledgeBaseId;
  final String? content;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (name != null) 'name': name,
        if (knowledgeBaseId != null) 'knowledgeBaseId': knowledgeBaseId,
        if (content != null) 'content': content,
      };
}

/// Body of `storeEmbeddings` (`POST <kb>/embeddings`).
class EmbeddingDbRequest {
  const EmbeddingDbRequest({
    this.modelId,
    this.credentialId,
    this.texts,
    this.payload,
    this.collection,
    this.distance,
  });

  factory EmbeddingDbRequest.fromJson(Map<String, dynamic> json) => EmbeddingDbRequest(
        modelId: readString(json['modelId']),
        credentialId: readString(json['credentialId']),
        texts: readString(json['texts']),
        payload: readMap(json['payload']),
        collection: readString(json['collection']),
        distance: readString(json['distance']),
      );

  final String? modelId;
  final String? credentialId;
  final String? texts;
  final Map<String, dynamic>? payload;
  final String? collection;

  /// Qdrant distance-metric name, e.g. `Cosine`, `Dot` or `Euclid`.
  final String? distance;

  Map<String, dynamic> toJson() => {
        if (modelId != null) 'modelId': modelId,
        if (credentialId != null) 'credentialId': credentialId,
        if (texts != null) 'texts': texts,
        if (payload != null) 'payload': payload,
        if (collection != null) 'collection': collection,
        if (distance != null) 'distance': distance,
      };
}
