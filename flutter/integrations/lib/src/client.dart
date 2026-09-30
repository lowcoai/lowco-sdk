import 'package:http/http.dart' as http;

import 'resources/actions.dart';
import 'resources/applications.dart';
import 'resources/configurations.dart';
import 'resources/connections.dart';
import 'resources/mcp.dart';
import 'resources/oauth.dart';
import 'resources/triggers.dart';
import 'transport.dart';

/// Client for the lowco integrations-manager (routes under
/// `/v1/integrations/*`).
///
/// Every request goes to `https://api.lowco.ai` with
/// `Authorization: Bearer <token>` and, when [orgId] is set, `X-Org-Id`.
/// Responses are unwrapped from the `{ success, data, ... }` envelope and
/// failures throw `IntegrationsException`. Call [close] when done.
class IntegrationsClient {
  /// Creates a client.
  ///
  /// * [token] — user token or API key. Required; [ArgumentError] if blank.
  ///   Not sent when [headers] already contain `Authorization`.
  /// * [orgId] — `X-Org-Id` header value (unless [headers] already set it).
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it. A
  ///   timed-out request is aborted and throws `IntegrationsException` with
  ///   status `0`.
  /// * [headers] — extra headers added to every request.
  /// * [httpClient] — custom `http.Client` (e.g. a platform client in
  ///   Flutter, or `MockClient` in tests). It is not closed by [close].
  IntegrationsClient({
    required String token,
    String? orgId,
    Duration? timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? httpClient,
  }) : this._(IntegrationsHttpClient(
          token: token,
          orgId: orgId,
          timeout: timeout,
          headers: headers,
          httpClient: httpClient,
        ));

  IntegrationsClient._(IntegrationsHttpClient transport)
      : _transport = transport,
        applications = ApplicationsResource(transport),
        actions = ActionsResource(transport),
        connections = ConnectionsResource(transport),
        triggers = TriggersResource(transport),
        oauth = OAuthResource(transport),
        configurations = ConfigurationsResource(transport),
        mcp = McpResource(transport);

  final IntegrationsHttpClient _transport;

  final ApplicationsResource applications;
  final ActionsResource actions;
  final ConnectionsResource connections;
  final TriggersResource triggers;
  final OAuthResource oauth;
  final ConfigurationsResource configurations;
  final McpResource mcp;

  /// Closes the underlying HTTP client if this instance created it.
  void close() => _transport.close();
}
