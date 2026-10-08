import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/integrations/configurations`.
class ConfigurationsResource {
  ConfigurationsResource(this._http);

  final IntegrationsHttpClient _http;

  /// Application type -> sub types.
  Future<SubApplicationConfig> get() async =>
      decodeStringListMap(await _http.request('GET', '/v1/integrations/configurations'));
}
