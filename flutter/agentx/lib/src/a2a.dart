// Executor wire types: the A2A message model and its JSON-RPC 2.0 envelope.
//
// The plain classes at the bottom were generated with scratchpad/dartgen.py
// (specs/agentx_a2a.py); the sealed unions ([Part], [FilePayload]),
// [A2AMessage] and the JSON-RPC request/response are hand-written.

import 'json.dart';

// ---------------------------------------------------------------------------
// Parts
// ---------------------------------------------------------------------------

/// One piece of an [A2AMessage], discriminated by [kind]:
/// [TextPart] (`text`), [FilePart] (`file`) or [DataPart] (`data`).
///
/// [Part.fromJson] never throws: a part with an unrecognised `kind`, or a
/// known kind whose required payload is missing or malformed, decodes as an
/// [UnknownPart] that keeps the raw map (and re-emits it from [toJson]).
sealed class Part {
  const Part();

  factory Part.fromJson(Map<String, dynamic> json) {
    final metadata = readMap(json['metadata']);
    return switch (json) {
      {'kind': 'text', 'text': final String text} => TextPart(text: text, metadata: metadata),
      {'kind': 'file', 'file': final Map file} =>
        FilePart(file: FilePayload.fromJson(readMap(file)!), metadata: metadata),
      {'kind': 'data', 'data': final Map data} =>
        DataPart(data: readMap(data)!, metadata: metadata),
      _ => UnknownPart(json),
    };
  }

  /// `text`, `file`, `data` — or whatever an [UnknownPart] carried.
  String get kind;

  Map<String, dynamic>? get metadata;

  Map<String, dynamic> toJson();
}

/// A plain-text part (`kind: "text"`).
class TextPart extends Part {
  const TextPart({required this.text, this.metadata});

  final String text;

  @override
  final Map<String, dynamic>? metadata;

  @override
  String get kind => 'text';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'text': text,
        if (metadata != null) 'metadata': metadata,
      };
}

/// A file part (`kind: "file"`), carrying inline bytes or a URI.
class FilePart extends Part {
  const FilePart({required this.file, this.metadata});

  final FilePayload file;

  @override
  final Map<String, dynamic>? metadata;

  @override
  String get kind => 'file';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'file': file.toJson(),
        if (metadata != null) 'metadata': metadata,
      };
}

/// A structured-data part (`kind: "data"`).
class DataPart extends Part {
  const DataPart({required this.data, this.metadata});

  final Map<String, dynamic> data;

  @override
  final Map<String, dynamic>? metadata;

  @override
  String get kind => 'data';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'data': data,
        if (metadata != null) 'metadata': metadata,
      };
}

/// A part this SDK does not understand (new `kind`, or a malformed known one).
/// [raw] is the part exactly as received and is what [toJson] returns.
class UnknownPart extends Part {
  const UnknownPart(this.raw);

  final Map<String, dynamic> raw;

  @override
  String get kind => readString(raw['kind']) ?? '';

  @override
  Map<String, dynamic>? get metadata => readMap(raw['metadata']);

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.of(raw);
}

// ---------------------------------------------------------------------------
// File payloads
// ---------------------------------------------------------------------------

/// The `file` of a [FilePart]: [FileWithBytes] (base64 `bytes`) or
/// [FileWithURI] (`uri`).
///
/// [FilePayload.fromJson] picks [FileWithBytes] when `bytes` is present and
/// [FileWithURI] otherwise (with an empty `uri` if that is missing too).
sealed class FilePayload {
  const FilePayload({this.name, this.mimeType});

  factory FilePayload.fromJson(Map<String, dynamic> json) {
    final name = readString(json['name']);
    final mimeType = readString(json['mimeType']);
    final bytes = json['bytes'];
    if (bytes != null) {
      return FileWithBytes(bytes: readString(bytes)!, name: name, mimeType: mimeType);
    }
    return FileWithURI(uri: readString(json['uri']) ?? '', name: name, mimeType: mimeType);
  }

  final String? name;
  final String? mimeType;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// File content inlined as a base64 string.
class FileWithBytes extends FilePayload {
  const FileWithBytes({required this.bytes, super.name, super.mimeType});

  /// Base64-encoded file content.
  final String bytes;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'bytes': bytes};
}

/// File content referenced by URI.
class FileWithURI extends FilePayload {
  const FileWithURI({required this.uri, super.name, super.mimeType});

  final String uri;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'uri': uri};
}

// ---------------------------------------------------------------------------
// Message
// ---------------------------------------------------------------------------

/// A single A2A communication turn (executor input and output).
///
/// Named `A2AMessage` to avoid colliding with the manager's
/// `ConversationMessage`.
class A2AMessage {
  const A2AMessage({
    required this.role,
    required this.parts,
    required this.messageId,
    this.kind = 'message',
    this.metadata,
    this.extensions,
    this.referenceTaskIds,
    this.taskId,
    this.contextId,
  });

  factory A2AMessage.fromJson(Map<String, dynamic> json) => A2AMessage(
        role: readString(json['role']) ?? '',
        parts: readObjectList(json['parts'], Part.fromJson) ?? const <Part>[],
        messageId: readString(json['messageId']) ?? '',
        kind: readString(json['kind']) ?? 'message',
        metadata: readMap(json['metadata']),
        extensions: readStringList(json['extensions']),
        referenceTaskIds: readStringList(json['referenceTaskIds']),
        taskId: readString(json['taskId']),
        contextId: readString(json['contextId']),
      );

  /// `user` or `assistant`.
  final String role;

  final List<Part> parts;
  final String messageId;

  /// Always `message` for a well-formed message.
  final String kind;

  final Map<String, dynamic>? metadata;
  final List<String>? extensions;
  final List<String>? referenceTaskIds;
  final String? taskId;
  final String? contextId;

  Map<String, dynamic> toJson() => {
        'role': role,
        'parts': parts.map((e) => e.toJson()).toList(),
        'messageId': messageId,
        'kind': kind,
        if (metadata != null) 'metadata': metadata,
        if (extensions != null) 'extensions': extensions,
        if (referenceTaskIds != null) 'referenceTaskIds': referenceTaskIds,
        if (taskId != null) 'taskId': taskId,
        if (contextId != null) 'contextId': contextId,
      };
}

// ---------------------------------------------------------------------------
// JSON-RPC 2.0
// ---------------------------------------------------------------------------

/// A JSON-RPC 2.0 request. The executor reuses [id] as the target agent id.
class JSONRPCRequest {
  const JSONRPCRequest({required this.method, this.jsonrpc = '2.0', this.params, this.id});

  factory JSONRPCRequest.fromJson(Map<String, dynamic> json) => JSONRPCRequest(
        jsonrpc: readString(json['jsonrpc']) ?? '2.0',
        method: readString(json['method']) ?? '',
        params: json['params'],
        id: json['id'],
      );

  final String jsonrpc;
  final String method;

  /// Any JSON value or model object (e.g. [MessageSendParams]).
  final Object? params;

  /// A `String`, a `num` or `null`.
  final Object? id;

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'method': method,
        if (params != null) 'params': params,
        if (id != null) 'id': id,
      };
}

/// A JSON-RPC 2.0 response. Exactly one of [result] / [error] is normally set.
class JSONRPCResponse {
  const JSONRPCResponse({this.jsonrpc = '2.0', this.result, this.error, this.id});

  factory JSONRPCResponse.fromJson(Map<String, dynamic> json) => JSONRPCResponse(
        jsonrpc: readString(json['jsonrpc']) ?? '2.0',
        result: json['result'],
        error: readObject(json['error'], JSONRPCError.fromJson),
        id: json['id'],
      );

  final String jsonrpc;

  /// The raw JSON result (for `message/send`, typically an [A2AMessage] map:
  /// decode it with `A2AMessage.fromJson`).
  final Object? result;

  final JSONRPCError? error;

  /// A `String`, a `num` or `null`.
  final Object? id;

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        if (result != null) 'result': result,
        if (error != null) 'error': error!.toJson(),
        if (id != null) 'id': id,
      };
}

/// Standard JSON-RPC error codes.
abstract final class JSONRPCErrorCodes {
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
}

/// A2A-specific error codes (-32000 to -32099).
abstract final class A2AErrorCodes {
  static const int taskNotFound = -32001;
  static const int taskNotCancelable = -32002;
  static const int pushNotificationNotSupported = -32003;
  static const int unsupportedOperation = -32004;
  static const int contentTypeNotSupported = -32005;
  static const int invalidAgentResponse = -32006;
}

// ---------------------------------------------------------------------------
// Send parameters (generated)
// ---------------------------------------------------------------------------

class PushNotificationAuthenticationInfo {
  const PushNotificationAuthenticationInfo({
    required this.schemes,
    this.credentials,
  });

  factory PushNotificationAuthenticationInfo.fromJson(Map<String, dynamic> json) =>
      PushNotificationAuthenticationInfo(
        schemes: readStringList(json['schemes']) ?? const <String>[],
        credentials: readString(json['credentials']),
      );

  final List<String> schemes;
  final String? credentials;

  Map<String, dynamic> toJson() => {
        'schemes': schemes,
        if (credentials != null) 'credentials': credentials,
      };
}

class PushNotificationConfig {
  const PushNotificationConfig({
    this.id,
    required this.url,
    this.token,
    this.authentication,
  });

  factory PushNotificationConfig.fromJson(Map<String, dynamic> json) => PushNotificationConfig(
        id: readString(json['id']),
        url: readString(json['url']) ?? '',
        token: readString(json['token']),
        authentication:
            readObject(json['authentication'], PushNotificationAuthenticationInfo.fromJson),
      );

  final String? id;
  final String url;
  final String? token;
  final PushNotificationAuthenticationInfo? authentication;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'url': url,
        if (token != null) 'token': token,
        if (authentication != null) 'authentication': authentication!.toJson(),
      };
}

class MessageSendConfiguration {
  const MessageSendConfiguration({
    this.acceptedOutputModes,
    this.historyLength,
    this.pushNotificationConfig,
    this.blocking,
  });

  factory MessageSendConfiguration.fromJson(Map<String, dynamic> json) => MessageSendConfiguration(
        acceptedOutputModes: readStringList(json['acceptedOutputModes']),
        historyLength: readInt(json['historyLength']),
        pushNotificationConfig:
            readObject(json['pushNotificationConfig'], PushNotificationConfig.fromJson),
        blocking: readBool(json['blocking']),
      );

  final List<String>? acceptedOutputModes;
  final int? historyLength;
  final PushNotificationConfig? pushNotificationConfig;
  final bool? blocking;

  Map<String, dynamic> toJson() => {
        if (acceptedOutputModes != null) 'acceptedOutputModes': acceptedOutputModes,
        if (historyLength != null) 'historyLength': historyLength,
        if (pushNotificationConfig != null)
          'pushNotificationConfig': pushNotificationConfig!.toJson(),
        if (blocking != null) 'blocking': blocking,
      };
}

/// Params of a `message/send` JSON-RPC call.
class MessageSendParams {
  const MessageSendParams({
    required this.message,
    this.configuration,
    this.metadata,
    this.chatType,
  });

  factory MessageSendParams.fromJson(Map<String, dynamic> json) => MessageSendParams(
        message: readObject(json['message'], A2AMessage.fromJson) ??
            A2AMessage.fromJson(const <String, dynamic>{}),
        configuration: readObject(json['configuration'], MessageSendConfiguration.fromJson),
        metadata: readMap(json['metadata']),
        chatType: readString(json['chatType']),
      );

  final A2AMessage message;
  final MessageSendConfiguration? configuration;
  final Map<String, dynamic>? metadata;
  final String? chatType;

  Map<String, dynamic> toJson() => {
        'message': message.toJson(),
        if (configuration != null) 'configuration': configuration!.toJson(),
        if (metadata != null) 'metadata': metadata,
        if (chatType != null) 'chatType': chatType,
      };
}

/// A JSON-RPC error object. See [JSONRPCErrorCodes] and [A2AErrorCodes].
class JSONRPCError {
  const JSONRPCError({
    required this.code,
    required this.message,
    this.data,
  });

  factory JSONRPCError.fromJson(Map<String, dynamic> json) => JSONRPCError(
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
