import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_engage/lowcoai_engage.dart';
import 'package:lowcoai_engage/src/device_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Records every request and answers with [respond].
class Recorder {
  Recorder([http.Response Function(http.Request)? respond])
      : _respond = respond ?? ((_) => http.Response('', 202));

  final http.Response Function(http.Request) _respond;
  final requests = <http.Request>[];

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    return _respond(request);
  });

  List<Map<String, dynamic>> get events =>
      [for (final r in requests) jsonDecode(r.body) as Map<String, dynamic>];

  Map<String, dynamic> get last => events.last;
}

/// A controllable clock.
class Clock {
  Clock(this.current);

  DateTime current;

  DateTime call() => current;

  void advance(Duration by) => current = current.add(by);
}

class ThrowingStorage implements EngageStorage {
  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> setString(String key, String value) async => throw StateError('disk full');

  @override
  Future<void> remove(String key) async {}
}

const config = EngageConfig(apiKey: 'key_secret', orgId: 'org_1');

void main() {
  late Clock clock;
  late Recorder rec;
  late InMemoryEngageStorage storage;

  LowcoAnalytics analytics() => LowcoAnalytics.instance;

  Future<void> init({
    EngageConfig cfg = config,
    EngageStorage? store,
    http.Client? client,
  }) {
    LowcoAnalytics.instance.now = clock.call;
    return LowcoAnalytics.instance
        .init(cfg, storage: store ?? storage, httpClient: client ?? rec.client);
  }

  setUp(() {
    LowcoAnalytics.debugReset();
    clock = Clock(DateTime.utc(2026, 9, 30, 12, 0, 0, 123));
    rec = Recorder();
    storage = InMemoryEngageStorage();
  });

  group('delivery', () {
    test('posts one event with the browser SDK payload and headers', () async {
      await init();
      await analytics().track('signup_completed', {'plan': 'pro', 'seats': 3});

      expect(rec.requests, hasLength(1));
      final req = rec.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://api.lowco.ai/v1/engage/track');
      expect(req.headers['Authorization'], 'Bearer key_secret');
      expect(req.headers['X-Org-Id'], 'org_1');
      expect(req.headers['Content-Type'], 'application/json');

      final body = rec.last;
      expect(body.keys, [
        'id',
        'event_name',
        'event_data',
        'user_id',
        'device_id',
        'session_id',
        'device_info',
        'location',
        'event_time',
      ]);
      expect(body['id'], '');
      expect(body['event_name'], 'signup_completed');
      expect(body['event_data'], {'plan': 'pro', 'seats': 3});
      expect(body['user_id'], isNull);
      expect(body['device_id'], matches(_uuidPattern));
      expect(body['session_id'], matches(_uuidPattern));
      expect(body['location'], isNull);
      expect(body['event_time'], '2026-09-30T12:00:00.123Z');

      final deviceInfo = body['device_info'] as Map<String, dynamic>;
      expect(deviceInfo['engine'], {'name': 'Flutter'});
      expect((deviceInfo['os'] as Map)['name'], isA<String>());
      expect((deviceInfo['device'] as Map)['type'], isIn(['mobile', 'tablet', 'desktop', 'web']));
      if (kIsWeb) {
        expect((deviceInfo['device'] as Map)['type'], 'web');
        expect(deviceInfo['ua'], contains('Mozilla/'));
        expect(deviceInfo['browser'], isA<Map<String, dynamic>>());
      } else {
        expect(deviceInfo['ua'], startsWith('Flutter ('));
      }
    });

    test('event_time is UTC with millisecond precision', () async {
      clock.current = DateTime.fromMicrosecondsSinceEpoch(1790000000123456);
      await init();
      await analytics().track('x');
      expect(rec.last['event_time'], '2026-09-21T14:13:20.123Z');
    });

    test('page() sends page_view and metadata values are JSON-encoded', () async {
      await init();
      await analytics().page({'path': '/home', 'at': DateTime.utc(2026, 1, 2, 3, 4, 5)});
      expect(rec.last['event_name'], 'page_view');
      expect(rec.last['event_data'], {'path': '/home', 'at': '2026-01-02T03:04:05.000Z'});
    });

    test('setLocation and setDeviceInfo are sent with later events', () async {
      await init();
      analytics()
        ..setLocation(
            const LocationInfo(latitude: 12.5, longitude: 77.25, accuracy: 10, altitudeAccuracy: 3))
        ..setDeviceInfo(const DeviceInfo(
          os: OsInfo(name: 'Android', version: '14'),
          device: DeviceDetails(type: 'mobile', vendor: 'Google', model: 'Pixel 8'),
          engine: EngineInfo(name: 'Flutter'),
          ua: 'Flutter (Android 14)',
        ));
      await analytics().track('x');
      // The engage ingest model reads snake_case `altitude_accuracy`.
      expect(rec.last['location'], {
        'latitude': 12.5,
        'longitude': 77.25,
        'accuracy': 10.0,
        'altitude_accuracy': 3.0,
      });
      expect(rec.last['device_info'], {
        'os': {'name': 'Android', 'version': '14'},
        'device': {'type': 'mobile', 'vendor': 'Google', 'model': 'Pixel 8'},
        'engine': {'name': 'Flutter'},
        'ua': 'Flutter (Android 14)',
      });

      analytics().setLocation(null);
      await analytics().track('y');
      expect(rec.last['location'], isNull);
    });

    test('calls before init are dropped', () async {
      await analytics().track('early');
      await analytics().page();
      await analytics().identifyUser('u1');
      expect(rec.requests, isEmpty);
      expect(analytics().isInitialized, isFalse);
      expect(analytics().userId, isNull);
    });

    test('init validates the config and never exposes the api key', () async {
      expect(
        () => analytics().init(const EngageConfig(apiKey: ' ', orgId: 'o')),
        throwsArgumentError,
      );
      expect(
        () => analytics().init(const EngageConfig(apiKey: 'k', orgId: '')),
        throwsArgumentError,
      );
      expect(config.toString(), isNot(contains('key_secret')));
    });
  });

  group('errors', () {
    test('non-2xx answers go to onError, never to the caller', () async {
      final errors = <Object>[];
      rec = Recorder((_) => http.Response(
          jsonEncode({
            'error': {'message': 'bad key'}
          }),
          401));
      await init(cfg: EngageConfig(apiKey: 'k', orgId: 'o', onError: errors.add));
      await analytics().track('x');

      expect(errors.single, isA<EngageException>());
      final error = errors.single as EngageException;
      expect(error.statusCode, 401);
      expect(error.message, 'bad key');
    });

    test('network failures go to onError', () async {
      final errors = <Object>[];
      final client = MockClient((_) async => throw http.ClientException('offline'));
      await init(cfg: EngageConfig(apiKey: 'k', orgId: 'o', onError: errors.add), client: client);
      await expectLater(analytics().track('x'), completes);
      expect(errors.single, isA<http.ClientException>());
    });

    test('storage failures go to onError and tracking continues', () async {
      final errors = <Object>[];
      await init(
        cfg: EngageConfig(apiKey: 'k', orgId: 'o', onError: errors.add),
        store: ThrowingStorage(),
      );
      await analytics().track('x');
      expect(rec.requests, hasLength(1));
      expect(errors, isNotEmpty);
      expect(errors.first, isA<StateError>());
    });

    test('a throwing onError handler is contained', () async {
      rec = Recorder((_) => http.Response('nope', 500));
      await init(cfg: EngageConfig(apiKey: 'k', orgId: 'o', onError: (_) => throw 'oops'));
      await expectLater(analytics().track('x'), completes);
    });
  });

  group('device id', () {
    test('is generated once, persisted under lowco_uuid and reused across re-init', () async {
      await init();
      final first = analytics().deviceId;
      expect(first, matches(_uuidPattern));
      expect(storage.values['lowco_uuid'], first);

      LowcoAnalytics.debugReset();
      await init();
      expect(analytics().deviceId, first);

      await analytics().track('x');
      expect(rec.last['device_id'], first);
    });

    test('an existing lowco_uuid is honoured', () async {
      storage = InMemoryEngageStorage({'lowco_uuid': 'abc123'});
      await init();
      await analytics().track('x');
      expect(rec.last['device_id'], 'abc123');
    });
  });

  group('sessions', () {
    test('a stored session younger than 30 minutes is reused', () async {
      final last = clock.current.subtract(const Duration(minutes: 29));
      storage = InMemoryEngageStorage({
        'lowco_session_id': 'sess_1',
        'lowco_session_last_event': '${last.millisecondsSinceEpoch}',
      });
      await init();
      expect(analytics().sessionId, 'sess_1');

      await analytics().track('x');
      expect(rec.last['session_id'], 'sess_1');
      expect(storage.values['lowco_session_last_event'], '${clock.current.millisecondsSinceEpoch}');
    });

    test('a stored session older than 30 minutes is replaced', () async {
      final last = clock.current.subtract(const Duration(minutes: 31));
      storage = InMemoryEngageStorage({
        'lowco_session_id': 'sess_1',
        'lowco_session_last_event': '${last.millisecondsSinceEpoch}',
      });
      await init();
      expect(analytics().sessionId, isNot('sess_1'));
      expect(analytics().sessionId, matches(_uuidPattern));
      expect(storage.values['lowco_session_id'], analytics().sessionId);
      expect(storage.values['lowco_session_last_event'], '${clock.current.millisecondsSinceEpoch}');
    });

    test('a malformed last-event value starts a new session', () async {
      storage = InMemoryEngageStorage({
        'lowco_session_id': 'sess_1',
        'lowco_session_last_event': 'garbage',
      });
      await init();
      expect(analytics().sessionId, isNot('sess_1'));
    });

    test('30 minutes of inactivity between events rotates the session', () async {
      await init();
      await analytics().track('a');
      final first = rec.last['session_id'];

      clock.advance(const Duration(minutes: 30));
      await analytics().track('b');
      expect(rec.last['session_id'], first, reason: 'exactly 30 min is not expired');

      clock.advance(const Duration(minutes: 30, milliseconds: 1));
      await analytics().track('c');
      expect(rec.last['session_id'], isNot(first));
      expect(storage.values['lowco_session_id'], rec.last['session_id']);
    });
  });

  group('identify', () {
    test('identifyUser sends _lowco_identify and later events carry user_id', () async {
      await init();
      await analytics().identifyUser('user_42', {'email': 'a@example.com'});
      expect(rec.last['event_name'], '_lowco_identify');
      expect(rec.last['user_id'], 'user_42');
      expect(rec.last['event_data'], {'email': 'a@example.com'});

      await analytics().track('purchase');
      expect(rec.last['user_id'], 'user_42');
      expect(rec.last['session_id'], rec.events.first['session_id']);
    });

    test('reset() forgets the user and starts a new session', () async {
      await init();
      await analytics().identifyUser('user_42');
      final session = analytics().sessionId;
      final device = analytics().deviceId;

      analytics().reset();
      await analytics().track('after_logout');
      expect(rec.last['user_id'], isNull);
      expect(rec.last['session_id'], isNot(session));
      expect(rec.last['device_id'], device);
    });
  });

  group('attribution', () {
    test('captures utm/click ids and persists first touch once', () async {
      await init();
      await analytics().captureAttribution(Uri.parse(
          'myapp://open/promo?utm_source=google&utm_medium=cpc&utm_campaign=fall&gclid=g1&foo=bar&utm_term='));
      await analytics().track('x', {'plan': 'pro'});

      final firstTouch = {
        'utm_source': 'google',
        'utm_medium': 'cpc',
        'utm_campaign': 'fall',
        'gclid': 'g1',
        'landing_url':
            'myapp://open/promo?utm_source=google&utm_medium=cpc&utm_campaign=fall&gclid=g1&foo=bar&utm_term=',
        'referrer': null,
        'captured_at': '2026-09-30T12:00:00.123Z',
      };
      expect(rec.last['event_data'], {
        'utm_source': 'google',
        'utm_medium': 'cpc',
        'utm_campaign': 'fall',
        'gclid': 'g1',
        'first_touch': firstTouch,
        'plan': 'pro',
      });
      expect(jsonDecode(storage.values['lowco_first_touch']!), firstTouch);

      // A later campaign replaces the current attribution but not first touch.
      clock.advance(const Duration(minutes: 1));
      await analytics()
          .captureAttribution(Uri.parse('https://app.example.com/?utm_source=newsletter'));
      await analytics().track('y');
      expect(rec.last['event_data'], {'utm_source': 'newsletter', 'first_touch': firstTouch});
      expect(jsonDecode(storage.values['lowco_first_touch']!), firstTouch);
    });

    test('event metadata overrides attribution keys', () async {
      await init();
      await analytics().captureAttribution(Uri.parse('myapp://x?utm_source=google'));
      await analytics().track('x', {'utm_source': 'manual'});
      expect((rec.last['event_data'] as Map)['utm_source'], 'manual');
    });

    test('a URL without attribution neither sets nor creates first touch', () async {
      await init();
      await analytics().captureAttribution(Uri.parse('myapp://x?foo=bar'));
      await analytics().track('x');
      expect(rec.last['event_data'], isEmpty);
      expect(storage.values.containsKey('lowco_first_touch'), isFalse);
    });

    test('a stored first touch is restored and sent with every event', () async {
      final stored = {'utm_source': 'bing', 'landing_url': 'https://x', 'captured_at': 't'};
      storage = InMemoryEngageStorage({'lowco_first_touch': jsonEncode(stored)});
      await init();
      await analytics().captureAttribution(Uri.parse('myapp://x?fbclid=f1'));
      await analytics().track('x');
      expect(rec.last['event_data'], {'fbclid': 'f1', 'first_touch': stored});
      expect(jsonDecode(storage.values['lowco_first_touch']!), stored);
    });

    test('attribution captured before init is applied once init completes', () async {
      await analytics().captureAttribution(Uri.parse('myapp://x?msclkid=m1&utm_id=42'));
      await init();
      await analytics().track('x');
      final data = rec.last['event_data'] as Map<String, dynamic>;
      expect(data['msclkid'], 'm1');
      expect(data['utm_id'], '42');
      expect((data['first_touch'] as Map)['landing_url'], 'myapp://x?msclkid=m1&utm_id=42');
      expect(storage.values['lowco_first_touch'], isNotNull);
    });

    test('attributionFromUri reads hash-routed query strings and the first value', () {
      expect(
        attributionFromUri(Uri.parse('https://a.com/#/landing?utm_source=x&utm_content=c')),
        {'utm_source': 'x', 'utm_content': 'c'},
      );
      expect(
        attributionFromUri(Uri.parse('https://a.com/?utm_source=q&utm_source=r#/p?utm_source=f')),
        {'utm_source': 'q'},
      );
      expect(attributionFromUri(Uri.parse('https://a.com/')), isEmpty);
    });
  });

  group('observer', () {
    Widget app(LowcoAnalyticsObserver observer) => MaterialApp(
          navigatorObservers: [observer],
          routes: {
            '/': (_) => const Text('home'),
            '/details': (_) => const Text('details'),
            '/settings': (_) => const Text('settings'),
          },
        );

    List<Object?> pageViews() => [
          for (final e in rec.events)
            if (e['event_name'] == 'page_view') e['event_data'],
        ];

    testWidgets('sends page_view for push, replace and pop of named routes', (tester) async {
      await init();
      await tester.pumpWidget(app(LowcoAnalyticsObserver()));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/details');
      await tester.pumpAndSettle();
      navigator.pushReplacementNamed('/settings');
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(pageViews(), [
        {'path': '/', 'title': '/'},
        {'path': '/details', 'title': '/details'},
        {'path': '/settings', 'title': '/settings'},
        {'path': '/', 'title': '/'},
      ]);
    });

    testWidgets('skips routes without a name', (tester) async {
      await init();
      await tester.pumpWidget(app(LowcoAnalyticsObserver()));
      await tester.pumpAndSettle();
      rec.requests.clear();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('anon')));
      await tester.pumpAndSettle();
      expect(pageViews(), isEmpty);

      navigator.pop(); // back to the named home route
      await tester.pumpAndSettle();
      expect(pageViews(), [
        {'path': '/', 'title': '/'},
      ]);
    });

    testWidgets('drops page views before init', (tester) async {
      await tester.pumpWidget(app(LowcoAnalyticsObserver()));
      await tester.pumpAndSettle();
      expect(rec.requests, isEmpty);
    });
  });

  group('storage', () {
    test('SharedPreferencesEngageStorage round-trips values', () async {
      SharedPreferences.setMockInitialValues({'lowco_uuid': 'dev_1'});
      final prefs = SharedPreferencesEngageStorage();
      expect(await prefs.getString('lowco_uuid'), 'dev_1');
      await prefs.setString('lowco_session_id', 's');
      expect(await prefs.getString('lowco_session_id'), 's');
      await prefs.remove('lowco_session_id');
      expect(await prefs.getString('lowco_session_id'), isNull);
    });

    test('is the default storage', () async {
      SharedPreferences.setMockInitialValues({'lowco_uuid': 'from_prefs'});
      LowcoAnalytics.instance.now = clock.call;
      await LowcoAnalytics.instance.init(config, httpClient: rec.client);
      expect(analytics().deviceId, 'from_prefs');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lowco_session_id'), analytics().sessionId);
    });
  });

  group('device info', () {
    test('native platforms', () {
      final ios = buildDeviceInfo(
        isWeb: false,
        platform: TargetPlatform.iOS,
        osVersionString: 'Version 17.4 (Build 21E213)',
        logicalShortestSide: 390,
      );
      expect(ios.toJson(), {
        'os': {'name': 'iOS', 'version': '17.4'},
        'device': {'type': 'mobile', 'vendor': 'Apple'},
        'engine': {'name': 'Flutter'},
        'ua': 'Flutter (iOS 17.4)',
      });

      final tablet = buildDeviceInfo(
        isWeb: false,
        platform: TargetPlatform.android,
        osVersionString: 'Linux 5.10.43 #1 SMP PREEMPT',
        logicalShortestSide: 800,
      );
      expect(tablet.toJson(), {
        'os': {'name': 'Android'},
        'device': {'type': 'tablet'},
        'engine': {'name': 'Flutter'},
        'ua': 'Flutter (Android)',
      });

      final windows = buildDeviceInfo(
        isWeb: false,
        platform: TargetPlatform.windows,
        osVersionString: '"Windows 10 Pro" 10.0 (Build 19045)',
      );
      expect(windows.os!.version, '10.0');
      expect(windows.device!.type, 'desktop');

      final mac = buildDeviceInfo(isWeb: false, platform: TargetPlatform.macOS);
      expect(mac.os!.name, 'Mac OS');
      expect(mac.device!.type, 'desktop');
    });

    test('web parses the user agent', () {
      const ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/129.0.6668.71 Safari/537.36';
      final info = buildDeviceInfo(isWeb: true, platform: TargetPlatform.macOS, userAgent: ua);
      expect(info.toJson(), {
        'browser': {'name': 'Chrome', 'version': '129.0.6668.71', 'major': '129'},
        'os': {'name': 'Mac OS', 'version': '10.15.7'},
        'device': {'type': 'web', 'vendor': 'Apple'},
        'engine': {'name': 'Flutter'},
        'ua': ua,
      });

      const safari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
      final ios = buildDeviceInfo(isWeb: true, platform: TargetPlatform.iOS, userAgent: safari);
      expect(ios.browser!.name, 'Safari');
      expect(ios.os!.version, '17.4');

      const edge =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/129.0.0.0 Safari/537.36 Edg/129.0.2792.65';
      final win = buildDeviceInfo(isWeb: true, platform: TargetPlatform.windows, userAgent: edge);
      expect(win.browser!.name, 'Edge');
      expect(win.os!.version, '10');

      final unknown = buildDeviceInfo(isWeb: true, platform: TargetPlatform.linux);
      expect(unknown.browser, isNull);
      expect(unknown.ua, 'Flutter (web)');
    });
  });

  test('uuidV4 produces RFC 4122 v4 ids', () {
    final ids = {for (var i = 0; i < 100; i++) uuidV4()};
    expect(ids, hasLength(100));
    expect(ids, everyElement(matches(_uuidPattern)));
  });

  test('EngageEvent JSON round-trips', () {
    final event = EngageEvent(
      eventName: 'x',
      eventData: const {'a': 1},
      deviceId: 'd',
      sessionId: 's',
      eventTime: DateTime.utc(2026, 1, 1),
    );
    final json = jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>;
    final back = EngageEvent.fromJson(json);
    expect(back.toJson(), event.toJson());
    expect(json['user_id'], isNull);
    expect(json.containsKey('device_info'), isTrue);
  });
}
