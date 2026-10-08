import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents/webhooks` — call a URL when an object event happens under
/// a folder.
class WebhooksResource {
  /// Creates the resource on top of [_http].
  WebhooksResource(this._http);

  final DocsHttpClient _http;

  static const _path = '$docsBasePath/webhooks';

  /// The org's webhooks visible to the caller, optionally paged with [page]
  /// and [limit] (the platform's standard list query).
  Future<List<Webhook>> list({int? page, int? limit}) async => decodeMany(
      await _http.request('GET', _path, query: {'page': page, 'limit': limit}), Webhook.fromJson);

  /// Creates a webhook. `url`, `method`, `prefix` and at least one event type
  /// are required.
  Future<Webhook> create(WebhookRequest body) async =>
      decodeOne(await _http.request('POST', _path, body: body), Webhook.fromJson);

  /// The webhook [id].
  Future<Webhook> get(String id) async =>
      decodeOne(await _http.request('GET', '$_path/${seg(id)}'), Webhook.fromJson);

  /// Replaces every field of webhook [id] (at least one event type is
  /// required).
  Future<Webhook> update(String id, WebhookRequest body) async =>
      decodeOne(await _http.request('PUT', '$_path/${seg(id)}', body: body), Webhook.fromJson);

  /// Deletes webhook [id] (the service answers `204`).
  Future<void> delete(String id) async => _http.requestVoid('DELETE', '$_path/${seg(id)}');
}
