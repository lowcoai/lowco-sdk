import '../codec.dart';
import '../models.dart';
import '../transfer.dart';
import '../transport.dart';

/// `/v1/documents/{bucketName}/...` — read, save, upload, rename, delete,
/// download and preview files.
///
/// Methods taking a `path` in the URL keep its `/` separators, so nested keys
/// (`folder/file.md`) work everywhere.
class FilesResource {
  /// Creates the resource on top of [_http].
  FilesResource(this._http);

  final DocsHttpClient _http;

  String _bucket(String bucketName) => '$docsBasePath/${seg(bucketName)}';

  /// The file at [path] as a [Document] with its URLs and its body as text in
  /// `content`; records a view. Use [read] for conditional saves.
  Future<Document> get(String bucketName, String path) async => decodeOne(
      await _http.request('GET', '${_bucket(bucketName)}/file/${segs(path)}'), Document.fromJson);

  /// Reads the file at [path] (`GET /file?path=`): the body with the etag of
  /// exactly that version (send it back as `UpdateFileRequest.ifMatch`), the
  /// caller's role, the space owner and the real node id. [meta] `true`
  /// skips the body.
  Future<FileContent> read(String bucketName, String path, {bool? meta}) async => decodeOne(
      await _http.request('GET', '${_bucket(bucketName)}/file',
          query: {'path': path, 'meta': meta == true ? '1' : null}),
      FileContent.fromJson);

  /// Creates an empty file.
  Future<Document> createBlank(String bucketName, CreateBlankFileRequest body) async => decodeOne(
      await _http.request('POST', '${_bucket(bucketName)}/file', body: body), Document.fromJson);

  /// Saves a text file's whole body (creating it when missing). With `ifMatch` / `ifNoneMatch` the save
  /// is conditional and fails with a `412` `DocsException` whose
  /// `precondition` holds the file's current state.
  Future<Document> update(String bucketName, UpdateFileRequest body) async => decodeOne(
      await _http.request('PUT', '${_bucket(bucketName)}/file', body: body), Document.fromJson);

  /// Same as [update] (`PUT /file/{path}`): the target still comes from the
  /// body's `parentName` / `fileName`, the service ignores [path].
  Future<Document> updateAt(String bucketName, String path, UpdateFileRequest body) async =>
      decodeOne(await _http.request('PUT', '${_bucket(bucketName)}/file/${segs(path)}', body: body),
          Document.fromJson);

  /// Renames (or moves, when `newName` holds a path) a file.
  Future<Document> rename(String bucketName, RenameRequest body) async => decodeOne(
      await _http.request('PUT', '${_bucket(bucketName)}/file/rename', body: body),
      Document.fromJson);

  /// Deletes the file at [path] (`DELETE /file/{path}`) and returns the
  /// confirmation message. Library and personal files move to the trash;
  /// `.apps/` and system files are deleted permanently.
  Future<String> delete(String bucketName, String path) async =>
      decodeMessage(await _http.request('DELETE', '${_bucket(bucketName)}/file/${segs(path)}'));

  /// Deletes the file at [path] (`DELETE /file?path=`) and returns the
  /// confirmation message.
  Future<String> deleteByPath(String bucketName, String path) async => decodeMessage(
      await _http.request('DELETE', '${_bucket(bucketName)}/file', query: {'path': path}));

  /// Uploads one [file] (multipart field `file`) into the folder [parentId]
  /// (sent as the `ParentID` field; the library root when omitted).
  ///
  /// [onConflict] is `replace` (the default: overwrite) or `rename` (keep
  /// both, uploading as `name(1).ext`, ...).
  Future<Document> upload(String bucketName, UploadFile file,
          {String? parentId, String? onConflict}) async =>
      decodeOne(
          await _http.requestMultipart('POST', '${_bucket(bucketName)}/upload-file', fields: [
            if (parentId != null) ('ParentID', parentId),
            if (onConflict != null) ('onConflict', onConflict),
          ], files: [
            ('file', file)
          ]),
          Document.fromJson);

  /// Returns a short-lived URL that downloads the file at [path] under its
  /// real name (the `Location` of the `307`; the redirect is not followed).
  ///
  /// Needs an HTTP client that can disable redirects, so it throws a
  /// `DocsException` on the web.
  Future<String> downloadUrl(String bucketName, String path) async =>
      _http.requestRedirect('GET', '${_bucket(bucketName)}/download/${segs(path)}');

  /// Returns the URL of a PDF rendition of the file at [path] (PDFs and
  /// office documents; the `Location` of the `307`, not followed).
  ///
  /// Needs an HTTP client that can disable redirects, so it throws a
  /// `DocsException` on the web.
  Future<String> previewUrl(String bucketName, String path) async =>
      _http.requestRedirect('GET', '${_bucket(bucketName)}/preview/${segs(path)}');

  /// Lists the entries of the zip file at [path].
  Future<ArchiveListing> listArchive(String bucketName, String path) async => decodeOne(
      await _http.request('GET', '${_bucket(bucketName)}/archive/${segs(path)}'),
      ArchiveListing.fromJson);
}
