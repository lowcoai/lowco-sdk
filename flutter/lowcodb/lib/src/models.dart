// Wire models for the lowcodb manager API. Field names match the JSON the
// manager sends and accepts; `toJson` omits null fields so partial updates
// only send what you set.

import 'json.dart';

/// A user-table row. System fields (`id`, `createdAt`, ...) are always present
/// alongside whatever columns the table defines.
typedef LowcodbRecord = Map<String, dynamic>;

/// Loosely typed dashboard payload.
typedef DashboardResponse = Map<String, dynamic>;

/// Metadata fields shared by every lowcodb entity.
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

/// A database ("base").
class Base extends BaseEntity {
  const Base({
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
    this.baseType,
    this.schema,
  });

  factory Base.fromJson(Map<String, dynamic> json) => Base(
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
        baseType: readString(json['baseType']),
        schema: readString(json['schema']),
      );

  final String? name;
  final String? description;
  final String? connectionId;

  /// `internal` or `external`.
  final String? baseType;

  final String? schema;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (connectionId != null) 'connectionId': connectionId,
        if (baseType != null) 'baseType': baseType,
        if (schema != null) 'schema': schema,
      };
}

class Table extends BaseEntity {
  const Table({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.name,
    this.description,
    this.tableKey,
    this.metadata,
  });

  factory Table.fromJson(Map<String, dynamic> json) => Table(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        name: readString(json['name']),
        description: readString(json['description']),
        tableKey: readString(json['tableKey']),
        metadata: readMap(json['metadata']),
      );

  final String? baseId;
  final String? name;
  final String? description;
  final String? tableKey;
  final Map<String, dynamic>? metadata;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (tableKey != null) 'tableKey': tableKey,
        if (metadata != null) 'metadata': metadata,
      };
}

class ColumnTrimmed {
  const ColumnTrimmed({
    this.name,
    this.dataType,
  });

  factory ColumnTrimmed.fromJson(Map<String, dynamic> json) => ColumnTrimmed(
        name: readString(json['name']),
        dataType: readString(json['dataType']),
      );

  final String? name;
  final String? dataType;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (dataType != null) 'dataType': dataType,
      };
}

class TableWithColumns extends Table {
  const TableWithColumns({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    super.baseId,
    super.name,
    super.description,
    super.tableKey,
    super.metadata,
    this.columns,
  });

  factory TableWithColumns.fromJson(Map<String, dynamic> json) => TableWithColumns(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        name: readString(json['name']),
        description: readString(json['description']),
        tableKey: readString(json['tableKey']),
        metadata: readMap(json['metadata']),
        columns: readObjectList(json['columns'], ColumnTrimmed.fromJson),
      );

  final List<ColumnTrimmed>? columns;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (columns != null) 'columns': columns!.map((e) => e.toJson()).toList(),
      };
}

class ColumnMetadata {
  const ColumnMetadata({
    this.option,
    this.isNotNull,
    this.isPrimaryKey,
    this.isUnique,
    this.isAutoIncrement,
    this.maxLength,
    this.selectType,
  });

  factory ColumnMetadata.fromJson(Map<String, dynamic> json) => ColumnMetadata(
        option: readStringList(json['option']),
        isNotNull: readBool(json['isNotNull']),
        isPrimaryKey: readBool(json['isPrimaryKey']),
        isUnique: readBool(json['isUnique']),
        isAutoIncrement: readBool(json['isAutoIncrement']),
        maxLength: readInt(json['maxLength']),
        selectType: readString(json['selectType']),
      );

  final List<String>? option;
  final bool? isNotNull;
  final bool? isPrimaryKey;
  final bool? isUnique;
  final bool? isAutoIncrement;
  final int? maxLength;
  final String? selectType;

  Map<String, dynamic> toJson() => {
        if (option != null) 'option': option,
        if (isNotNull != null) 'isNotNull': isNotNull,
        if (isPrimaryKey != null) 'isPrimaryKey': isPrimaryKey,
        if (isUnique != null) 'isUnique': isUnique,
        if (isAutoIncrement != null) 'isAutoIncrement': isAutoIncrement,
        if (maxLength != null) 'maxLength': maxLength,
        if (selectType != null) 'selectType': selectType,
      };
}

class ValidationError {
  const ValidationError({
    this.rule,
    this.error,
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) => ValidationError(
        rule: readString(json['rule']),
        error: readString(json['error']),
      );

  final String? rule;
  final String? error;

  Map<String, dynamic> toJson() => {
        if (rule != null) 'rule': rule,
        if (error != null) 'error': error,
      };
}

class DropdownOption {
  const DropdownOption({
    this.label,
    this.value,
  });

  factory DropdownOption.fromJson(Map<String, dynamic> json) => DropdownOption(
        label: readString(json['label']),
        value: readString(json['value']),
      );

  final String? label;
  final String? value;

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        if (value != null) 'value': value,
      };
}

class Field {
  const Field({
    this.value,
    this.dataType,
    this.options,
    this.validations,
  });

  factory Field.fromJson(Map<String, dynamic> json) => Field(
        value: json['value'],
        dataType: readString(json['dataType']),
        options: readObjectList(json['options'], DropdownOption.fromJson),
        validations: readObjectList(json['validations'], ValidationError.fromJson),
      );

  final Object? value;
  final String? dataType;
  final List<DropdownOption>? options;
  final List<ValidationError>? validations;

  Map<String, dynamic> toJson() => {
        if (value != null) 'value': value,
        if (dataType != null) 'dataType': dataType,
        if (options != null) 'options': options!.map((e) => e.toJson()).toList(),
        if (validations != null) 'validations': validations!.map((e) => e.toJson()).toList(),
      };
}

class ValidationResponse {
  const ValidationResponse({
    this.value,
    this.errors,
  });

  factory ValidationResponse.fromJson(Map<String, dynamic> json) => ValidationResponse(
        value: json['value'],
        errors: readObjectList(json['errors'], ValidationError.fromJson),
      );

  final Object? value;
  final List<ValidationError>? errors;

  Map<String, dynamic> toJson() => {
        if (value != null) 'value': value,
        if (errors != null) 'errors': errors!.map((e) => e.toJson()).toList(),
      };
}

class Column extends BaseEntity {
  const Column({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.tableId,
    this.name,
    this.dataType,
    this.metadata,
    this.defaultValue,
    this.validations,
  });

  factory Column.fromJson(Map<String, dynamic> json) => Column(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        tableId: readString(json['tableId']),
        name: readString(json['name']),
        dataType: readString(json['dataType']),
        metadata: readObject(json['metadata'], ColumnMetadata.fromJson),
        defaultValue: readString(json['defaultValue']),
        validations: readObjectList(json['validations'], ValidationError.fromJson),
      );

  final String? baseId;
  final String? tableId;
  final String? name;
  final String? dataType;
  final ColumnMetadata? metadata;
  final String? defaultValue;
  final List<ValidationError>? validations;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (tableId != null) 'tableId': tableId,
        if (name != null) 'name': name,
        if (dataType != null) 'dataType': dataType,
        if (metadata != null) 'metadata': metadata!.toJson(),
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (validations != null) 'validations': validations!.map((e) => e.toJson()).toList(),
      };
}

class TableIndex extends BaseEntity {
  const TableIndex({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.tableId,
    this.indexName,
    this.columns,
    this.isUnique,
  });

  factory TableIndex.fromJson(Map<String, dynamic> json) => TableIndex(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        tableId: readString(json['tableId']),
        indexName: readString(json['indexName']),
        columns: readStringList(json['columns']),
        isUnique: readBool(json['isUnique']),
      );

  final String? baseId;
  final String? tableId;
  final String? indexName;
  final List<String>? columns;
  final bool? isUnique;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (tableId != null) 'tableId': tableId,
        if (indexName != null) 'indexName': indexName,
        if (columns != null) 'columns': columns,
        if (isUnique != null) 'isUnique': isUnique,
      };
}

/// Rename-only payload accepted by `PUT /tables/{tableId}/index/{id}`.
class TableIndexUpdateInput {
  const TableIndexUpdateInput({
    this.indexName,
  });

  factory TableIndexUpdateInput.fromJson(Map<String, dynamic> json) => TableIndexUpdateInput(
        indexName: readString(json['indexName']),
      );

  final String? indexName;

  Map<String, dynamic> toJson() => {
        if (indexName != null) 'indexName': indexName,
      };
}

class TableTrigger extends BaseEntity {
  const TableTrigger({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.tableId,
    this.eventType,
    this.eventTime,
    this.workflowId,
    this.workflowName,
  });

  factory TableTrigger.fromJson(Map<String, dynamic> json) => TableTrigger(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        tableId: readString(json['tableId']),
        eventType: readString(json['eventType']),
        eventTime: readString(json['eventTime']),
        workflowId: readString(json['workflowId']),
        workflowName: readString(json['workflowName']),
      );

  final String? baseId;
  final String? tableId;
  final String? eventType;
  final String? eventTime;
  final String? workflowId;

  /// Populated only by `listTriggers` (enrichment from the workflow service).
  final String? workflowName;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (tableId != null) 'tableId': tableId,
        if (eventType != null) 'eventType': eventType,
        if (eventTime != null) 'eventTime': eventTime,
        if (workflowId != null) 'workflowId': workflowId,
        if (workflowName != null) 'workflowName': workflowName,
      };
}

class TableWebhook extends BaseEntity {
  const TableWebhook({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.tableId,
    this.url,
    this.headers,
    this.eventTypes,
    this.method,
    this.active,
  });

  factory TableWebhook.fromJson(Map<String, dynamic> json) => TableWebhook(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        tableId: readString(json['tableId']),
        url: readString(json['url']),
        headers: readStringMap(json['headers']),
        eventTypes: readStringList(json['eventTypes']),
        method: readString(json['method']),
        active: readBool(json['active']),
      );

  final String? baseId;
  final String? tableId;
  final String? url;
  final Map<String, String>? headers;
  final List<String>? eventTypes;
  final String? method;
  final bool? active;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (tableId != null) 'tableId': tableId,
        if (url != null) 'url': url,
        if (headers != null) 'headers': headers,
        if (eventTypes != null) 'eventTypes': eventTypes,
        if (method != null) 'method': method,
        if (active != null) 'active': active,
      };
}

class DBFunctionMetadata {
  const DBFunctionMetadata({
    this.timeoutMs,
    this.methods,
    this.public,
  });

  factory DBFunctionMetadata.fromJson(Map<String, dynamic> json) => DBFunctionMetadata(
        timeoutMs: readInt(json['timeoutMs']),
        methods: readStringList(json['methods']),
        public: readBool(json['public']),
      );

  /// Execution timeout in ms; server default 10 000, capped at 55 000.
  final int? timeoutMs;

  /// HTTP methods the invoke route accepts; defaults to `["POST"]`.
  final List<String>? methods;

  /// Reserved: invokable without gateway auth. Defaults to false.
  final bool? public;

  Map<String, dynamic> toJson() => {
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
        if (methods != null) 'methods': methods,
        if (public != null) 'public': public,
      };
}

/// A user-authored JavaScript function scoped to a base.
class DBFunction extends BaseEntity {
  const DBFunction({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.name,
    this.functionKey,
    this.description,
    this.body,
    this.version,
    this.isActive,
    this.metadata,
  });

  factory DBFunction.fromJson(Map<String, dynamic> json) => DBFunction(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        name: readString(json['name']),
        functionKey: readString(json['functionKey']),
        description: readString(json['description']),
        body: readString(json['body']),
        version: readInt(json['version']),
        isActive: readBool(json['isActive']),
        metadata: readObject(json['metadata'], DBFunctionMetadata.fromJson),
      );

  final String? baseId;
  final String? name;

  /// URL slug the function is invoked under (`/v1/fn/{functionKey}`).
  final String? functionKey;

  final String? description;

  /// JavaScript source. Top-level `return` and `await` are allowed.
  final String? body;

  final int? version;
  final bool? isActive;
  final DBFunctionMetadata? metadata;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (name != null) 'name': name,
        if (functionKey != null) 'functionKey': functionKey,
        if (description != null) 'description': description,
        if (body != null) 'body': body,
        if (version != null) 'version': version,
        if (isActive != null) 'isActive': isActive,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };
}

/// Create/update payload; a body change auto-creates a version snapshot.
class DBFunctionUpsertInput {
  const DBFunctionUpsertInput({
    this.baseId,
    this.name,
    this.functionKey,
    this.description,
    this.body,
    this.isActive,
    this.metadata,
    this.comment,
  });

  factory DBFunctionUpsertInput.fromJson(Map<String, dynamic> json) => DBFunctionUpsertInput(
        baseId: readString(json['baseId']),
        name: readString(json['name']),
        functionKey: readString(json['functionKey']),
        description: readString(json['description']),
        body: readString(json['body']),
        isActive: readBool(json['isActive']),
        metadata: readObject(json['metadata'], DBFunctionMetadata.fromJson),
        comment: readString(json['comment']),
      );

  final String? baseId;
  final String? name;
  final String? functionKey;
  final String? description;
  final String? body;
  final bool? isActive;
  final DBFunctionMetadata? metadata;

  /// Label for the version snapshot created when the body changes.
  final String? comment;

  Map<String, dynamic> toJson() => {
        if (baseId != null) 'baseId': baseId,
        if (name != null) 'name': name,
        if (functionKey != null) 'functionKey': functionKey,
        if (description != null) 'description': description,
        if (body != null) 'body': body,
        if (isActive != null) 'isActive': isActive,
        if (metadata != null) 'metadata': metadata!.toJson(),
        if (comment != null) 'comment': comment,
      };
}

class DBFunctionVersion extends BaseEntity {
  const DBFunctionVersion({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.functionId,
    this.version,
    this.body,
    this.comment,
  });

  factory DBFunctionVersion.fromJson(Map<String, dynamic> json) => DBFunctionVersion(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        functionId: readString(json['functionId']),
        version: readInt(json['version']),
        body: readString(json['body']),
        comment: readString(json['comment']),
      );

  final String? functionId;
  final int? version;
  final String? body;
  final String? comment;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (functionId != null) 'functionId': functionId,
        if (version != null) 'version': version,
        if (body != null) 'body': body,
        if (comment != null) 'comment': comment,
      };
}

class FunctionExecuteError {
  const FunctionExecuteError({
    this.code,
    this.message,
    this.stack,
  });

  factory FunctionExecuteError.fromJson(Map<String, dynamic> json) => FunctionExecuteError(
        code: readString(json['code']),
        message: readString(json['message']),
        stack: readString(json['stack']),
      );

  /// `TIMEOUT`, `COMPILE_ERROR` or `FUNCTION_ERROR`.
  final String? code;

  final String? message;
  final String? stack;

  Map<String, dynamic> toJson() => {
        if (code != null) 'code': code,
        if (message != null) 'message': message,
        if (stack != null) 'stack': stack,
      };
}

/// Full console-execution result (returned even when the function itself failed).
class FunctionExecuteResult {
  const FunctionExecuteResult({
    this.success,
    this.result,
    this.logs,
    this.error,
    this.durationMs,
  });

  factory FunctionExecuteResult.fromJson(Map<String, dynamic> json) => FunctionExecuteResult(
        success: readBool(json['success']),
        result: json['result'],
        logs: readStringList(json['logs']),
        error: readObject(json['error'], FunctionExecuteError.fromJson),
        durationMs: readInt(json['durationMs']),
      );

  final bool? success;
  final Object? result;
  final List<String>? logs;
  final FunctionExecuteError? error;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        if (success != null) 'success': success,
        if (result != null) 'result': result,
        if (logs != null) 'logs': logs,
        if (error != null) 'error': error!.toJson(),
        if (durationMs != null) 'durationMs': durationMs,
      };
}

/// One step of an atomic record transaction.
class TransactionOperation {
  const TransactionOperation({
    required this.type,
    required this.table,
    this.id,
    this.record,
  });

  factory TransactionOperation.fromJson(Map<String, dynamic> json) => TransactionOperation(
        type: readString(json['type']) ?? '',
        table: readString(json['table']) ?? '',
        id: readString(json['id']),
        record: readMap(json['record']),
      );

  /// `create`, `update` or `delete`.
  final String type;

  final String table;

  /// Required for update and delete.
  final String? id;

  /// Fields for create and update.
  final Map<String, dynamic>? record;

  Map<String, dynamic> toJson() => {
        'type': type,
        'table': table,
        if (id != null) 'id': id,
        if (record != null) 'record': record,
      };
}

class TransactionResult {
  const TransactionResult({
    this.results,
  });

  factory TransactionResult.fromJson(Map<String, dynamic> json) => TransactionResult(
        results: readMapList(json['results']),
      );

  /// Per-operation results, in order: the written row, or `{deletedCount}` for deletes.
  final List<Map<String, dynamic>>? results;

  Map<String, dynamic> toJson() => {
        if (results != null) 'results': results,
      };
}

/// Payload of `publishEvent` (`ctx.events.publish` in DB functions).
class PublishEventInput {
  const PublishEventInput({
    required this.eventType,
    this.tableName,
    this.record,
    this.correlationId,
  });

  factory PublishEventInput.fromJson(Map<String, dynamic> json) => PublishEventInput(
        eventType: readString(json['eventType']) ?? '',
        tableName: readString(json['tableName']),
        record: readMap(json['record']),
        correlationId: readString(json['correlationId']),
      );

  /// Event name, e.g. `lead.qualified` (alphanumeric tokens separated by dots).
  final String eventType;

  /// Scopes the NATS subject's table segment; `_` when omitted.
  final String? tableName;

  final Map<String, dynamic>? record;
  final String? correlationId;

  Map<String, dynamic> toJson() => {
        'eventType': eventType,
        if (tableName != null) 'tableName': tableName,
        if (record != null) 'record': record,
        if (correlationId != null) 'correlationId': correlationId,
      };
}

class PublishEventResult {
  const PublishEventResult({
    this.published,
    this.subject,
  });

  factory PublishEventResult.fromJson(Map<String, dynamic> json) => PublishEventResult(
        published: readBool(json['published']),
        subject: readString(json['subject']),
      );

  final bool? published;
  final String? subject;

  Map<String, dynamic> toJson() => {
        if (published != null) 'published': published,
        if (subject != null) 'subject': subject,
      };
}

class TableView extends BaseEntity {
  const TableView({
    super.id,
    super.orgId,
    super.prn,
    super.createdAt,
    super.updatedAt,
    super.createdBy,
    super.updatedBy,
    this.baseId,
    this.name,
    this.description,
    this.viewKey,
    this.kind,
    this.definition,
    this.metadata,
  });

  factory TableView.fromJson(Map<String, dynamic> json) => TableView(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        prn: readString(json['prn']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        baseId: readString(json['baseId']),
        name: readString(json['name']),
        description: readString(json['description']),
        viewKey: readString(json['viewKey']),
        kind: readString(json['kind']),
        definition: readString(json['definition']),
        metadata: readMap(json['metadata']),
      );

  final String? baseId;
  final String? name;
  final String? description;
  final String? viewKey;

  /// `view` or `materialized_view`.
  final String? kind;

  final String? definition;
  final Map<String, dynamic>? metadata;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseId != null) 'baseId': baseId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (viewKey != null) 'viewKey': viewKey,
        if (kind != null) 'kind': kind,
        if (definition != null) 'definition': definition,
        if (metadata != null) 'metadata': metadata,
      };
}

class RunQueryRequest {
  const RunQueryRequest({
    required this.query,
    this.baseId,
  });

  factory RunQueryRequest.fromJson(Map<String, dynamic> json) => RunQueryRequest(
        query: readString(json['query']) ?? '',
        baseId: readString(json['baseId']),
      );

  final String query;
  final String? baseId;

  Map<String, dynamic> toJson() => {
        'query': query,
        if (baseId != null) 'baseId': baseId,
      };
}

class RowsResponse {
  const RowsResponse({
    this.rows,
  });

  factory RowsResponse.fromJson(Map<String, dynamic> json) => RowsResponse(
        rows: readMapList(json['rows']),
      );

  final List<Map<String, dynamic>>? rows;

  Map<String, dynamic> toJson() => {
        if (rows != null) 'rows': rows,
      };
}

class SuggestionsResponse {
  const SuggestionsResponse({
    this.suggestions,
  });

  factory SuggestionsResponse.fromJson(Map<String, dynamic> json) => SuggestionsResponse(
        suggestions: readStringList(json['suggestions']),
      );

  final List<String>? suggestions;

  Map<String, dynamic> toJson() => {
        if (suggestions != null) 'suggestions': suggestions,
      };
}

class CountResponse {
  const CountResponse({
    this.count,
  });

  factory CountResponse.fromJson(Map<String, dynamic> json) => CountResponse(
        count: readInt(json['count']),
      );

  final int? count;

  Map<String, dynamic> toJson() => {
        if (count != null) 'count': count,
      };
}

class DeleteCountResponse {
  const DeleteCountResponse({
    this.deletedCount,
  });

  factory DeleteCountResponse.fromJson(Map<String, dynamic> json) => DeleteCountResponse(
        deletedCount: readInt(json['deletedCount']),
      );

  final int? deletedCount;

  Map<String, dynamic> toJson() => {
        if (deletedCount != null) 'deletedCount': deletedCount,
      };
}

class ViewRefreshResponse {
  const ViewRefreshResponse({
    this.status,
  });

  factory ViewRefreshResponse.fromJson(Map<String, dynamic> json) => ViewRefreshResponse(
        status: readString(json['status']),
      );

  final String? status;

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
      };
}

class ColumnsBulkResult {
  const ColumnsBulkResult({
    this.created,
    this.failed,
  });

  factory ColumnsBulkResult.fromJson(Map<String, dynamic> json) => ColumnsBulkResult(
        created: readObjectList(json['created'], Column.fromJson),
        failed: readMapList(json['failed']),
      );

  final List<Column>? created;
  final List<Map<String, dynamic>>? failed;

  Map<String, dynamic> toJson() => {
        if (created != null) 'created': created!.map((e) => e.toJson()).toList(),
        if (failed != null) 'failed': failed,
      };
}

class RecordsBulkResult {
  const RecordsBulkResult({
    this.updated,
    this.failed,
  });

  factory RecordsBulkResult.fromJson(Map<String, dynamic> json) => RecordsBulkResult(
        updated: readMapList(json['updated']),
        failed: readMapList(json['failed']),
      );

  final List<Map<String, dynamic>>? updated;
  final List<Map<String, dynamic>>? failed;

  Map<String, dynamic> toJson() => {
        if (updated != null) 'updated': updated,
        if (failed != null) 'failed': failed,
      };
}

class OverviewCounts {
  const OverviewCounts({
    this.totals,
    this.bases,
  });

  factory OverviewCounts.fromJson(Map<String, dynamic> json) => OverviewCounts(
        totals: readIntMap(json['totals']),
        bases: readMapList(json['bases']),
      );

  final Map<String, int>? totals;
  final List<Map<String, dynamic>>? bases;

  Map<String, dynamic> toJson() => {
        if (totals != null) 'totals': totals,
        if (bases != null) 'bases': bases,
      };
}

class SyncTablesResult {
  const SyncTablesResult({
    this.tablesAdded,
    this.tablesRemoved,
    this.tablesUpdated,
    this.errors,
  });

  factory SyncTablesResult.fromJson(Map<String, dynamic> json) => SyncTablesResult(
        tablesAdded: readStringList(json['tablesAdded']),
        tablesRemoved: readStringList(json['tablesRemoved']),
        tablesUpdated: readStringList(json['tablesUpdated']),
        errors: readStringList(json['errors']),
      );

  final List<String>? tablesAdded;
  final List<String>? tablesRemoved;
  final List<String>? tablesUpdated;
  final List<String>? errors;

  Map<String, dynamic> toJson() => {
        if (tablesAdded != null) 'tablesAdded': tablesAdded,
        if (tablesRemoved != null) 'tablesRemoved': tablesRemoved,
        if (tablesUpdated != null) 'tablesUpdated': tablesUpdated,
        if (errors != null) 'errors': errors,
      };
}
