import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents/triggers` — run a workflow when an object event happens
/// under a folder.
class TriggersResource {
  /// Creates the resource on top of [_http].
  TriggersResource(this._http);

  final DocsHttpClient _http;

  static const _path = '$docsBasePath/triggers';

  /// The org's triggers visible to the caller.
  Future<List<Trigger>> list() async =>
      decodeMany(await _http.request('GET', _path), Trigger.fromJson);

  /// Creates a trigger. `prefix` and `workflowId` are required; a prefix in a
  /// personal space (`.users/{id}/`) may only be the caller's own.
  Future<Trigger> create(TriggerRequest body) async =>
      decodeOne(await _http.request('POST', _path, body: body), Trigger.fromJson);

  /// The trigger [id].
  Future<Trigger> get(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Trigger.fromJson);

  /// Replaces every field of trigger [id].
  Future<Trigger> update(String id, TriggerRequest body) async =>
      decodeOne(await _http.request('PUT', '$_path/${seg(id)}', body: body), Trigger.fromJson);

  /// Deletes trigger [id].
  Future<void> delete(String id) async => _http.requestVoid('DELETE', '$_path/${seg(id)}');
}
