import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/activities` — per-node execution history.
class ActivitiesResource {
  ActivitiesResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/activities';

  Future<List<ActivityHistoryResponse>> list([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', _path, query: query?.toQuery()), ActivityHistoryResponse.fromJson);

  /// A number, or an object, depending on the service version.
  Future<Object?> count([PaginationQuery? query]) =>
      _http.request('GET', '$_path/count', query: query?.toQuery());

  Future<ActivityHistoryResponse> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), ActivityHistoryResponse.fromJson);

  Future<List<Object?>> logs(String id) async =>
      decodeList(await _http.request('GET', '$_path/${seg(id)}/logs'));
}
