import 'package:http/http.dart' as http;

import 'resources/activities.dart';
import 'resources/analytics.dart';
import 'resources/dry_run.dart';
import 'resources/environments.dart';
import 'resources/executions.dart';
import 'resources/functions.dart';
import 'resources/human_tasks.dart';
import 'resources/webhooks.dart';
import 'resources/workflows.dart';
import 'transport.dart';

/// Client for the lowco workflow-orchestrator (routes under `/v1/wf/*`).
///
/// Every request goes to `https://api.lowco.ai` with
/// `Authorization: Bearer <token>` and, when [orgId] is set, `X-Org-Id`.
/// Responses are unwrapped from the `{ success, data, ... }` envelope and
/// failures throw `WorkflowException`. Call [close] when done.
class WorkflowClient {
  /// Creates a client.
  ///
  /// * [token] — user token or API key. Required; [ArgumentError] if blank.
  ///   Not sent when [headers] already contain `Authorization`.
  /// * [orgId] — `X-Org-Id` header value (unless [headers] already set it).
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it. A
  ///   timed-out request is aborted and throws `WorkflowException` with
  ///   status `0`.
  /// * [headers] — extra headers added to every request.
  /// * [httpClient] — custom `http.Client` (e.g. a platform client in
  ///   Flutter, or `MockClient` in tests). It is not closed by [close].
  WorkflowClient({
    required String token,
    String? orgId,
    Duration? timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  }) : this._(WorkflowHttpClient(
          token: token,
          orgId: orgId,
          timeout: timeout,
          headers: headers,
          httpClient: httpClient,
        ));

  WorkflowClient._(WorkflowHttpClient transport)
      : _transport = transport,
        workflows = WorkflowsResource(transport),
        environments = EnvironmentsResource(transport),
        functions = FunctionsResource(transport),
        executions = ExecutionsResource(transport),
        activities = ActivitiesResource(transport),
        humanTasks = HumanTasksResource(transport),
        analytics = AnalyticsResource(transport),
        dryRun = DryRunResource(transport),
        webhooks = WebhooksResource(transport);

  final WorkflowHttpClient _transport;

  final WorkflowsResource workflows;
  final EnvironmentsResource environments;
  final FunctionsResource functions;
  final ExecutionsResource executions;
  final ActivitiesResource activities;
  final HumanTasksResource humanTasks;
  final AnalyticsResource analytics;
  final DryRunResource dryRun;
  final WebhooksResource webhooks;

  /// Closes the underlying HTTP client if this instance created it.
  void close() => _transport.close();
}
