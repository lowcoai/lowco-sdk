import '../codec.dart';
import '../models.dart';
import '../transfer.dart';
import '../transport.dart';

/// `/v1/documents/nodes`, `/v1/documents/d` — node metadata and stable
/// permalinks by node id.
class NodesResource {
  /// Creates the resource on top of [_http].
  NodesResource(this._http);

  final DocsHttpClient _http;

  /// The stored metadata of node [nodeId] plus the caller's role on it.
  Future<NodeView> get(String nodeId) async => decodeOne(
      await _http.request('GET', '$docsBasePath/nodes/${seg(nodeId)}'), NodeView.fromJson);

  /// Resolves the permalink `/v1/documents/d/{nodeId}` without following the
  /// redirect.
  ///
  /// Returns [NodeFileResult.url] (a fresh short-lived URL; [download] `true`
  /// makes it force a download under the file's name), or the bytes in
  /// [NodeFileResult.content] for a file restored from cold storage, or
  /// [NodeFileResult.restoring] while its restore runs. On the web the
  /// browser follows the redirect itself, so you get the content instead of
  /// the URL (when the file host allows the cross-origin read).
  ///
  /// The service treats any `download` value as true, so `false` omits the
  /// parameter and `true` sends `download=1`.
  Future<NodeFileResult> resolve(String nodeId, {bool download = false}) async =>
      _http.requestNodeFile('GET', '$docsBasePath/d/${seg(nodeId)}',
          query: {'download': download ? '1' : null});

  /// Streams the bytes of node [nodeId] (for callers that cannot follow a
  /// redirect): [NodeFileResult.content] with the stored content type and
  /// file name, or [NodeFileResult.restoring] while a restore from cold
  /// storage runs.
  Future<NodeFileResult> content(String nodeId) async =>
      _http.requestNodeFile('GET', '$docsBasePath/d/${seg(nodeId)}/content');
}
