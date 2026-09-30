import '../codec.dart';
import '../models.dart';
import '../query.dart';
import '../transport.dart';

/// `/v1/integrations/triggers` — application triggers.
class TriggersResource {
  TriggersResource(this._http);

  final IntegrationsHttpClient _http;

  static const _path = '/v1/integrations/triggers';

  Future<List<ApplicationTrigger>> listByApplication(String applicationId,
          [PaginationQuery? query]) async =>
      decodeMany(
          await _http.request('GET', '/v1/integrations/applications/${seg(applicationId)}/triggers',
              query: query?.toQuery()),
          ApplicationTrigger.fromJson);

  Future<ApplicationTrigger> getById(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), ApplicationTrigger.fromJson);

  Future<ApplicationTrigger> create(ApplicationTrigger payload) async =>
      decodeOne(await _http.request('POST', _path, body: payload), ApplicationTrigger.fromJson);

  Future<ApplicationTrigger> update(String id, ApplicationTrigger payload) async => decodeOne(
      await _http.request('PUT', '$_path/${seg(id)}', body: payload), ApplicationTrigger.fromJson);

  Future<void> delete(String id) => _http.requestVoid('DELETE', '$_path/${seg(id)}');

  Future<TriggerState> getState(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}/state'), TriggerState.fromJson);
}
