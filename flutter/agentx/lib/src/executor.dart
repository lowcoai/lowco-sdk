import 'dart:async';
import 'dart:convert';

import 'a2a.dart';
import 'constants.dart';
import 'errors.dart';
import 'json.dart';
import 'sse.dart';
import 'transport.dart';

/// A single SSE event delivered by [ExecutorClient.streamMessage].
///
/// [data] is the raw payload of the event, typically an [A2AMessage] as JSON
/// but possibly a tool/status frame. Call [tryParseMessage] for a
/// message-typed view.
class StreamEvent {
  const StreamEvent(this.data);

  final String data;

  @override
  String toString() => 'StreamEvent($data)';
}

/// Decodes [ev] as an [A2AMessage]; `null` when its data is not a JSON
/// object. Like the TypeScript SDK it does not check `kind`, so inspect
/// `A2AMessage.kind` if non-message frames may arrive.
A2AMessage? tryParseMessage(StreamEvent ev) {
  final Object? parsed;
  try {
    parsed = jsonDecode(ev.data);
  } on FormatException {
    return null;
  }
  return parsed is Map ? A2AMessage.fromJson(readMap(parsed)!) : null;
}

/// The agent-executor service routes (A2A JSON-RPC over HTTP, plus SSE).
///
/// Obtain it from `AgentxClient.executor`; the constructor is internal.
class ExecutorClient {
  ExecutorClient(this._t, String apiBasePath) : _base = trimSlashes(apiBasePath);

  final Transport _t;
  final String _base;

  String _path(List<String> parts) => _t.joinPath(_base, parts);

  JSONRPCRequest _rpc(String agentId, MessageSendParams params) =>
      JSONRPCRequest(method: methodMessageSend, params: params, id: agentId);

  // --- Health --------------------------------------------------------------

  /// `GET /health` at the host root.
  Future<void> health() => _t.requestVoid('GET', '/health');

  // --- Synchronous send ----------------------------------------------------

  /// Performs a synchronous `message/send` call. The JSON-RPC id doubles as
  /// the target agent identifier (the service convention).
  ///
  /// The response is returned as-is (it is not enveloped); JSON-RPC errors are
  /// in [JSONRPCResponse.error], only HTTP errors throw [AgentxException]. An
  /// empty (e.g. 204) reply yields `JSONRPCResponse(jsonrpc: '2.0', id: agentId)`.
  Future<JSONRPCResponse> sendMessage(String agentId, MessageSendParams params) async {
    final data =
        await _t.request('POST', _path(['execute']), body: _rpc(agentId, params), enveloped: false);
    return data is Map
        ? JSONRPCResponse.fromJson(readMap(data)!)
        : JSONRPCResponse(jsonrpc: '2.0', id: agentId);
  }

  // --- Streaming send ------------------------------------------------------

  /// Streams a `message/send` call, emitting one [StreamEvent] per SSE event
  /// the server sends.
  ///
  /// The request is sent when the stream is listened to and has no timeout.
  /// A non-2xx reply is delivered as an [AgentxException] stream error.
  /// Cancelling the subscription (e.g. `break` in an `await for`) aborts the
  /// HTTP request.
  ///
  /// ```dart
  /// await for (final ev in client.executor.streamMessage(agentId, params)) {
  ///   final msg = tryParseMessage(ev);
  ///   print(msg != null ? 'message: ${msg.parts}' : 'raw: ${ev.data}');
  /// }
  /// ```
  Stream<StreamEvent> streamMessage(String agentId, MessageSendParams params) {
    final abort = Completer<void>();
    final events = _stream(_rpc(agentId, params), abort);

    // An async* body only observes a cancel at its next `yield`, which may be
    // a long way off while the agent is silent. Completing the abort trigger
    // as soon as the listener cancels closes the connection right away (which
    // in turn ends the generator).
    StreamSubscription<StreamEvent>? sub;
    late final StreamController<StreamEvent> controller;
    controller = StreamController<StreamEvent>(
      sync: true,
      onListen: () {
        sub = events.listen(controller.add, onError: controller.addError, onDone: controller.close);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        if (!abort.isCompleted) abort.complete();
        final s = sub;
        sub = null;
        // The aborted generator may finish with a RequestAbortedException,
        // which nobody is listening for any more.
        s?.cancel().ignore();
      },
    );
    return controller.stream;
  }

  Stream<StreamEvent> _stream(JSONRPCRequest req, Completer<void> abort) async* {
    try {
      final resp = await _t.openStream('POST', _path(['execute']),
          body: req, accept: 'text/event-stream', abortTrigger: abort.future);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = utf8.decode(await resp.stream.toBytes(), allowMalformed: true);
        throw buildHttpException(resp.statusCode, text);
      }
      final parser = SseParser();
      await for (final chunk in resp.stream.transform(const Utf8Decoder(allowMalformed: true))) {
        for (final data in parser.add(chunk)) {
          yield StreamEvent(data);
        }
      }
      final trailing = parser.close();
      if (trailing != null) yield StreamEvent(trailing);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }
}
