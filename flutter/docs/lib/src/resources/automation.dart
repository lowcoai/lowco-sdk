import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents/{bucketName}/folder-configs` and `/processing-jobs` —
/// automation rules that run a pipeline when files land in a folder, and
/// their run history.
class AutomationResource {
  /// Creates the resource on top of [_http].
  AutomationResource(this._http);

  final DocsHttpClient _http;

  String _configs(String bucketName) => '$docsBasePath/${seg(bucketName)}/folder-configs';

  /// The bucket's rules visible to the caller, optionally only those on the
  /// folder [prefix].
  Future<List<FolderConfig>> list(String bucketName, {String? prefix}) async => decodeMany(
      await _http.request('GET', _configs(bucketName), query: {'prefix': prefix}),
      FolderConfig.fromJson);

  /// Creates a rule.
  Future<FolderConfig> create(String bucketName, FolderConfigRequest body) async => decodeOne(
      await _http.request('POST', _configs(bucketName), body: body), FolderConfig.fromJson);

  /// The rule [id].
  Future<FolderConfig> get(String bucketName, String id) async => decodeOne(
      await _http.request('GET', '${_configs(bucketName)}/${seg(id)}'), FolderConfig.fromJson);

  /// Replaces rule [id].
  Future<FolderConfig> update(String bucketName, String id, FolderConfigRequest body) async =>
      decodeOne(await _http.request('PUT', '${_configs(bucketName)}/${seg(id)}', body: body),
          FolderConfig.fromJson);

  /// Deletes rule [id] and returns the confirmation message.
  Future<String> delete(String bucketName, String id) async =>
      decodeMessage(await _http.request('DELETE', '${_configs(bucketName)}/${seg(id)}'));

  /// Recent rule runs, newest first, optionally only those of rule
  /// [configId]; [limit] is 1-200 (server default 50).
  Future<List<ProcessingJob>> jobs(String bucketName, {String? configId, int? limit}) async =>
      decodeMany(
          await _http.request('GET', '$docsBasePath/${seg(bucketName)}/processing-jobs',
              query: {'configId': configId, 'limit': limit}),
          ProcessingJob.fromJson);
}
