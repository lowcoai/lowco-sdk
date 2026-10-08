import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/wf/environments` — variable sets workflows run against.
class EnvironmentsResource {
  EnvironmentsResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/environments';

  Future<List<Environment>> list([PaginationQuery? query]) async =>
      decodeMany(await _http.request('GET', _path, query: query?.toQuery()), Environment.fromJson);

  Future<Environment> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Environment.fromJson);

  Future<Environment> create(Environment payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), Environment.fromJson);

  Future<Environment> update(String id, Environment payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), Environment.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  /// Makes this the org's default environment (`PATCH`, no body).
  Future<Environment> setDefault(String id) async =>
      decodeOne(await _http.request('PATCH', '$_path/${seg(id)}/default'), Environment.fromJson);
}
