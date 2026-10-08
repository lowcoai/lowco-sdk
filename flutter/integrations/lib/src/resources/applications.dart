import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/integrations/applications` — integration applications.
class ApplicationsResource {
  ApplicationsResource(this._http);

  final IntegrationsHttpClient _http;

  static const _path = '/v1/integrations/applications';

  Future<List<ApplicationWithCount>> list([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', _path, query: query?.toQuery()), ApplicationWithCount.fromJson);

  Future<Application> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Application.fromJson);

  Future<Application> create(Application payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), Application.fromJson);

  Future<Application> update(String id, Application payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), Application.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  /// Replaces the application's tags (`PATCH {"tags": [...]}`).
  Future<Application> patchTags(String id, List<String> tags) async => decodeOne(
      await _http.request('PATCH', '$_path/${seg(id)}/tags', body: PatchTagsRequest(tags: tags)),
      Application.fromJson);

  /// Runs the application; returns whatever the upstream call returned.
  Future<Object?> run(String id, RunApplicationRequest payload) =>
      _http.request('POST', '$_path/${seg(id)}/run', body: payload);

  /// Creates actions from a Postman collection folder.
  Future<List<ApplicationAction>> loadActions(String id, PostmanFolder folder) async => decodeMany(
      await _http.request('POST', '$_path/${seg(id)}/load-actions', body: folder),
      ApplicationAction.fromJson);

  Future<List<ApplicationHistory>> versions(String id, [PaginationQuery? query]) async =>
      decodeMany(await _http.request('GET', '$_path/${seg(id)}/versions', query: query?.toQuery()),
          ApplicationHistory.fromJson);

  Future<Application> regenerateMcpKey(String id) async => decodeOne(
      await _http.request('GET', '$_path/${seg(id)}/regenerate-mcp-key'), Application.fromJson);

  Future<McpToolsResponse> getMcpTools(String id) async => decodeOne(
      await _http.request('GET', '$_path/${seg(id)}/mcp/tools'), McpToolsResponse.fromJson);

  /// Application type -> sub types.
  Future<SubApplicationConfig> getSubApplications() async =>
      decodeStringListMap(await _http.request('GET', '$_path/types'));

  Future<List<Application>> getApplicationsWithTriggers() async =>
      decodeMany(await _http.request('GET', '$_path/by-trigger'), Application.fromJson);
}
