import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// Published applications exposed as MCP servers (JSON-RPC).
class McpResource {
  McpResource(this._http);

  final IntegrationsHttpClient _http;

  static const _path = '/v1/integrations/applications/published';

  /// Sends a JSON-RPC request (e.g. `tools/list`, `tools/call`) to the
  /// application published under [key].
  Future<JsonRpcResponse> callPublished(String key, JsonRpcRequest payload) async => decodeOne(
      await _http.request('POST', '$_path/${seg(key)}', body: payload), JsonRpcResponse.fromJson);

  Future<Map<String, dynamic>> infoPublished(String key) async =>
      decodeMap(await _http.request('GET', '$_path/${seg(key)}'));
}
