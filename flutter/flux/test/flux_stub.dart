import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:lowcoai_flux/lowcoai_flux.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const waitTimeout = Duration(seconds: 5);

/// A FIFO whose [next] waits (with a timeout) for the next item.
class AsyncQueue<T> {
  final _items = Queue<T>();
  final _waiters = Queue<Completer<T>>();

  bool get isEmpty => _items.isEmpty;

  void add(T item) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(item);
    } else {
      _items.add(item);
    }
  }

  Future<T> next([Duration timeout = waitTimeout]) {
    if (_items.isNotEmpty) return Future.value(_items.removeFirst());
    final waiter = Completer<T>();
    _waiters.add(waiter);
    return waiter.future.timeout(timeout, onTimeout: () {
      _waiters.remove(waiter);
      throw TimeoutException('nothing arrived', timeout);
    });
  }
}

/// A frame the stub received, tagged with the index of its socket.
class Frame {
  Frame(this.socket, this.json);

  final int socket;
  final Map<String, dynamic> json;

  Object? get data => json['data'];
}

/// A loopback flux server. It rejects dials that do not announce `replay=1`,
/// reports every subscription frame as `"<sb|usb> <data as JSON>"`, records
/// pings and other frames per socket, and can push frames or drop sockets.
class FluxStub {
  FluxStub._(this._server) {
    _server.listen(_handle);
  }

  static Future<FluxStub> start() async {
    final stub = FluxStub._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    addTearDown(stub.close);
    return stub;
  }

  final HttpServer _server;

  /// URIs the client asked the factory to dial (before rewriting).
  final dials = <Uri>[];

  /// Request URIs as seen by the server.
  final requests = <Uri>[];
  final sockets = <WebSocket>[];

  /// Completes when the client side of socket `i` has gone (its stream ended).
  final socketClosed = <Completer<void>>[];

  /// Index of each accepted socket, in order.
  final connections = AsyncQueue<int>();
  final subscriptionFrames = AsyncQueue<String>();
  final pings = AsyncQueue<Frame>();
  final otherFrames = AsyncQueue<Frame>();

  int get port => _server.port;

  /// A [WebSocketChannelFactory] that sends the client here instead of
  /// `wss://ws.lowco.ai/`, keeping the path and query.
  WebSocketChannel dial(Uri uri) {
    dials.add(uri);
    return WebSocketChannel.connect(uri.replace(scheme: 'ws', host: '127.0.0.1', port: port));
  }

  FluxClient client({
    Duration heartbeatInterval = const Duration(hours: 1),
    Duration reconnectInterval = const Duration(milliseconds: 10),
    Map<String, String>? queryParams,
    String? clientId,
  }) {
    final client = FluxClient(
      token: 'tok_123',
      orgId: 'org-1',
      clientId: clientId,
      heartbeatInterval: heartbeatInterval,
      reconnectInterval: reconnectInterval,
      queryParams: queryParams,
      channelFactory: dial,
    );
    addTearDown(client.disconnect);
    return client;
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    if (request.uri.queryParameters['replay'] != '1' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final index = sockets.length;
    sockets.add(socket);
    socketClosed.add(Completer<void>());
    connections.add(index);
    socket.listen(
      (raw) {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        final frame = Frame(index, json);
        if (json['channel'] == 'flux:subscription') {
          subscriptionFrames.add('${json['event']} ${jsonEncode(json['data'])}');
        } else if (json['channel'] == 'flux:health_check' && json['event'] == 'pi') {
          pings.add(frame);
        } else {
          otherFrames.add(frame);
        }
      },
      onError: (Object _) {},
      onDone: () => socketClosed[index].complete(),
    );
  }

  /// Waits until the server accepted the next socket and [client] saw it
  /// open; returns the socket's index.
  Future<int> opened(FluxClient client) async {
    final index = await connections.next();
    await until(() => client.isConnected);
    return index;
  }

  /// Sends [message] (JSON-encoded unless it is a String) on the latest socket.
  void send(Object? message) => sockets.last.add(message is String ? message : jsonEncode(message));

  /// Closes a socket from the server side (the latest one by default).
  void drop([int? index]) => unawaited(sockets[index ?? sockets.length - 1].close());

  /// Awaits the next subscription frames and checks them in order.
  Future<void> expectFrames(List<String> want) async {
    for (final w in want) {
      expect(await subscriptionFrames.next(), w);
    }
  }

  Future<void> close() async {
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await _server.close(force: true);
  }
}

/// Polls [condition] until it holds, failing after [timeout].
Future<void> until(bool Function() condition, {Duration timeout = waitTimeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
