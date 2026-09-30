import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'device_info.dart';
import 'json.dart';
import 'models.dart';
import 'storage.dart';

/// The fixed API host every lowco SDK talks to.
const String lowcoBaseUrl = 'https://api.lowco.ai';

/// Path of the event ingestion endpoint.
const String engageTrackPath = '/v1/engage/track';

/// Header carrying the organization id.
const String headerOrgId = 'X-Org-Id';

/// Storage key of the persistent device (anonymous) id.
const String deviceIdStorageKey = 'lowco_uuid';

/// Storage key of the current session id.
const String sessionIdStorageKey = 'lowco_session_id';

/// Storage key of the last event time (epoch milliseconds, as a string).
const String sessionLastEventStorageKey = 'lowco_session_last_event';

/// Storage key of the first-touch attribution JSON.
const String firstTouchStorageKey = 'lowco_first_touch';

/// A session ends after this much inactivity (same as the browser SDK).
const Duration sessionTimeout = Duration(minutes: 30);

/// Query parameters captured as attribution.
const List<String> attributionKeys = [
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
  'gclid',
  'fbclid',
  'msclkid',
];

const Duration _requestTimeout = Duration(seconds: 30);
final Uri _trackUri = Uri.parse('$lowcoBaseUrl$engageTrackPath');

/// Analytics client for the lowco engage service. Use the process-wide
/// [instance] (the TS SDK's default export).
///
/// ```dart
/// await LowcoAnalytics.instance.init(const EngageConfig(apiKey: '...', orgId: 'org_123'));
/// LowcoAnalytics.instance.track('signup_completed', {'plan': 'pro'});
/// ```
///
/// Every event is POSTed on its own to `https://api.lowco.ai/v1/engage/track`.
/// Tracking is fire-and-forget: the returned futures never throw, failures go
/// to [EngageConfig.onError]. Calls made before [init] completes are dropped.
class LowcoAnalytics {
  LowcoAnalytics._();

  static LowcoAnalytics _instance = LowcoAnalytics._();

  /// The shared analytics client.
  static LowcoAnalytics get instance => _instance;

  /// Replaces [instance] with a fresh, uninitialized client (closing the HTTP
  /// client the old one created). For tests only.
  @visibleForTesting
  static void debugReset() {
    _instance._closeHttp();
    _instance = LowcoAnalytics._();
  }

  /// Clock used for event times and session expiry. Tests may replace it.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  EngageConfig? _config;
  EngageStorage _storage = InMemoryEngageStorage();
  http.Client? _http;
  bool _ownsHttp = false;
  int _generation = 0;

  String? _userId;
  String? _deviceId;
  String? _sessionId;
  int? _lastEventTime;
  DeviceInfo? _deviceInfo;
  LocationInfo? _location;
  Map<String, String> _attribution = const {};
  Map<String, dynamic>? _firstTouch;
  Uri? _pendingLandingUri;

  /// Whether [init] has completed.
  bool get isInitialized => _config != null;

  /// The user id set by [identifyUser], sent with every later event.
  String? get userId => _userId;

  /// The persistent anonymous device id (`lowco_uuid`).
  String? get deviceId => _deviceId;

  /// The current session id (`lowco_session_id`).
  String? get sessionId => _sessionId;

  /// The `device_info` sent with events.
  DeviceInfo? get deviceInfo => _deviceInfo;

  /// The `location` sent with events.
  LocationInfo? get location => _location;

  /// Attribution parameters from the last [captureAttribution] call.
  Map<String, String> get attribution => Map.unmodifiable(_attribution);

  /// The persisted first-touch attribution, if any.
  Map<String, dynamic>? get firstTouch =>
      _firstTouch == null ? null : Map.unmodifiable(_firstTouch!);

  /// Configures the client and restores (or creates) the device id and the
  /// session from [storage] (default: [SharedPreferencesEngageStorage]).
  ///
  /// Await it before tracking; call `WidgetsFlutterBinding.ensureInitialized()`
  /// first when running before `runApp`. [httpClient] lets you plug in your own
  /// client (it is never closed by the SDK). Calling [init] again reconfigures
  /// the client; the user id set by [identifyUser] is kept.
  ///
  /// On web with [EngageConfig.autoTrack], attribution is captured from the
  /// page URL ([Uri.base]).
  Future<void> init(
    EngageConfig config, {
    EngageStorage? storage,
    http.Client? httpClient,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw ArgumentError('LowcoAnalytics: apiKey is required');
    }
    if (config.orgId.trim().isEmpty) {
      throw ArgumentError('LowcoAnalytics: orgId is required');
    }
    final generation = ++_generation;
    _config = null;
    _closeHttp();
    _http = httpClient ?? http.Client();
    _ownsHttp = httpClient == null;
    _storage = storage ?? SharedPreferencesEngageStorage();
    _deviceInfo ??= detectDeviceInfo();

    final deviceId = await _read(config, deviceIdStorageKey);
    final sessionId = await _read(config, sessionIdStorageKey);
    final lastEvent = await _read(config, sessionLastEventStorageKey);
    final firstTouch = await _read(config, firstTouchStorageKey);
    if (generation != _generation) return; // superseded by a newer init()

    if (deviceId != null && deviceId.isNotEmpty) {
      _deviceId = deviceId;
    } else {
      _deviceId = uuidV4();
      unawaited(_write(config, deviceIdStorageKey, _deviceId!));
    }

    _initializeSession(config, sessionId, lastEvent);
    _firstTouch = _decodeFirstTouch(config, firstTouch);

    if (kIsWeb && config.autoTrack && _pendingLandingUri == null) {
      _attribution = attributionFromUri(Uri.base);
      _pendingLandingUri = Uri.base;
    }
    final landing = _pendingLandingUri;
    _pendingLandingUri = null;
    if (landing != null) unawaited(_resolveFirstTouch(config, landing));

    _config = config;
  }

  /// Sends a custom event. [metadata] is merged over the attribution context
  /// (`utm_*`, click ids and `first_touch`) into `event_data`.
  Future<void> track(String eventName, [Metadata? metadata]) {
    final config = _config;
    if (config == null) return _notInitialized();
    return _emit(config, eventName, metadata);
  }

  /// Sends a `page_view` event.
  Future<void> page([Metadata? properties]) => track('page_view', properties);

  /// Remembers [userId] for every later event and sends `_lowco_identify`
  /// with [properties]. The id is kept in memory only (like the browser SDK):
  /// call it again after an app restart.
  Future<void> identifyUser(String userId, [Metadata? properties]) {
    final config = _config;
    if (config == null) return _notInitialized();
    _userId = userId;
    return _emit(config, '_lowco_identify', properties);
  }

  /// Sets (or clears) the location sent with later events. The SDK does not
  /// read the location itself; pass coordinates from your location plugin.
  void setLocation(LocationInfo? location) => _location = location;

  /// Replaces the auto-detected `device_info`, e.g. with the model and OS
  /// release from `device_info_plus`.
  void setDeviceInfo(DeviceInfo deviceInfo) => _deviceInfo = deviceInfo;

  /// Captures attribution from a deep link or web URL: `utm_source`,
  /// `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `utm_id`,
  /// `gclid`, `fbclid` and `msclkid` (query string, or the query part of a
  /// `#/route?...` fragment).
  ///
  /// The parameters are added to every later event. The first time any are
  /// seen they are also persisted as first-touch attribution
  /// (`lowco_first_touch`, with `landing_url`, `referrer` and `captured_at`),
  /// which is never overwritten. May be called before [init] completes.
  Future<void> captureAttribution(Uri uri) async {
    _attribution = attributionFromUri(uri);
    final config = _config;
    if (config == null) {
      _pendingLandingUri = uri;
      return;
    }
    await _resolveFirstTouch(config, uri);
  }

  /// Logout: forgets the user id and starts a new session. The device id and
  /// attribution are kept.
  void reset() {
    _userId = null;
    final config = _config;
    if (config != null) _startNewSession(config, now().millisecondsSinceEpoch);
  }

  // --- Sessions (same rules as the browser SDK) ----------------------------

  void _initializeSession(EngageConfig config, String? storedId, String? storedLastEvent) {
    final nowMs = now().millisecondsSinceEpoch;
    if (storedId != null && storedId.isNotEmpty && storedLastEvent != null) {
      final last = num.tryParse(storedLastEvent.trim());
      if (last != null && nowMs - last <= sessionTimeout.inMilliseconds) {
        _sessionId = storedId;
        _lastEventTime = last.toInt();
        return;
      }
    }
    _startNewSession(config, nowMs);
  }

  void _startNewSession(EngageConfig config, int timestamp) {
    _sessionId = uuidV4();
    _lastEventTime = timestamp;
    _persistSession(config);
  }

  void _ensureActiveSession(EngageConfig config, int eventTimestamp) {
    final last = _lastEventTime;
    if (_sessionId == null || last == null) {
      _startNewSession(config, eventTimestamp);
      return;
    }
    if (eventTimestamp - last > sessionTimeout.inMilliseconds) {
      _startNewSession(config, eventTimestamp);
      return;
    }
    _lastEventTime = eventTimestamp;
    _persistSession(config);
  }

  void _persistSession(EngageConfig config) {
    unawaited(_write(config, sessionIdStorageKey, _sessionId!));
    unawaited(_write(config, sessionLastEventStorageKey, '$_lastEventTime'));
  }

  // --- Attribution ---------------------------------------------------------

  Map<String, dynamic> _attributionContext() => {
        ..._attribution,
        if (_firstTouch != null) 'first_touch': _firstTouch,
      };

  Future<void> _resolveFirstTouch(EngageConfig config, Uri landing) async {
    if (_firstTouch != null || _attribution.isEmpty) return;
    final firstTouch = Map<String, dynamic>.unmodifiable(<String, dynamic>{
      ..._attribution,
      'landing_url': landing.toString(),
      'referrer': null,
      'captured_at': isoTimestamp(now()),
    });
    _firstTouch = firstTouch;
    await _write(config, firstTouchStorageKey, jsonEncode(firstTouch));
  }

  Map<String, dynamic>? _decodeFirstTouch(EngageConfig config, String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = readMap(jsonDecode(raw));
      return parsed == null ? null : Map.unmodifiable(parsed);
    } catch (error) {
      _report(config, error);
      return null;
    }
  }

  // --- Delivery ------------------------------------------------------------

  Future<void> _emit(EngageConfig config, String eventName, Metadata? data) {
    final eventTime = now();
    _ensureActiveSession(config, eventTime.millisecondsSinceEpoch);
    final event = EngageEvent(
      eventName: eventName,
      eventData: {..._attributionContext(), ...?data},
      userId: _userId,
      deviceId: _deviceId ?? '',
      sessionId: _sessionId,
      deviceInfo: _deviceInfo,
      location: _location,
      eventTime: eventTime,
    );
    return _send(config, event);
  }

  Future<void> _send(EngageConfig config, EngageEvent event) async {
    final client = _http;
    if (client == null) return;
    try {
      final abort = Completer<void>();
      final request = http.AbortableRequest('POST', _trackUri, abortTrigger: abort.future)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
          headerOrgId: config.orgId,
        })
        ..bodyBytes = utf8.encode(jsonEncode(event.toJson(), toEncodable: _toEncodable));
      final response = await client.send(request).then(http.Response.fromStream).timeout(
        _requestTimeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('engage: POST $engageTrackPath timed out', _requestTimeout);
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response);
      }
    } catch (error) {
      _report(config, error);
    }
  }

  // --- Helpers -------------------------------------------------------------

  Future<String?> _read(EngageConfig config, String key) async {
    try {
      return await _storage.getString(key);
    } catch (error) {
      _report(config, error);
      return null;
    }
  }

  Future<void> _write(EngageConfig config, String key, String value) async {
    try {
      await _storage.setString(key, value);
    } catch (error) {
      _report(config, error);
    }
  }

  void _report(EngageConfig config, Object error) {
    final handler = config.onError;
    if (handler == null) {
      if (kDebugMode) debugPrint('LowcoAnalytics: $error');
      return;
    }
    try {
      handler(error);
    } catch (handlerError) {
      if (kDebugMode) debugPrint('LowcoAnalytics: onError threw: $handlerError');
    }
  }

  Future<void> _notInitialized() {
    if (kDebugMode) debugPrint('LowcoAnalytics not initialized. Call init() first.');
    return Future<void>.value();
  }

  void _closeHttp() {
    if (_ownsHttp) _http?.close();
    _http = null;
    _ownsHttp = false;
  }
}

/// Extracts the [attributionKeys] from [uri]'s query string and from the query
/// part of its fragment (hash routing: `/#/landing?utm_source=x`). Empty values
/// are skipped; the query string wins over the fragment.
Map<String, String> attributionFromUri(Uri uri) {
  Map<String, List<String>> query;
  Map<String, List<String>> fragmentQuery = const {};
  try {
    query = uri.queryParametersAll;
  } on FormatException {
    query = const {};
  }
  final fragment = uri.fragment;
  final queryStart = fragment.indexOf('?');
  if (queryStart >= 0) {
    try {
      fragmentQuery = Uri(query: fragment.substring(queryStart + 1)).queryParametersAll;
    } on FormatException {
      fragmentQuery = const {};
    }
  }
  final out = <String, String>{};
  for (final key in attributionKeys) {
    final values = query[key] ?? fragmentQuery[key];
    final value = values == null || values.isEmpty ? null : values.first;
    if (value != null && value.isNotEmpty) out[key] = value;
  }
  return out;
}

/// A random (version 4) UUID from a cryptographically secure source.
String uuidV4([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

EngageException _httpError(http.Response response) {
  final text = response.body;
  var message = text.trim();
  try {
    final parsed = jsonDecode(text);
    if (parsed is Map) {
      final error = parsed['error'];
      if (error is Map && error['message'] is String) {
        message = error['message'] as String;
      } else if (error is String && error.isNotEmpty) {
        message = error;
      } else if (parsed['message'] is String) {
        message = parsed['message'] as String;
      }
    }
  } on FormatException {
    // Keep the raw text.
  }
  return EngageException(statusCode: response.statusCode, message: message, body: text);
}

Object? _toEncodable(Object? value) {
  if (value is DateTime) return isoTimestamp(value);
  try {
    return (value as dynamic).toJson();
  } on NoSuchMethodError {
    return value.toString();
  }
}
