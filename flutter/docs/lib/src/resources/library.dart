import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents/{bucketName}/...` — the caller's personal library: starred
/// items, recent items and the trash.
class LibraryResource {
  /// Creates the resource on top of [_http].
  LibraryResource(this._http);

  final DocsHttpClient _http;

  String _bucket(String bucketName) => '$docsBasePath/${seg(bucketName)}';

  /// Stars node [nodeId] and returns the confirmation message.
  Future<String> star(String bucketName, String nodeId) async => decodeMessage(
      await _http.request('POST', '${_bucket(bucketName)}/nodes/${seg(nodeId)}/star'));

  /// Removes the caller's star from node [nodeId] and returns the
  /// confirmation message.
  Future<String> unstar(String bucketName, String nodeId) async => decodeMessage(
      await _http.request('DELETE', '${_bucket(bucketName)}/nodes/${seg(nodeId)}/star'));

  /// Stars the item at [path] and returns it. [type] is `file` (the default)
  /// or `folder`.
  Future<Document> starPath(String bucketName, String path, {String? type}) async => decodeOne(
      await _http.request('POST', '${_bucket(bucketName)}/star',
          body: StarByPathRequest(path: path, type: type)),
      Document.fromJson);

  /// Removes the caller's star from the item at [path] and returns the
  /// confirmation message.
  Future<String> unstarPath(String bucketName, String path) async => decodeMessage(
      await _http.request('DELETE', '${_bucket(bucketName)}/star', query: {'path': path}));

  /// The caller's starred items.
  Future<List<Document>> starred(String bucketName) async =>
      decodeMany(await _http.request('GET', '${_bucket(bucketName)}/starred'), Document.fromJson);

  /// The caller's recently used items, newest first; [limit] is 1-200
  /// (server default 50).
  Future<List<Document>> recent(String bucketName, {int? limit}) async => decodeMany(
      await _http.request('GET', '${_bucket(bucketName)}/recent', query: {'limit': limit}),
      Document.fromJson);

  /// The caller's trashed items.
  Future<List<Document>> trash(String bucketName) async =>
      decodeMany(await _http.request('GET', '${_bucket(bucketName)}/trash'), Document.fromJson);

  /// Restores trashed node [nodeId] and returns it.
  Future<Document> restore(String bucketName, String nodeId) async => decodeOne(
      await _http.request('POST', '${_bucket(bucketName)}/trash/${seg(nodeId)}/restore'),
      Document.fromJson);

  /// Permanently deletes trashed node [nodeId] and returns the confirmation
  /// message.
  Future<String> purge(String bucketName, String nodeId) async =>
      decodeMessage(await _http.request('DELETE', '${_bucket(bucketName)}/trash/${seg(nodeId)}'));
}
