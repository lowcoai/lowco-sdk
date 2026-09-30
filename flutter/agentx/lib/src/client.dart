import 'package:http/http.dart' as http;

import 'constants.dart';
import 'executor.dart';
import 'kb.dart';
import 'manager.dart';
import 'transport.dart';

/// Unified agentx client.
///
/// Wraps three sub-clients — [manager], [kb] and [executor] — that share one
/// HTTP transport and one set of default headers. All requests go to
/// `https://api.lowco.ai`.
///
/// [token] (a user token or API key) is required and sent as
/// `Authorization: Bearer <token>` on every request. Call [close] when done
/// to release the underlying HTTP client (unless you passed your own).
class AgentxClient {
  /// Creates a client.
  ///
  /// * [orgId] — `X-Org-Id` header value.
  /// * [managerApiBasePath] — agent-manager route prefix, default
  ///   `/v1/agentx/manager`.
  /// * [kbApiBasePath] — agent-kb route prefix, default `/v1/agentx/kb`.
  /// * [executorApiBasePath] — agent-executor route prefix, default
  ///   `/v1/agentx/executors`.
  /// * [defaultHeaders] — extra headers added to every request.
  /// * [timeout] — per-request timeout for non-streaming calls (default
  ///   30 s); `null` disables it. `executor.streamMessage` never times out;
  ///   cancel its subscription instead.
  /// * [httpClient] — custom `http.Client` (e.g. a `MockClient` in tests or a
  ///   platform client in Flutter). It is not closed by [close].
  factory AgentxClient({
    required String token,
    String? orgId,
    String? managerApiBasePath,
    String? kbApiBasePath,
    String? executorApiBasePath,
    Map<String, String>? defaultHeaders,
    Duration? timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'AgentxClient: token is required');
    }
    final headers = <String, String>{
      ...?defaultHeaders,
      'Authorization': 'Bearer $token',
      if (orgId != null && orgId.isNotEmpty) headerOrgId: orgId,
    };
    final transport = Transport(
      httpClient: httpClient ?? http.Client(),
      ownsHttp: httpClient == null,
      headers: headers,
      timeout: timeout,
    );
    return AgentxClient._(
      transport,
      ManagerClient(transport, managerApiBasePath ?? defaultManagerApiBasePath),
      KBClient(transport, kbApiBasePath ?? defaultKbApiBasePath),
      ExecutorClient(transport, executorApiBasePath ?? defaultExecutorApiBasePath),
    );
  }

  AgentxClient._(this._transport, this.manager, this.kb, this.executor);

  final Transport _transport;

  /// Agent-manager sub-client (agents, published agents, models,
  /// conversations).
  final ManagerClient manager;

  /// Agent-kb sub-client (knowledge bases, datasets, embeddings).
  final KBClient kb;

  /// Agent-executor sub-client (A2A `message/send`, sync and streaming).
  final ExecutorClient executor;

  /// Sets the `X-Org-Id` header for later requests of every sub-client;
  /// `null` (or an empty string) removes it.
  void setOrgId(String? orgId) {
    if (orgId != null && orgId.isNotEmpty) {
      _transport.headers[headerOrgId] = orgId;
    } else {
      _transport.headers.remove(headerOrgId);
    }
  }

  /// Sets / overwrites an arbitrary default header. Pass `null` to delete.
  void setHeader(String key, String? value) {
    if (value == null) {
      _transport.headers.remove(key);
    } else {
      _transport.headers[key] = value;
    }
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() => _transport.close();
}
