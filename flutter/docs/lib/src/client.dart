import 'package:http/http.dart' as http;

import 'codec.dart';
import 'models.dart';
import 'resources/app_files.dart';
import 'resources/automation.dart';
import 'resources/buckets.dart';
import 'resources/files.dart';
import 'resources/folders.dart';
import 'resources/library.dart';
import 'resources/nodes.dart';
import 'resources/sharing.dart';
import 'resources/triggers.dart';
import 'resources/webhooks.dart';
import 'transport.dart';

/// Client for the lowco document service (routes under `/v1/documents`).
///
/// Every request goes to `https://api.lowco.ai` with
/// `Authorization: Bearer <token>` and `X-Org-Id: <orgId>`. JSON responses
/// are unwrapped from the `{ status, data }` envelope and failures throw
/// `DocsException`. Call [close] when done.
class DocsClient {
  /// Creates a client.
  ///
  /// * [token] — user token or API key. Required; [ArgumentError] if blank.
  ///   Not sent when [headers] already contain `Authorization`.
  /// * [orgId] — organization id, sent as `X-Org-Id` (unless [headers]
  ///   already set it). Required; [ArgumentError] if blank.
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it. A
  ///   timed-out request is aborted and throws `DocsException` with status
  ///   `0`.
  /// * [headers] — extra headers added to every request.
  /// * [httpClient] — custom `http.Client` (e.g. a platform client in
  ///   Flutter, or `MockClient` in tests). It is not closed by [close].
  DocsClient({
    required String token,
    required String orgId,
    Duration? timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  }) : this._(DocsHttpClient(
          token: token,
          orgId: orgId,
          timeout: timeout,
          headers: headers,
          httpClient: httpClient,
        ));

  DocsClient._(DocsHttpClient transport)
      : _transport = transport,
        buckets = BucketsResource(transport),
        folders = FoldersResource(transport),
        files = FilesResource(transport),
        nodes = NodesResource(transport),
        library = LibraryResource(transport),
        sharing = SharingResource(transport),
        automation = AutomationResource(transport),
        appFiles = AppFilesResource(transport),
        triggers = TriggersResource(transport),
        webhooks = WebhooksResource(transport);

  final DocsHttpClient _transport;

  /// The org's bucket and its storage usage.
  final BucketsResource buckets;

  /// Folder listing, creation, upload, zip download, copy, rename, delete.
  final FoldersResource folders;

  /// File read, save, upload, rename, delete, download and preview URLs.
  final FilesResource files;

  /// Node metadata and permalinks by node id.
  final NodesResource nodes;

  /// The caller's starred, recent and trashed items.
  final LibraryResource library;

  /// Shares, share links and items shared with the caller.
  final SharingResource sharing;

  /// Folder automation rules and their runs.
  final AutomationResource automation;

  /// App data under `.apps/{appKey}/`.
  final AppFilesResource appFiles;

  /// Workflow triggers on object events.
  final TriggersResource triggers;

  /// Webhooks on object events.
  final WebhooksResource webhooks;

  /// Liveness probe (`GET /health`, outside `/v1/documents`); returns the
  /// plain-text body (`Working!`).
  Future<String> health() async => _transport.requestText('GET', '/health');

  /// Finds files and folders in [bucketName] whose name matches [q], then
  /// documents whose extracted text matches (marked
  /// `metadata['matchedBy'] == 'content'`), limited to what the caller can
  /// read.
  Future<List<Document>> search(String bucketName, String q) async => decodeMany(
      await _transport.request('GET', '$docsBasePath/${seg(bucketName)}/search', query: {'q': q}),
      Document.fromJson);

  /// Closes the underlying HTTP client if this instance created it.
  void close() => _transport.close();
}
