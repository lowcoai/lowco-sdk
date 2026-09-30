import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/integrations/connections` — stored credentials.
class ConnectionsResource {
  ConnectionsResource(this._http);

  final IntegrationsHttpClient _http;

  static const _path = '/v1/integrations/connections';

  Future<List<Connection>> list([PaginationQuery? query]) async =>
      decodeMany(await _http.request('GET', _path, query: query?.toQuery()), Connection.fromJson);

  Future<ConnectionResponse> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), ConnectionResponse.fromJson);

  Future<Connection> create(Connection payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), Connection.fromJson);

  Future<Connection> update(String id, Connection payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), Connection.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  Future<List<Connection>> listByApplication(String applicationId) async => decodeMany(
      await _http.request('GET', '/v1/integrations/applications/${seg(applicationId)}/connections'),
      Connection.fromJson);

  /// Makes this the default connection of [applicationId]
  /// (`PATCH {"applicationId": ...}`).
  Future<Connection> setAsDefault(String id, String applicationId) async => decodeOne(
      await _http.request('PATCH', '$_path/${seg(id)}/setDefault',
          body: SetAsDefaultRequest(applicationId: applicationId)),
      Connection.fromJson);
}
