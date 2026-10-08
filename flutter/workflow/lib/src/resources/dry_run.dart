import '../models.dart';
import '../transport.dart';

/// `/v1/wf/dryrun` — evaluate expressions against an execution's data.
class DryRunResource {
  DryRunResource(this._http);

  final WorkflowHttpClient _http;

  /// Returns the evaluated value (any JSON value).
  Future<Object?> execute(DryRunRequest payload) =>
      _http.request('POST', '/v1/wf/dryrun', body: payload);
}
