// Wire models for the integrations-manager API (`/v1/integrations/*`). Field
// names match the JSON the service sends and accepts; `toJson` omits null
// fields so partial payloads only send what you set. Non-optional TS fields
// are `required` here. The TS string unions (`ApplicationType`,
// `ApplicationSubType`, `ConnectionType`, `ConnectionStatus`) are plain
// `String`s; the known values are listed on each field.

import 'json.dart';

/// A JSON object (`JsonObject` in the TS SDK).
typedef JsonObject = Map<String, dynamic>;

/// Free-form HTTP action metadata (`HttpInput` in the TS SDK).
typedef HttpInput = Map<String, dynamic>;

/// Application type -> its sub types (`SubApplicationConfig` in the TS SDK),
/// e.g. `{'database': ['postgres', 'mysql'], 'http': ['http', 'oauth2']}`.
typedef SubApplicationConfig = Map<String, List<String>>;

/// The `{ success, code, message, data, error }` envelope every integrations endpoint
/// answers with. The client unwraps `data` for you; this type is only for callers
/// that use `IntegrationsHttpClient` with their own decoding.
class ApiEnvelope {
  const ApiEnvelope({
    this.success,
    this.code,
    this.message,
    this.data,
    this.error,
  });

  factory ApiEnvelope.fromJson(Map<String, dynamic> json) => ApiEnvelope(
        success: readBool(json['success']),
        code: readString(json['code']),
        message: readString(json['message']),
        data: json['data'],
        error: json['error'],
      );

  final bool? success;
  final String? code;
  final String? message;
  final Object? data;
  final Object? error;

  Map<String, dynamic> toJson() => {
        if (success != null) 'success': success,
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
      };
}

/// Metadata fields shared by every integrations entity.
abstract class BaseEntity {
  const BaseEntity({
    this.id,
    this.orgId,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? orgId;
  final String? createdBy;
  final String? updatedBy;

  /// ISO-8601 timestamp.
  final String? createdAt;

  /// ISO-8601 timestamp.
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (orgId != null) 'orgId': orgId,
        if (createdBy != null) 'createdBy': createdBy,
        if (updatedBy != null) 'updatedBy': updatedBy,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}

/// An integration application (HTTP API, database, queue, ...).
class Application extends BaseEntity {
  const Application({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    this.icon,
    required this.type,
    required this.subType,
    this.operationConfig,
    this.authConfig,
    this.supportProtocol,
    this.tags,
    this.version,
    this.mcpKey,
    this.publishedUrl,
  });

  factory Application.fromJson(Map<String, dynamic> json) => Application(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        icon: readString(json['icon']),
        type: readString(json['type']) ?? '',
        subType: readString(json['subType']) ?? '',
        operationConfig: readMap(json['operationConfig']),
        authConfig: readMap(json['authConfig']),
        supportProtocol: json['supportProtocol'],
        tags: readStringList(json['tags']),
        version: readInt(json['version']),
        mcpKey: readString(json['mcpKey']),
        publishedUrl: readString(json['publishedUrl']),
      );

  final String name;
  final String? description;
  final String? icon;

  /// `ApplicationType`: `http`, `database`, `queue`, `storage` or any other string.
  final String type;

  /// `ApplicationSubType`: `http`, `oauth2`, `postgres`, `mysql`, `clickhouse`, `nats`, `mongodb`,
  /// `redis`, `rabbitmq`, `kafka`, `sqs`, `qdrant`, `zep`, `opensearch` or any other string.
  final String subType;

  final Map<String, dynamic>? operationConfig;
  final Map<String, dynamic>? authConfig;
  final Object? supportProtocol;
  final List<String>? tags;
  final int? version;
  final String? mcpKey;
  final String? publishedUrl;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        'type': type,
        'subType': subType,
        if (operationConfig != null) 'operationConfig': operationConfig,
        if (authConfig != null) 'authConfig': authConfig,
        if (supportProtocol != null) 'supportProtocol': supportProtocol,
        if (tags != null) 'tags': tags,
        if (version != null) 'version': version,
        if (mcpKey != null) 'mcpKey': mcpKey,
        if (publishedUrl != null) 'publishedUrl': publishedUrl,
      };
}

/// List item of `applications.list`.
class ApplicationWithCount extends Application {
  const ApplicationWithCount({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required super.name,
    super.description,
    super.icon,
    required super.type,
    required super.subType,
    super.operationConfig,
    super.authConfig,
    super.supportProtocol,
    super.tags,
    super.version,
    super.mcpKey,
    super.publishedUrl,
    required this.count,
  });

  factory ApplicationWithCount.fromJson(Map<String, dynamic> json) => ApplicationWithCount(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        icon: readString(json['icon']),
        type: readString(json['type']) ?? '',
        subType: readString(json['subType']) ?? '',
        operationConfig: readMap(json['operationConfig']),
        authConfig: readMap(json['authConfig']),
        supportProtocol: json['supportProtocol'],
        tags: readStringList(json['tags']),
        version: readInt(json['version']),
        mcpKey: readString(json['mcpKey']),
        publishedUrl: readString(json['publishedUrl']),
        count: readInt(json['count']) ?? 0,
      );

  final int count;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'count': count,
      };
}

/// Result item of `actions.resolveCredentials`.
class ApplicationWithConnection extends Application {
  const ApplicationWithConnection({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required super.name,
    super.description,
    super.icon,
    required super.type,
    required super.subType,
    super.operationConfig,
    super.authConfig,
    super.supportProtocol,
    super.tags,
    super.version,
    super.mcpKey,
    super.publishedUrl,
    required this.connections,
    this.actionId,
  });

  factory ApplicationWithConnection.fromJson(Map<String, dynamic> json) =>
      ApplicationWithConnection(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        icon: readString(json['icon']),
        type: readString(json['type']) ?? '',
        subType: readString(json['subType']) ?? '',
        operationConfig: readMap(json['operationConfig']),
        authConfig: readMap(json['authConfig']),
        supportProtocol: json['supportProtocol'],
        tags: readStringList(json['tags']),
        version: readInt(json['version']),
        mcpKey: readString(json['mcpKey']),
        publishedUrl: readString(json['publishedUrl']),
        connections:
            readObjectList(json['connections'], Connection.fromJson) ?? const <Connection>[],
        actionId: readString(json['actionId']),
      );

  final List<Connection> connections;
  final String? actionId;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'connections': connections.map((e) => e.toJson()).toList(),
        if (actionId != null) 'actionId': actionId,
      };
}

/// A version snapshot of an application.
class ApplicationHistory extends BaseEntity {
  const ApplicationHistory({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.application,
    this.comment,
  });

  factory ApplicationHistory.fromJson(Map<String, dynamic> json) => ApplicationHistory(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        application: readObject(json['application'], Application.fromJson) ??
            Application.fromJson(const <String, dynamic>{}),
        comment: readString(json['comment']),
      );

  final Application application;
  final String? comment;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'application': application.toJson(),
        if (comment != null) 'comment': comment,
      };
}

class PatchTagsRequest {
  const PatchTagsRequest({
    required this.tags,
  });

  factory PatchTagsRequest.fromJson(Map<String, dynamic> json) => PatchTagsRequest(
        tags: readStringList(json['tags']) ?? const <String>[],
      );

  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'tags': tags,
      };
}

class RunApplicationRequest {
  const RunApplicationRequest({
    this.credentialId,
    required this.inputBody,
  });

  factory RunApplicationRequest.fromJson(Map<String, dynamic> json) => RunApplicationRequest(
        credentialId: readString(json['credentialId']),
        inputBody: readMap(json['inputBody']) ?? const <String, dynamic>{},
      );

  final String? credentialId;
  final Map<String, dynamic> inputBody;

  Map<String, dynamic> toJson() => {
        if (credentialId != null) 'credentialId': credentialId,
        'inputBody': inputBody,
      };
}

class HttpActionType {
  const HttpActionType({
    required this.type,
    this.metadata,
  });

  factory HttpActionType.fromJson(Map<String, dynamic> json) => HttpActionType(
        type: readString(json['type']) ?? '',
        metadata: readMap(json['metadata']),
      );

  final String type;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (metadata != null) 'metadata': metadata,
      };
}

/// An operation of an application.
class ApplicationAction extends BaseEntity {
  const ApplicationAction({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.applicationId,
    required this.name,
    this.groupName,
    this.description,
    required this.action,
    this.properties,
  });

  factory ApplicationAction.fromJson(Map<String, dynamic> json) => ApplicationAction(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        applicationId: readString(json['applicationId']) ?? '',
        name: readString(json['name']) ?? '',
        groupName: readString(json['groupName']),
        description: readString(json['description']),
        action: readObject(json['action'], HttpActionType.fromJson) ??
            HttpActionType.fromJson(const <String, dynamic>{}),
        properties: json['properties'],
      );

  final String applicationId;
  final String name;
  final String? groupName;
  final String? description;
  final HttpActionType action;
  final Object? properties;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'applicationId': applicationId,
        'name': name,
        if (groupName != null) 'groupName': groupName,
        if (description != null) 'description': description,
        'action': action.toJson(),
        if (properties != null) 'properties': properties,
      };
}

class RunActionRequest {
  const RunActionRequest({
    this.credentialId,
    required this.inputBody,
  });

  factory RunActionRequest.fromJson(Map<String, dynamic> json) => RunActionRequest(
        credentialId: readString(json['credentialId']),
        inputBody: readMap(json['inputBody']) ?? const <String, dynamic>{},
      );

  final String? credentialId;
  final Map<String, dynamic> inputBody;

  Map<String, dynamic> toJson() => {
        if (credentialId != null) 'credentialId': credentialId,
        'inputBody': inputBody,
      };
}

/// A Postman collection folder (or request item), as accepted by
/// `applications.loadActions`.
///
/// Mirrors the TS `PostmanFolder`, which has an index signature: every key
/// besides `name`, `item` and `request` (`description`, `event`, `auth`,
/// `variable`, ...) is kept in [extra] and written back by [toJson], so a
/// collection round-trips losslessly.
class PostmanFolder {
  const PostmanFolder({
    this.name,
    this.item,
    this.request,
    this.extra = const <String, dynamic>{},
  });

  factory PostmanFolder.fromJson(Map<String, dynamic> json) => PostmanFolder(
        name: readString(json['name']),
        item: readObjectList(json['item'], PostmanFolder.fromJson),
        request: readMap(json['request']),
        extra: {
          for (final e in json.entries)
            if (!knownKeys.contains(e.key)) e.key: e.value,
        },
      );

  /// Keys mapped to typed fields; everything else lands in [extra].
  static const Set<String> knownKeys = {'name', 'item', 'request'};

  final String? name;

  /// Nested folders / request items.
  final List<PostmanFolder>? item;

  final Map<String, dynamic>? request;

  /// Any other keys, kept verbatim (including `null` values).
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (item != null) 'item': item!.map((e) => e.toJson()).toList(),
        if (request != null) 'request': request,
        for (final e in extra.entries)
          if (!knownKeys.contains(e.key)) e.key: e.value,
      };
}

/// Stored credentials for an application.
class Connection extends BaseEntity {
  const Connection({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    required this.connectionType,
    this.applicationType,
    this.applicationSubType,
    this.connectionStatus,
    required this.applicationId,
    this.properties,
    this.isDefault,
  });

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        connectionType: readString(json['connectionType']) ?? '',
        applicationType: readString(json['applicationType']),
        applicationSubType: readString(json['applicationSubType']),
        connectionStatus: readString(json['connectionStatus']),
        applicationId: readString(json['applicationId']) ?? '',
        properties: readMap(json['properties']),
        isDefault: readBool(json['isDefault']),
      );

  final String name;
  final String? description;

  /// `ConnectionType`: `oauth2` or any other string.
  final String connectionType;

  /// `ApplicationType`: `http`, `database`, `queue`, `storage` or any other string.
  final String? applicationType;

  /// `ApplicationSubType`: `http`, `oauth2`, `postgres`, `mysql`, `clickhouse`, `nats`, `mongodb`,
  /// `redis`, `rabbitmq`, `kafka`, `sqs`, `qdrant`, `zep`, `opensearch` or any other string.
  final String? applicationSubType;

  /// `ConnectionStatus`: `active`, `inactive`, `revoked`, `expired`, `pending` or any other
  /// string.
  final String? connectionStatus;

  final String applicationId;
  final Map<String, dynamic>? properties;
  final bool? isDefault;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        'connectionType': connectionType,
        if (applicationType != null) 'applicationType': applicationType,
        if (applicationSubType != null) 'applicationSubType': applicationSubType,
        if (connectionStatus != null) 'connectionStatus': connectionStatus,
        'applicationId': applicationId,
        if (properties != null) 'properties': properties,
        if (isDefault != null) 'isDefault': isDefault,
      };
}

/// Result of `connections.getById`.
class ConnectionResponse extends Connection {
  const ConnectionResponse({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required super.name,
    super.description,
    required super.connectionType,
    super.applicationType,
    super.applicationSubType,
    super.connectionStatus,
    required super.applicationId,
    super.properties,
    super.isDefault,
  });

  factory ConnectionResponse.fromJson(Map<String, dynamic> json) => ConnectionResponse(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        connectionType: readString(json['connectionType']) ?? '',
        applicationType: readString(json['applicationType']),
        applicationSubType: readString(json['applicationSubType']),
        connectionStatus: readString(json['connectionStatus']),
        applicationId: readString(json['applicationId']) ?? '',
        properties: readMap(json['properties']),
        isDefault: readBool(json['isDefault']),
      );

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
      };
}

class SetAsDefaultRequest {
  const SetAsDefaultRequest({
    required this.applicationId,
  });

  factory SetAsDefaultRequest.fromJson(Map<String, dynamic> json) => SetAsDefaultRequest(
        applicationId: readString(json['applicationId']) ?? '',
      );

  final String applicationId;

  Map<String, dynamic> toJson() => {
        'applicationId': applicationId,
      };
}

/// A trigger (e.g. a CDC subscription) of an application.
class ApplicationTrigger extends BaseEntity {
  const ApplicationTrigger({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    this.operationConfig,
    required this.applicationId,
    this.webhookUrl,
  });

  factory ApplicationTrigger.fromJson(Map<String, dynamic> json) => ApplicationTrigger(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        operationConfig: readMap(json['operationConfig']),
        applicationId: readString(json['applicationId']) ?? '',
        webhookUrl: readString(json['webhookUrl']),
      );

  final String name;
  final String? description;
  final Map<String, dynamic>? operationConfig;
  final String applicationId;
  final String? webhookUrl;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        if (operationConfig != null) 'operationConfig': operationConfig,
        'applicationId': applicationId,
        if (webhookUrl != null) 'webhookUrl': webhookUrl,
      };
}

/// Runtime state of a polling trigger.
class TriggerState {
  const TriggerState({
    required this.triggerId,
    this.orgId,
    this.cursor,
    this.lastRunAt,
    this.lastError,
    required this.runCount,
    this.leasedBy,
    this.leasedUntil,
    this.updatedAt,
  });

  factory TriggerState.fromJson(Map<String, dynamic> json) => TriggerState(
        triggerId: readString(json['triggerId']) ?? '',
        orgId: readString(json['orgId']),
        cursor: readMap(json['cursor']),
        lastRunAt: readString(json['lastRunAt']),
        lastError: readString(json['lastError']),
        runCount: readInt(json['runCount']) ?? 0,
        leasedBy: readString(json['leasedBy']),
        leasedUntil: readString(json['leasedUntil']),
        updatedAt: readString(json['updatedAt']),
      );

  final String triggerId;
  final String? orgId;
  final Map<String, dynamic>? cursor;

  /// ISO-8601 timestamp.
  final String? lastRunAt;

  final String? lastError;
  final int runCount;
  final String? leasedBy;

  /// ISO-8601 timestamp.
  final String? leasedUntil;

  /// ISO-8601 timestamp.
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'triggerId': triggerId,
        if (orgId != null) 'orgId': orgId,
        if (cursor != null) 'cursor': cursor,
        if (lastRunAt != null) 'lastRunAt': lastRunAt,
        if (lastError != null) 'lastError': lastError,
        'runCount': runCount,
        if (leasedBy != null) 'leasedBy': leasedBy,
        if (leasedUntil != null) 'leasedUntil': leasedUntil,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}

/// Body of `oauth.login`.
class ConnectionCreateRequest {
  const ConnectionCreateRequest({
    required this.applicationId,
    this.name,
    this.description,
  });

  factory ConnectionCreateRequest.fromJson(Map<String, dynamic> json) => ConnectionCreateRequest(
        applicationId: readString(json['applicationId']) ?? '',
        name: readString(json['name']),
        description: readString(json['description']),
      );

  final String applicationId;
  final String? name;
  final String? description;

  Map<String, dynamic> toJson() => {
        'applicationId': applicationId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      };
}

/// Body of `oauth.callback`.
class CallbackRequest {
  const CallbackRequest({
    required this.state,
    required this.code,
  });

  factory CallbackRequest.fromJson(Map<String, dynamic> json) => CallbackRequest(
        state: readString(json['state']) ?? '',
        code: readString(json['code']) ?? '',
      );

  final String state;
  final String code;

  Map<String, dynamic> toJson() => {
        'state': state,
        'code': code,
      };
}

class OAuthLoginUrl {
  const OAuthLoginUrl({
    required this.url,
  });

  factory OAuthLoginUrl.fromJson(Map<String, dynamic> json) => OAuthLoginUrl(
        url: readString(json['url']) ?? '',
      );

  final String url;

  Map<String, dynamic> toJson() => {
        'url': url,
      };
}

class OAuthCallbackResult {
  const OAuthCallbackResult({
    required this.success,
  });

  factory OAuthCallbackResult.fromJson(Map<String, dynamic> json) => OAuthCallbackResult(
        success: readString(json['success']) ?? '',
      );

  final String success;

  Map<String, dynamic> toJson() => {
        'success': success,
      };
}

/// An OAuth token stored for a connection.
class AuthToken extends BaseEntity {
  const AuthToken({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    this.requestId,
    required this.applicationId,
    required this.credentialId,
    required this.token,
    this.refreshToken,
    this.expiresIn,
    this.expiry,
    this.tokenType,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        requestId: readString(json['requestId']),
        applicationId: readString(json['applicationId']) ?? '',
        credentialId: readString(json['credentialId']) ?? '',
        token: readString(json['token']) ?? '',
        refreshToken: readString(json['refreshToken']),
        expiresIn: readInt(json['expiresIn']),
        expiry: readString(json['expiry']),
        tokenType: readString(json['tokenType']),
      );

  final String? requestId;
  final String applicationId;
  final String credentialId;
  final String token;
  final String? refreshToken;
  final int? expiresIn;

  /// ISO-8601 timestamp.
  final String? expiry;

  final String? tokenType;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (requestId != null) 'requestId': requestId,
        'applicationId': applicationId,
        'credentialId': credentialId,
        'token': token,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (expiresIn != null) 'expiresIn': expiresIn,
        if (expiry != null) 'expiry': expiry,
        if (tokenType != null) 'tokenType': tokenType,
      };
}

class RefreshExpiringTokensResult {
  const RefreshExpiringTokensResult({
    required this.checked,
    required this.refreshed,
    required this.skipped,
    required this.failed,
    required this.refreshedTokens,
    required this.failures,
  });

  factory RefreshExpiringTokensResult.fromJson(Map<String, dynamic> json) =>
      RefreshExpiringTokensResult(
        checked: readInt(json['checked']) ?? 0,
        refreshed: readInt(json['refreshed']) ?? 0,
        skipped: readInt(json['skipped']) ?? 0,
        failed: readInt(json['failed']) ?? 0,
        refreshedTokens:
            readObjectList(json['refreshedTokens'], AuthToken.fromJson) ?? const <AuthToken>[],
        failures: readMapList(json['failures']) ?? const <Map<String, dynamic>>[],
      );

  final int checked;
  final int refreshed;
  final int skipped;
  final int failed;
  final List<AuthToken> refreshedTokens;
  final List<Map<String, dynamic>> failures;

  Map<String, dynamic> toJson() => {
        'checked': checked,
        'refreshed': refreshed,
        'skipped': skipped,
        'failed': failed,
        'refreshedTokens': refreshedTokens.map((e) => e.toJson()).toList(),
        'failures': failures,
      };
}

/// A JSON-RPC 2.0 request sent to a published MCP application.
class JsonRpcRequest {
  const JsonRpcRequest({
    required this.jsonrpc,
    this.id,
    required this.method,
    this.params,
  });

  factory JsonRpcRequest.fromJson(Map<String, dynamic> json) => JsonRpcRequest(
        jsonrpc: readString(json['jsonrpc']) ?? '',
        id: json['id'],
        method: readString(json['method']) ?? '',
        params: json['params'],
      );

  final String jsonrpc;

  /// A `String`, a number or `null`.
  final Object? id;

  final String method;
  final Object? params;

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        if (id != null) 'id': id,
        'method': method,
        if (params != null) 'params': params,
      };
}

class JsonRpcError {
  const JsonRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  factory JsonRpcError.fromJson(Map<String, dynamic> json) => JsonRpcError(
        code: readInt(json['code']) ?? 0,
        message: readString(json['message']) ?? '',
        data: json['data'],
      );

  final int code;
  final String message;
  final Object? data;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };
}

class JsonRpcResponse {
  const JsonRpcResponse({
    required this.jsonrpc,
    this.id,
    this.result,
    this.error,
  });

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) => JsonRpcResponse(
        jsonrpc: readString(json['jsonrpc']) ?? '',
        id: json['id'],
        result: json['result'],
        error: readObject(json['error'], JsonRpcError.fromJson),
      );

  final String jsonrpc;

  /// A `String`, a number or `null`.
  final Object? id;

  final Object? result;
  final JsonRpcError? error;

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        if (id != null) 'id': id,
        if (result != null) 'result': result,
        if (error != null) 'error': error!.toJson(),
      };
}

class McpToolsResponse {
  const McpToolsResponse({
    required this.tools,
  });

  factory McpToolsResponse.fromJson(Map<String, dynamic> json) => McpToolsResponse(
        tools: readMapList(json['tools']) ?? const <Map<String, dynamic>>[],
      );

  final List<Map<String, dynamic>> tools;

  Map<String, dynamic> toJson() => {
        'tools': tools,
      };
}
