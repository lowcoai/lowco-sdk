// Wire models for the workflow-orchestrator API (`/v1/wf/*`). Field names
// match the JSON the service sends and accepts; `toJson` omits null fields so
// partial payloads only send what you set. Non-optional TS fields are
// `required` here.

import 'json.dart';

/// A JSON object (`JsonObject` in the TS SDK).
typedef JsonObject = Map<String, dynamic>;

/// The `{ success, code, message, data, error }` envelope every workflow endpoint
/// answers with. The client unwraps `data` for you; this type is only for callers
/// that use `WorkflowHttpClient` with their own decoding.
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

/// Metadata fields shared by every workflow entity.
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

/// An environment variable.
class Variable {
  const Variable({
    this.id,
    required this.name,
    required this.value,
  });

  factory Variable.fromJson(Map<String, dynamic> json) => Variable(
        id: readString(json['id']),
        name: readString(json['name']) ?? '',
        value: readString(json['value']) ?? '',
      );

  final String? id;
  final String name;
  final String value;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'value': value,
      };
}

/// A named set of variables a workflow runs against.
class Environment extends BaseEntity {
  const Environment({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    this.isDefaultEnv,
    this.variables,
  });

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        isDefaultEnv: readBool(json['isDefaultEnv']),
        variables: readObjectList(json['variables'], Variable.fromJson),
      );

  final String name;
  final String? description;
  final bool? isDefaultEnv;
  final List<Variable>? variables;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        if (isDefaultEnv != null) 'isDefaultEnv': isDefaultEnv,
        if (variables != null) 'variables': variables!.map((e) => e.toJson()).toList(),
      };
}

/// A node of the workflow canvas.
///
/// Mirrors the TS `WorkflowUINode`, which has an index signature: every key
/// besides `id`, `type` and `data` (`position`, `measured`, `selected`, ...)
/// is kept in [extra] and written back by [toJson], so a UI graph read from
/// the server round-trips losslessly.
class WorkflowUINode {
  const WorkflowUINode({
    required this.id,
    this.type,
    this.data,
    this.extra = const <String, dynamic>{},
  });

  factory WorkflowUINode.fromJson(Map<String, dynamic> json) => WorkflowUINode(
        id: readString(json['id']) ?? '',
        type: readString(json['type']),
        data: readMap(json['data']),
        extra: {
          for (final e in json.entries)
            if (!knownKeys.contains(e.key)) e.key: e.value,
        },
      );

  /// Keys mapped to typed fields; everything else lands in [extra].
  static const Set<String> knownKeys = {'id', 'type', 'data'};

  final String id;
  final String? type;
  final Map<String, dynamic>? data;

  /// Any other keys of the node, kept verbatim (including `null` values).
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (type != null) 'type': type,
        if (data != null) 'data': data,
        for (final e in extra.entries)
          if (!knownKeys.contains(e.key)) e.key: e.value,
      };
}

/// An edge of the workflow canvas.
class WorkflowUIEdge {
  const WorkflowUIEdge({
    required this.id,
    required this.source,
    required this.target,
    this.type,
    this.label,
  });

  factory WorkflowUIEdge.fromJson(Map<String, dynamic> json) => WorkflowUIEdge(
        id: readString(json['id']) ?? '',
        source: readString(json['source']) ?? '',
        target: readString(json['target']) ?? '',
        type: readString(json['type']),
        label: readString(json['label']),
      );

  final String id;
  final String source;
  final String target;
  final String? type;
  final String? label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'target': target,
        if (type != null) 'type': type,
        if (label != null) 'label': label,
      };
}

/// The workflow canvas (React Flow graph).
class WorkflowUI {
  const WorkflowUI({
    required this.nodes,
    required this.edges,
  });

  factory WorkflowUI.fromJson(Map<String, dynamic> json) => WorkflowUI(
        nodes: readObjectList(json['nodes'], WorkflowUINode.fromJson) ?? const <WorkflowUINode>[],
        edges: readObjectList(json['edges'], WorkflowUIEdge.fromJson) ?? const <WorkflowUIEdge>[],
      );

  final List<WorkflowUINode> nodes;
  final List<WorkflowUIEdge> edges;

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((e) => e.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };
}

class Workflow extends BaseEntity {
  const Workflow({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    this.inputData,
    required this.ui,
    this.tags,
    this.version,
    this.published,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) => Workflow(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        inputData: readMap(json['inputData']),
        ui: readObject(json['ui'], WorkflowUI.fromJson) ??
            WorkflowUI.fromJson(const <String, dynamic>{}),
        tags: readStringList(json['tags']),
        version: readInt(json['version']),
        published: readBool(json['published']),
      );

  final String name;
  final String? description;
  final Map<String, dynamic>? inputData;
  final WorkflowUI ui;
  final List<String>? tags;
  final int? version;
  final bool? published;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        if (inputData != null) 'inputData': inputData,
        'ui': ui.toJson(),
        if (tags != null) 'tags': tags,
        if (version != null) 'version': version,
        if (published != null) 'published': published,
      };
}

/// Create/update payload: a [Workflow] plus a version `comment`.
class WorkflowUpdateRequest extends Workflow {
  const WorkflowUpdateRequest({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required super.name,
    super.description,
    super.inputData,
    required super.ui,
    super.tags,
    super.version,
    super.published,
    this.comment,
  });

  factory WorkflowUpdateRequest.fromJson(Map<String, dynamic> json) => WorkflowUpdateRequest(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        inputData: readMap(json['inputData']),
        ui: readObject(json['ui'], WorkflowUI.fromJson) ??
            WorkflowUI.fromJson(const <String, dynamic>{}),
        tags: readStringList(json['tags']),
        version: readInt(json['version']),
        published: readBool(json['published']),
        comment: readString(json['comment']),
      );

  final String? comment;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (comment != null) 'comment': comment,
      };
}

/// Starts a workflow, or resumes it from [activityId] of [executionId].
class RunWorkflowRequest {
  const RunWorkflowRequest({
    required this.workflowId,
    this.inputData,
    this.environmentId,
    this.triggeredBy,
    this.orgId,
    this.activityId,
    this.executionId,
  });

  factory RunWorkflowRequest.fromJson(Map<String, dynamic> json) => RunWorkflowRequest(
        workflowId: readString(json['workflowId']) ?? '',
        inputData: readMap(json['inputData']),
        environmentId: readString(json['environmentId']),
        triggeredBy: readString(json['triggeredBy']),
        orgId: readString(json['orgId']),
        activityId: readString(json['activityId']),
        executionId: readString(json['executionId']),
      );

  final String workflowId;
  final Map<String, dynamic>? inputData;
  final String? environmentId;
  final String? triggeredBy;
  final String? orgId;
  final String? activityId;
  final String? executionId;

  Map<String, dynamic> toJson() => {
        'workflowId': workflowId,
        if (inputData != null) 'inputData': inputData,
        if (environmentId != null) 'environmentId': environmentId,
        if (triggeredBy != null) 'triggeredBy': triggeredBy,
        if (orgId != null) 'orgId': orgId,
        if (activityId != null) 'activityId': activityId,
        if (executionId != null) 'executionId': executionId,
      };
}

/// A reusable JavaScript function.
class FunctionEntity extends BaseEntity {
  const FunctionEntity({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.name,
    this.description,
    required this.body,
    this.version,
    this.isActive,
  });

  factory FunctionEntity.fromJson(Map<String, dynamic> json) => FunctionEntity(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        name: readString(json['name']) ?? '',
        description: readString(json['description']),
        body: readString(json['body']) ?? '',
        version: readInt(json['version']),
        isActive: readBool(json['isActive']),
      );

  final String name;
  final String? description;
  final String body;
  final int? version;
  final bool? isActive;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
        if (description != null) 'description': description,
        'body': body,
        if (version != null) 'version': version,
        if (isActive != null) 'isActive': isActive,
      };
}

/// Update payload of `functions.update`: the function plus a version comment.
class FunctionVersionRequest {
  const FunctionVersionRequest({
    required this.function,
    this.comment,
  });

  factory FunctionVersionRequest.fromJson(Map<String, dynamic> json) => FunctionVersionRequest(
        function: readObject(json['function'], FunctionEntity.fromJson) ??
            FunctionEntity.fromJson(const <String, dynamic>{}),
        comment: readString(json['comment']),
      );

  final FunctionEntity function;
  final String? comment;

  Map<String, dynamic> toJson() => {
        'function': function.toJson(),
        if (comment != null) 'comment': comment,
      };
}

/// A button offered to the assignee of a human task.
class HumanTaskAction {
  const HumanTaskAction({
    required this.text,
    required this.value,
  });

  factory HumanTaskAction.fromJson(Map<String, dynamic> json) => HumanTaskAction(
        text: readString(json['text']) ?? '',
        value: readString(json['value']) ?? '',
      );

  final String text;
  final String value;

  Map<String, dynamic> toJson() => {
        'text': text,
        'value': value,
      };
}

class HumanTask extends BaseEntity {
  const HumanTask({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.message,
    this.actions,
    this.assignedTo,
    required this.executionId,
    required this.workflowId,
    this.answer,
    this.completed,
    this.completedAt,
    required this.activityId,
  });

  factory HumanTask.fromJson(Map<String, dynamic> json) => HumanTask(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        message: readString(json['message']) ?? '',
        actions: readObjectList(json['actions'], HumanTaskAction.fromJson),
        assignedTo: readString(json['assignedTo']),
        executionId: readString(json['executionId']) ?? '',
        workflowId: readString(json['workflowId']) ?? '',
        answer: readString(json['answer']),
        completed: readBool(json['completed']),
        completedAt: readString(json['completedAt']),
        activityId: readString(json['activityId']) ?? '',
      );

  final String message;
  final List<HumanTaskAction>? actions;
  final String? assignedTo;
  final String executionId;
  final String workflowId;
  final String? answer;
  final bool? completed;

  /// ISO-8601 timestamp.
  final String? completedAt;

  final String activityId;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'message': message,
        if (actions != null) 'actions': actions!.map((e) => e.toJson()).toList(),
        if (assignedTo != null) 'assignedTo': assignedTo,
        'executionId': executionId,
        'workflowId': workflowId,
        if (answer != null) 'answer': answer,
        if (completed != null) 'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        'activityId': activityId,
      };
}

/// One run of a workflow.
class Execution extends BaseEntity {
  const Execution({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.workflowId,
    this.correlationId,
    this.version,
    this.status,
    this.context,
    this.failedReason,
    this.inputData,
    this.outputData,
    this.workflow,
  });

  factory Execution.fromJson(Map<String, dynamic> json) => Execution(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        workflowId: readString(json['workflowId']) ?? '',
        correlationId: readString(json['correlationId']),
        version: readInt(json['version']),
        status: readString(json['status']),
        context: readMap(json['context']),
        failedReason: readString(json['failedReason']),
        inputData: json['inputData'],
        outputData: json['outputData'],
        workflow: readObject(json['workflow'], Workflow.fromJson),
      );

  final String workflowId;
  final String? correlationId;
  final int? version;
  final String? status;
  final Map<String, dynamic>? context;
  final String? failedReason;
  final Object? inputData;
  final Object? outputData;
  final Workflow? workflow;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'workflowId': workflowId,
        if (correlationId != null) 'correlationId': correlationId,
        if (version != null) 'version': version,
        if (status != null) 'status': status,
        if (context != null) 'context': context,
        if (failedReason != null) 'failedReason': failedReason,
        if (inputData != null) 'inputData': inputData,
        if (outputData != null) 'outputData': outputData,
        if (workflow != null) 'workflow': workflow!.toJson(),
      };
}

/// One activity (node) run inside an execution.
class ActivityExecutionHistory extends BaseEntity {
  const ActivityExecutionHistory({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.activityId,
    required this.workflowId,
    required this.executionId,
    this.type,
    this.typeId,
    this.status,
    this.inputData,
    this.outputData,
    this.failedReason,
  });

  factory ActivityExecutionHistory.fromJson(Map<String, dynamic> json) => ActivityExecutionHistory(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        activityId: readString(json['activityId']) ?? '',
        workflowId: readString(json['workflowId']) ?? '',
        executionId: readString(json['executionId']) ?? '',
        type: readString(json['type']),
        typeId: readString(json['typeId']),
        status: readString(json['status']),
        inputData: json['inputData'],
        outputData: json['outputData'],
        failedReason: readString(json['failedReason']),
      );

  final String activityId;
  final String workflowId;
  final String executionId;
  final String? type;
  final String? typeId;
  final String? status;
  final Object? inputData;
  final Object? outputData;
  final String? failedReason;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'activityId': activityId,
        'workflowId': workflowId,
        'executionId': executionId,
        if (type != null) 'type': type,
        if (typeId != null) 'typeId': typeId,
        if (status != null) 'status': status,
        if (inputData != null) 'inputData': inputData,
        if (outputData != null) 'outputData': outputData,
        if (failedReason != null) 'failedReason': failedReason,
      };
}

class ActivityHistoryResponse {
  const ActivityHistoryResponse({
    required this.id,
    required this.history,
    this.activity,
    this.workflow,
    this.execution,
  });

  factory ActivityHistoryResponse.fromJson(Map<String, dynamic> json) => ActivityHistoryResponse(
        id: readString(json['id']) ?? '',
        history: readObject(json['history'], ActivityExecutionHistory.fromJson) ??
            ActivityExecutionHistory.fromJson(const <String, dynamic>{}),
        activity: readMap(json['activity']),
        workflow: readObject(json['workflow'], Workflow.fromJson),
        execution: readObject(json['execution'], Execution.fromJson),
      );

  final String id;
  final ActivityExecutionHistory history;
  final Map<String, dynamic>? activity;
  final Workflow? workflow;
  final Execution? execution;

  Map<String, dynamic> toJson() => {
        'id': id,
        'history': history.toJson(),
        if (activity != null) 'activity': activity,
        if (workflow != null) 'workflow': workflow!.toJson(),
        if (execution != null) 'execution': execution!.toJson(),
      };
}

/// A workflow published as a template.
class WorkflowPublish extends BaseEntity {
  const WorkflowPublish({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.createdAt,
    super.updatedAt,
    required this.workflowId,
    this.sourceOrgId,
    this.category,
    this.longDescription,
    this.workflow,
  });

  factory WorkflowPublish.fromJson(Map<String, dynamic> json) => WorkflowPublish(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        workflowId: readString(json['workflowId']) ?? '',
        sourceOrgId: readString(json['sourceOrgId']),
        category: readString(json['category']),
        longDescription: readString(json['longDescription']),
        workflow: readObject(json['workflow'], Workflow.fromJson),
      );

  final String workflowId;
  final String? sourceOrgId;
  final String? category;
  final String? longDescription;
  final Workflow? workflow;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'workflowId': workflowId,
        if (sourceOrgId != null) 'sourceOrgId': sourceOrgId,
        if (category != null) 'category': category,
        if (longDescription != null) 'longDescription': longDescription,
        if (workflow != null) 'workflow': workflow!.toJson(),
      };
}

/// Body of `workflows.publish` / `workflows.updatePublished` (an inline type in the TS SDK,
/// `WorkflowPublishRequest` in the Go SDK).
class WorkflowPublishRequest {
  const WorkflowPublishRequest({
    required this.category,
    required this.longDescription,
  });

  factory WorkflowPublishRequest.fromJson(Map<String, dynamic> json) => WorkflowPublishRequest(
        category: readString(json['category']) ?? '',
        longDescription: readString(json['longDescription']) ?? '',
      );

  final String category;
  final String longDescription;

  Map<String, dynamic> toJson() => {
        'category': category,
        'longDescription': longDescription,
      };
}

/// Evaluates an expression against a finished execution's data.
class DryRunRequest {
  const DryRunRequest({
    required this.executionId,
    required this.expression,
    required this.typeOfExpression,
    required this.activityId,
  });

  factory DryRunRequest.fromJson(Map<String, dynamic> json) => DryRunRequest(
        executionId: readString(json['executionId']) ?? '',
        expression: readString(json['expression']) ?? '',
        typeOfExpression: readString(json['typeOfExpression']) ?? '',
        activityId: readString(json['activityId']) ?? '',
      );

  final String executionId;
  final String expression;

  /// `object`, `string`, `statement` or `map`.
  final String typeOfExpression;

  final String activityId;

  Map<String, dynamic> toJson() => {
        'executionId': executionId,
        'expression': expression,
        'typeOfExpression': typeOfExpression,
        'activityId': activityId,
      };
}
