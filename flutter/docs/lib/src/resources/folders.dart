import '../codec.dart';
import '../models.dart';
import '../transfer.dart';
import '../transport.dart';

/// `/v1/documents/{bucketName}/...` — list, create, upload, zip, copy,
/// rename and delete folders.
///
/// [sizes] on the list methods: `false` skips the recursive folder sizes
/// (folders then report size `0`), which makes large listings faster.
class FoldersResource {
  /// Creates the resource on top of [_http].
  FoldersResource(this._http);

  final DocsHttpClient _http;

  String _bucket(String bucketName) => '$docsBasePath/${seg(bucketName)}';

  /// The direct children of [prefix] (the library root when omitted). Rows
  /// carry the node id, URLs, the caller's role (`metadata['role']`), the
  /// etag and a sharing badge on items the caller owns.
  Future<List<Document>> list(String bucketName, {String? prefix, bool? sizes}) async => decodeMany(
      await _http.request('GET', '${_bucket(bucketName)}/objects',
          query: {'prefix': prefix, 'sizes': sizes}),
      Document.fromJson);

  /// Like [list] for the folder at [path], given in the URL
  /// (`/objects/{path}`; `/` separators are kept).
  Future<List<Document>> listAt(String bucketName, String path, {bool? sizes}) async => decodeMany(
      await _http
          .request('GET', '${_bucket(bucketName)}/objects/${segs(path)}', query: {'sizes': sizes}),
      Document.fromJson);

  /// Same listing as [list] for the org-library folder [prefix], addressed by
  /// `?prefix=` only (`/public/objects`).
  Future<List<Document>> listPublic(String bucketName, {String? prefix, bool? sizes}) async =>
      decodeMany(
          await _http.request('GET', '${_bucket(bucketName)}/public/objects',
              query: {'prefix': prefix, 'sizes': sizes}),
          Document.fromJson);

  /// The personal drive of [userId] (optionally the folder [prefix] inside
  /// it).
  Future<List<Document>> listUser(String bucketName, String userId,
          {String? prefix, bool? sizes}) async =>
      decodeMany(
          await _http.request('GET', '${_bucket(bucketName)}/users/${seg(userId)}/objects',
              query: {'prefix': prefix, 'sizes': sizes}),
          Document.fromJson);

  /// The data area of app [appId] (`.apps/{appId}/`, optionally the folder
  /// [prefix] inside it).
  Future<List<Document>> listApp(String bucketName, String appId,
          {String? prefix, bool? sizes}) async =>
      decodeMany(
          await _http.request('GET', '${_bucket(bucketName)}/apps/${seg(appId)}/objects',
              query: {'prefix': prefix, 'sizes': sizes}),
          Document.fromJson);

  /// The raw listing of the folder named [key] (one segment): unlike [list],
  /// names are full keys and no role, sharing or size enrichment is applied.
  Future<List<Document>> get(String bucketName, String key) async => decodeMany(
      await _http.request('GET', '${_bucket(bucketName)}/folder/${seg(key)}'), Document.fromJson);

  /// Creates a folder; a nested `folderName` (`a/b/c`) creates every level.
  /// Returns every level created, outermost first.
  Future<List<Document>> create(String bucketName, CreateFolderRequest body) async => decodeMany(
      await _http.request('POST', '${_bucket(bucketName)}/folder', body: body), Document.fromJson);

  /// Deletes the top-level folder named [key] (one segment; use
  /// [deleteByPath] for nested folders) and returns the confirmation message.
  /// Library and personal folders move to the trash; `.apps/` folders are
  /// deleted permanently.
  Future<String> delete(String bucketName, String key) async =>
      decodeMessage(await _http.request('DELETE', '${_bucket(bucketName)}/folder/${seg(key)}'));

  /// Deletes the folder at [path] (`DELETE /folder?path=`), nested or not,
  /// and returns the confirmation message.
  Future<String> deleteByPath(String bucketName, String path) async => decodeMessage(
      await _http.request('DELETE', '${_bucket(bucketName)}/folder', query: {'path': path}));

  /// Uploads many [files] at once (multipart, one `files` part each).
  ///
  /// [relativePaths] gives each file's path under the destination (e.g.
  /// `photos/2026/a.jpg`), in the same order as [files]; without it each file
  /// lands under its file name. [parentId] is the destination folder (the
  /// library root when omitted); [prefix] is used when [parentId] is empty.
  /// Every key is checked before anything is written; files that fail to
  /// upload are missing from the result.
  ///
  /// Throws [ArgumentError] when [files] is empty or [relativePaths] has a
  /// different length.
  Future<UploadFolderResult> upload(String bucketName, List<UploadFile> files,
      {List<String>? relativePaths, String? parentId, String? prefix}) async {
    if (files.isEmpty) throw ArgumentError.value(files, 'files', 'must not be empty');
    if (relativePaths != null && relativePaths.length != files.length) {
      throw ArgumentError.value(
          relativePaths, 'relativePaths', 'must have one entry per file (${files.length})');
    }
    return decodeOne(
        await _http.requestMultipart('POST', '${_bucket(bucketName)}/upload-folder', fields: [
          for (final p in relativePaths ?? const <String>[]) ('relativePaths', p),
          if (parentId != null) ('parentID', parentId),
          if (prefix != null) ('prefix', prefix),
        ], files: [
          for (final f in files) ('files', f)
        ]),
        UploadFolderResult.fromJson);
  }

  /// Downloads every object under the folder at [path] as a zip archive
  /// (file name `<folder>.zip`).
  Future<FileDownload> downloadZip(String bucketName, String path) async =>
      _http.requestBytes('GET', '${_bucket(bucketName)}/folder-zip/${segs(path)}');

  /// Copies a file or folder next to itself and returns the copy, named
  /// `<name> copy` (then `<name> copy 2`, ...).
  Future<Document> duplicate(String bucketName, DuplicateRequest body) async => decodeOne(
      await _http.request('POST', '${_bucket(bucketName)}/duplicate', body: body),
      Document.fromJson);

  /// Renames (or moves, when `newName` holds a path) a folder.
  Future<Document> rename(String bucketName, RenameRequest body) async => decodeOne(
      await _http.request('PUT', '${_bucket(bucketName)}/folder/rename', body: body),
      Document.fromJson);
}
