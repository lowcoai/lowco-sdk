import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/functions` — reusable JavaScript functions.
class FunctionsResource {
  FunctionsResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/functions';

  Future<List<FunctionEntity>> list([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', _path, query: query?.toQuery()), FunctionEntity.fromJson);

  Future<FunctionEntity> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), FunctionEntity.fromJson);

  Future<FunctionEntity> create(FunctionEntity payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), FunctionEntity.fromJson);

  Future<FunctionEntity> update(String id, FunctionVersionRequest payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), FunctionEntity.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  Future<List<FunctionEntity>> versions(String id, [PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', '$_path/${seg(id)}/versions', query: query?.toQuery()),
      FunctionEntity.fromJson);

  /// Runs the function with [params] (defaults to `{}`).
  Future<Map<String, dynamic>> execute(String id, [Map<String, dynamic>? params]) async =>
      decodeMap(await _http.request('POST', '$_path/${seg(id)}/execute',
          body: params ?? const <String, dynamic>{}));
}
