import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/human-tasks` — approvals / decisions waiting on a person.
class HumanTasksResource {
  HumanTasksResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/human-tasks';

  Future<List<HumanTask>> list([PaginationQuery? query]) async =>
      decodeMany(await _http.request('GET', _path, query: query?.toQuery()), HumanTask.fromJson);

  Future<HumanTask> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), HumanTask.fromJson);

  /// Answers the task with one of its action values; the workflow resumes.
  Future<HumanTask> complete(String id, String action) async => decodeOne(
      await _http.request('PATCH', '$_path/${seg(id)}/complete', body: {'action': action}),
      HumanTask.fromJson);
}
