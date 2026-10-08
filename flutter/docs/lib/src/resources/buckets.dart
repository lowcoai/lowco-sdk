import '../codec.dart';
import '../models.dart';
import '../transport.dart';

/// `/v1/documents` — the org's bucket and its storage usage.
class BucketsResource {
  /// Creates the resource on top of [_http].
  BucketsResource(this._http);

  final DocsHttpClient _http;

  /// Returns the org's single bucket (created on first use) as a folder
  /// [Document] with its total size; `metadata['privateNotes']` tells whether
  /// new notes default to the private area. Its `name` is the `bucketName`
  /// every other bucket-scoped method takes.
  Future<Document> get() async =>
      decodeOne(await _http.request('GET', docsBasePath), Document.fromJson);

  /// Storage usage of [bucketName], split between visible and hidden system
  /// content.
  Future<BucketStats> stats(String bucketName) async => decodeOne(
      await _http.request('GET', '$docsBasePath/${seg(bucketName)}/stats'), BucketStats.fromJson);
}
