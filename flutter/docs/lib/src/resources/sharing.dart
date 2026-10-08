import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents/{bucketName}/shares`, `/share-links`, `/shared-with-me`
/// and `/v1/documents/link/{token}` — share My Drive items with members, the
/// org or by link. Managing shares requires owning the item.
class SharingResource {
  /// Creates the resource on top of [_http].
  SharingResource(this._http);

  final DocsHttpClient _http;

  String _bucket(String bucketName) => '$docsBasePath/${seg(bucketName)}';

  /// Grants a member (or the whole org) access to a My Drive item.
  Future<Share> create(String bucketName, CreateShareRequest body) async => decodeOne(
      await _http.request('POST', '${_bucket(bucketName)}/shares', body: body), Share.fromJson);

  /// The grants on the item at [path]; [type] is `file` (the default) or
  /// `folder`.
  Future<List<Share>> list(String bucketName,
          {required String path, String? type}) async =>
      decodeMany(
          await _http
              .request('GET', '${_bucket(bucketName)}/shares', query: {'path': path, 'type': type}),
          Share.fromJson);

  /// Revokes grant [id] and returns the confirmation message.
  Future<String> delete(String bucketName, String id) async =>
      decodeMessage(await _http.request('DELETE', '${_bucket(bucketName)}/shares/${seg(id)}'));

  /// Items other members shared with the caller, optionally only those of
  /// app [appKey] (e.g. `notes`).
  Future<List<Document>> sharedWithMe(String bucketName, {String? appKey}) async => decodeMany(
      await _http
          .request('GET', '${_bucket(bucketName)}/shared-with-me', query: {'appKey': appKey}),
      Document.fromJson);

  /// Mints an org-scope link for a My Drive file.
  Future<ShareLinkCreated> createLink(String bucketName, CreateShareLinkRequest body) async =>
      decodeOne(await _http.request('POST', '${_bucket(bucketName)}/share-links', body: body),
          ShareLinkCreated.fromJson);

  /// The links of the item at [path]; [type] is `file` (the default) or
  /// `folder`.
  Future<List<ShareLink>> listLinks(String bucketName,
          {required String path, String? type}) async =>
      decodeMany(
          await _http.request('GET', '${_bucket(bucketName)}/share-links',
              query: {'path': path, 'type': type}),
          ShareLink.fromJson);

  /// Revokes link [id] and returns the confirmation message.
  Future<String> deleteLink(String bucketName, String id) async =>
      decodeMessage(await _http.request('DELETE', '${_bucket(bucketName)}/share-links/${seg(id)}'));

  /// Follows share link [token] and returns a fresh short-lived URL for the
  /// file (the `Location` of the `307`; the redirect is not followed).
  ///
  /// Needs an HTTP client that can disable redirects, so it throws a
  /// `DocsException` on the web.
  Future<String> resolveLink(String token) async =>
      _http.requestRedirect('GET', '$docsBasePath/link/${seg(token)}');
}
