import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/integrations/actions` — operations of applications.
class ActionsResource {
  ActionsResource(this._http);

  final IntegrationsHttpClient _http;

  static const _path = '/v1/integrations/actions';

  Future<List<ApplicationAction>> list([PaginationQuery? query]) async => decodeMany(
      await _http.request('GET', _path, query: query?.toQuery()), ApplicationAction.fromJson);

  Future<ApplicationAction> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), ApplicationAction.fromJson);

  /// `POST /v1/integrations/applications/{applicationId}/action`.
  Future<ApplicationAction> create(String applicationId, ApplicationAction payload) async =>
      decodeOne(
          await _http.request('POST', '/v1/integrations/applications/${seg(applicationId)}/action',
              body: payload),
          ApplicationAction.fromJson);

  Future<ApplicationAction> update(String id, ApplicationAction payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), ApplicationAction.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  Future<List<ApplicationAction>> listByApplication(String applicationId) async => decodeMany(
      await _http.request('GET', '/v1/integrations/applications/${seg(applicationId)}/actions'),
      ApplicationAction.fromJson);

  /// Runs the action; returns whatever the upstream call returned.
  Future<Object?> run(String id, RunActionRequest payload) =>
      _http.request('POST', '$_path/${seg(id)}/run', body: payload);

  /// Resolves the applications (with their connections) behind [actionIds].
  /// The body is the raw id list.
  Future<List<ApplicationWithConnection>> resolveCredentials(List<String> actionIds) async =>
      decodeMany(await _http.request('POST', '$_path/allCredential', body: actionIds),
          ApplicationWithConnection.fromJson);
}
