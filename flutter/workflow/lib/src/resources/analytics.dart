import '../codec.dart';
import '../transport.dart';

/// `/v1/wf/analytics` — dashboard aggregates.
class AnalyticsResource {
  AnalyticsResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/analytics';

  /// `GET /v1/wf/analytics`. Named `default()` in the TS SDK; `default` is a
  /// reserved word in Dart.
  Future<Map<String, dynamic>> getDefault() async => decodeMap(await _http.request('GET', _path));

  Future<Map<String, dynamic>> getById(String id) async =>
      decodeMap(await _http.request('GET', '$_path/${seg(id)}'));
}
