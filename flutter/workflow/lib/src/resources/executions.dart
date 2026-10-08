import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/executions` — workflow runs.
class ExecutionsResource {
  ExecutionsResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/executions';

  /// Lists executions. [full] (`?full=true`) asks for the complete records.
  Future<List<Execution>> list([PaginationQuery? query, bool? full]) async => decodeMany(
      await _http
          .request('GET', _path, query: {...?query?.toQuery(), if (full != null) 'full': full}),
      Execution.fromJson);

  /// A number, or an object, depending on the service version.
  Future<Object?> count([PaginationQuery? query]) =>
      _http.request('GET', '$_path/count', query: query?.toQuery());

  Future<Execution> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Execution.fromJson);

  Future<List<Object?>> logs(String id) async =>
      decodeList(await _http.request('GET', '$_path/${seg(id)}/logs'));
}
