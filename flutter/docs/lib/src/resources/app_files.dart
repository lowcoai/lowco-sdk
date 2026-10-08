import '../codec.dart';
import '../models.dart';
import '../transfer.dart';
import '../transport.dart';

/// `/v1/documents/app-files/{appKey}` — app data stored under
/// `.apps/{appKey}/` in the org's bucket (the bucket comes from the org id,
/// never from the caller).
class AppFilesResource {
  /// Creates the resource on top of [_http].
  AppFilesResource(this._http);

  final DocsHttpClient _http;

  String _app(String appKey) => '$docsBasePath/app-files/${seg(appKey)}';

  /// Uploads [file] (multipart field `file`) into the folder [path] of the
  /// app area (e.g. `2026/invoices`; the area's root when omitted).
  ///
  /// [onConflict] is `replace` (the default: overwrite) or `rename` (keep
  /// both). Store the returned `permalink` rather than a storage URL: it
  /// survives renames.
  Future<AppFileUpload> upload(String appKey, UploadFile file,
          {String? path, String? onConflict}) async =>
      decodeOne(
          await _http.requestMultipart('POST', _app(appKey), fields: [
            if (path != null) ('path', path),
            if (onConflict != null) ('onConflict', onConflict),
          ], files: [
            ('file', file)
          ]),
          AppFileUpload.fromJson);

  /// The app area's files, optionally only the folder [prefix] inside it.
  Future<List<Document>> list(String appKey, {String? prefix}) async => decodeMany(
      await _http.request('GET', '${_app(appKey)}/objects', query: {'prefix': prefix}),
      Document.fromJson);

  /// Deletes the file at [path] inside the app area and returns the
  /// confirmation message.
  Future<String> delete(String appKey, String path) async =>
      decodeMessage(await _http.request('DELETE', '${_app(appKey)}/${segs(path)}'));

  /// Archives the app's files past their retention window.
  Future<AppFilesSweep> sweep(String appKey, SweepRequest body) async => decodeOne(
      await _http.request('POST', '${_app(appKey)}/sweep', body: body), AppFilesSweep.fromJson);
}
