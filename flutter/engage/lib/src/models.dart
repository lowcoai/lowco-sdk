import 'json.dart';

/// Free-form event properties (`Metadata` in the TS SDK). Values must be
/// JSON-encodable; `DateTime`s are sent as ISO-8601 strings.
typedef Metadata = Map<String, dynamic>;

/// Configuration for [LowcoAnalytics.init] (`Config` in the TS SDK).
class EngageConfig {
  const EngageConfig({
    required this.apiKey,
    required this.orgId,
    this.autoTrack = false,
    this.onError,
  });

  /// API key, sent as `Authorization: Bearer <apiKey>`. Never logged.
  final String apiKey;

  /// Organization id, sent as the `X-Org-Id` header.
  final String orgId;

  /// On web, also capture attribution from the page URL (`Uri.base`) during
  /// `init`. Route page views come from `LowcoAnalyticsObserver`.
  final bool autoTrack;

  /// Receives every delivery / storage error. Tracking never throws into the
  /// app; without a handler errors are only `debugPrint`ed in debug builds.
  final void Function(Object error)? onError;

  @override
  String toString() => 'EngageConfig(orgId: $orgId, autoTrack: $autoTrack, apiKey: <redacted>)';
}

/// `device_info.browser` (web only).
class BrowserInfo {
  const BrowserInfo({this.name, this.version, this.major});

  factory BrowserInfo.fromJson(Map<String, dynamic> json) => BrowserInfo(
        name: readString(json['name']),
        version: readString(json['version']),
        major: readString(json['major']),
      );

  final String? name;
  final String? version;
  final String? major;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (version != null) 'version': version,
        if (major != null) 'major': major,
      };
}

/// `device_info.os`.
class OsInfo {
  const OsInfo({this.name, this.version});

  factory OsInfo.fromJson(Map<String, dynamic> json) =>
      OsInfo(name: readString(json['name']), version: readString(json['version']));

  /// `Android`, `iOS`, `Mac OS`, `Windows`, `Linux`, `Fuchsia` (the names the
  /// browser SDK's user-agent parser reports).
  final String? name;
  final String? version;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (version != null) 'version': version,
      };
}

/// `device_info.device`.
class DeviceDetails {
  const DeviceDetails({this.type, this.vendor, this.model});

  factory DeviceDetails.fromJson(Map<String, dynamic> json) => DeviceDetails(
        type: readString(json['type']),
        vendor: readString(json['vendor']),
        model: readString(json['model']),
      );

  /// `mobile`, `tablet`, `desktop` or `web`.
  final String? type;
  final String? vendor;
  final String? model;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (vendor != null) 'vendor': vendor,
        if (model != null) 'model': model,
      };
}

/// `device_info.cpu`.
class CpuInfo {
  const CpuInfo({this.architecture});

  factory CpuInfo.fromJson(Map<String, dynamic> json) =>
      CpuInfo(architecture: readString(json['architecture']));

  final String? architecture;

  Map<String, dynamic> toJson() => {if (architecture != null) 'architecture': architecture};
}

/// `device_info.engine`.
class EngineInfo {
  const EngineInfo({this.name, this.version});

  factory EngineInfo.fromJson(Map<String, dynamic> json) =>
      EngineInfo(name: readString(json['name']), version: readString(json['version']));

  final String? name;
  final String? version;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (version != null) 'version': version,
      };
}

/// Device description attached to every event (`DeviceInfo` in the TS SDK,
/// same keys).
class DeviceInfo {
  const DeviceInfo({this.browser, this.os, this.device, this.cpu, this.engine, this.ua});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        browser: readObject(json['browser'], BrowserInfo.fromJson),
        os: readObject(json['os'], OsInfo.fromJson),
        device: readObject(json['device'], DeviceDetails.fromJson),
        cpu: readObject(json['cpu'], CpuInfo.fromJson),
        engine: readObject(json['engine'], EngineInfo.fromJson),
        ua: readString(json['ua']),
      );

  final BrowserInfo? browser;
  final OsInfo? os;
  final DeviceDetails? device;
  final CpuInfo? cpu;
  final EngineInfo? engine;

  /// The browser's user agent on web; `Flutter (<os> <version>)` elsewhere.
  final String? ua;

  Map<String, dynamic> toJson() => {
        if (browser != null) 'browser': browser!.toJson(),
        if (os != null) 'os': os!.toJson(),
        if (device != null) 'device': device!.toJson(),
        if (cpu != null) 'cpu': cpu!.toJson(),
        if (engine != null) 'engine': engine!.toJson(),
        if (ua != null) 'ua': ua,
      };
}

/// Location attached to events (`LocationInfo` in the TS SDK). The SDK does
/// not read the location itself: pass coordinates from your own location
/// plugin to [LowcoAnalytics.setLocation]. On the wire the keys are snake_case
/// like the rest of the event (`altitude_accuracy`), which is what the engage
/// ingest model reads.
class LocationInfo {
  const LocationInfo({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.heading,
    this.speed,
  });

  factory LocationInfo.fromJson(Map<String, dynamic> json) => LocationInfo(
        latitude: readDouble(json['latitude']),
        longitude: readDouble(json['longitude']),
        accuracy: readDouble(json['accuracy']),
        altitude: readDouble(json['altitude']),
        altitudeAccuracy: readDouble(json['altitude_accuracy']),
        heading: readDouble(json['heading']),
        speed: readDouble(json['speed']),
      );

  final double? latitude;
  final double? longitude;

  /// Metres.
  final double? accuracy;
  final double? altitude;
  final double? altitudeAccuracy;

  /// Degrees clockwise from true north.
  final double? heading;

  /// Metres per second.
  final double? speed;

  Map<String, dynamic> toJson() => {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (altitude != null) 'altitude': altitude,
        if (altitudeAccuracy != null) 'altitude_accuracy': altitudeAccuracy,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
      };
}

/// One tracked event, exactly as POSTed to `/v1/engage/track` (`Event` in the
/// TS SDK).
///
/// Unlike the other models, [toJson] keeps `user_id`, `device_info` and
/// `location` as explicit `null`s, matching what the browser SDK sends.
class EngageEvent {
  const EngageEvent({
    this.id = '',
    required this.eventName,
    this.eventData = const {},
    this.userId,
    required this.deviceId,
    this.sessionId,
    this.deviceInfo,
    this.location,
    required this.eventTime,
  });

  factory EngageEvent.fromJson(Map<String, dynamic> json) => EngageEvent(
        id: readString(json['id']) ?? '',
        eventName: readString(json['event_name']) ?? '',
        eventData: readMap(json['event_data']) ?? const {},
        userId: readString(json['user_id']),
        deviceId: readString(json['device_id']) ?? '',
        sessionId: readString(json['session_id']),
        deviceInfo: readObject(json['device_info'], DeviceInfo.fromJson),
        location: readObject(json['location'], LocationInfo.fromJson),
        eventTime: DateTime.tryParse(readString(json['event_time']) ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// Always `""` (assigned by the server).
  final String id;
  final String eventName;
  final Metadata eventData;
  final String? userId;
  final String deviceId;
  final String? sessionId;
  final DeviceInfo? deviceInfo;
  final LocationInfo? location;
  final DateTime eventTime;

  Map<String, dynamic> toJson() => {
        'id': id,
        'event_name': eventName,
        'event_data': eventData,
        'user_id': userId,
        'device_id': deviceId,
        if (sessionId != null) 'session_id': sessionId,
        'device_info': deviceInfo?.toJson(),
        'location': location?.toJson(),
        'event_time': isoTimestamp(eventTime),
      };
}

/// Delivery failure passed to [EngageConfig.onError] for a non-2xx answer
/// from the track endpoint.
class EngageException implements Exception {
  EngageException({required this.statusCode, required String message, this.body = ''})
      : message = message.isEmpty ? 'engage: status=$statusCode' : message;

  final int statusCode;
  final String message;

  /// The raw response body, for debugging.
  final String body;

  @override
  String toString() => 'EngageException($statusCode): $message';
}

/// ISO-8601 UTC with millisecond precision, like JavaScript's
/// `Date.prototype.toISOString()` (`2026-01-02T03:04:05.678Z`).
String isoTimestamp(DateTime time) =>
    DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch, isUtc: true).toIso8601String();
