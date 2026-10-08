import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/workflows` — workflows, their versions and published templates.
class WorkflowsResource {
  WorkflowsResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/workflows';

  Future<List<Workflow>> list([PaginationQuery? query]) async =>
      decodeMany(await _http.request('GET', _path, query: query?.toQuery()), Workflow.fromJson);

  /// A number, or an object, depending on the service version.
  Future<Object?> count([PaginationQuery? query]) =>
      _http.request('GET', '$_path/count', query: query?.toQuery());

  Future<Workflow> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Workflow.fromJson);

  /// Pass a [WorkflowUpdateRequest] to attach a version `comment`.
  Future<Workflow> create(Workflow payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), Workflow.fromJson);

  /// Pass a [WorkflowUpdateRequest] to attach a version `comment`.
  Future<Workflow> update(String id, Workflow payload) async =>
      decodeOne(await _http.request('PUT', '$_path/${seg(id)}', body: payload), Workflow.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  /// Starts a workflow, or resumes it from `activityId` of `executionId`.
  Future<Map<String, dynamic>> run(RunWorkflowRequest payload) async =>
      decodeMap(await _http.request('POST', '$_path/run', body: payload));

  Future<List<Workflow>> versions(String id, [PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', '$_path/${seg(id)}/versions', query: query?.toQuery()),
      Workflow.fromJson);

  Future<WorkflowPublish> publish(String id, WorkflowPublishRequest payload) async => decodeOne(
      await _http.request('POST', '$_path/${seg(id)}/publish', body: payload),
      WorkflowPublish.fromJson);

  Future<List<WorkflowPublish>> published([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', '$_path/published', query: query?.toQuery()),
      WorkflowPublish.fromJson);

  /// A number, or an object, depending on the service version.
  Future<Object?> publishedCount([PaginationQuery? query]) =>
      _http.request('GET', '$_path/published/count', query: query?.toQuery());

  Future<WorkflowPublish> getPublishedById(String id) async => decodeOne(
      await _http.request('GET', '$_path/published/${seg(id)}'), WorkflowPublish.fromJson);

  Future<WorkflowPublish> updatePublished(String id, WorkflowPublishRequest payload) async =>
      decodeOne(await _http.request('PUT', '$_path/published/${seg(id)}', body: payload),
          WorkflowPublish.fromJson);

  Future<void> deletePublished(String id) =>
      _http.requestVoid('DELETE', '$_path/published/${seg(id)}');

  Future<List<WorkflowPublish>> webPublished([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', '$_path/published/web', query: query?.toQuery()),
      WorkflowPublish.fromJson);

  Future<WorkflowPublish> webPublishedById(String id) async => decodeOne(
      await _http.request('GET', '$_path/published/web/${seg(id)}'), WorkflowPublish.fromJson);

  Future<List<WorkflowPublish>> searchPublishedTemplates(
          {String? q, String? category, int? limit}) async =>
      decodeMany(
          await _http.request('GET', '$_path/published/web/search',
              query: {'q': q, 'category': category, 'limit': limit}),
          WorkflowPublish.fromJson);
}
