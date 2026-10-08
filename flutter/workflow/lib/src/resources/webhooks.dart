import '../codec.dart';
import '../transport.dart';

/// `/v1/wf/webhook` — trigger workflows over HTTP.
///
/// Only the trigger is ported. The workflow orchestrator no longer serves the
/// webhook list / register / update / delete routes (webhook registration
/// lives in the integrations service), and `POST /v1/wf/webhook/{id}` is the
/// trigger, so the TS SDK's `create` would run the workflow instead.
class WebhooksResource {
  WebhooksResource(this._http);

  final WorkflowHttpClient _http;

  static const _path = '/v1/wf/webhook';

  /// Triggers the workflow with [payload] (defaults to `{}`). [env] picks the
  /// environment, [triggeredBy] labels the run and [async] (`?async=true`)
  /// returns without waiting for the run to finish.
  Future<Map<String, dynamic>> trigger(
    String workflowId, {
    Map<String, dynamic>? payload,
    String? env,
    String? triggeredBy,
    bool? async,
  }) async =>
      decodeMap(await _http.request('POST', '$_path/${seg(workflowId)}',
          body: payload ?? const <String, dynamic>{},
          query: {'env': env, 'triggeredBy': triggeredBy, 'async': async}));
}
