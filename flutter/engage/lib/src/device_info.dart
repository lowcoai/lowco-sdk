import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'platform/host_stub.dart'
    if (dart.library.io) 'platform/host_io.dart'
    if (dart.library.js_interop) 'platform/host_web.dart' as host;

/// Detects the current device without any device-info plugin.
DeviceInfo detectDeviceInfo() => buildDeviceInfo(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      osVersionString: host.operatingSystemVersion(),
      userAgent: host.browserUserAgent(),
      logicalShortestSide: _logicalShortestSide(),
    );

/// Builds the `device_info` payload from raw platform facts.
///
/// * [osVersionString] — `Platform.operatingSystemVersion` (native only).
/// * [userAgent] — `navigator.userAgent` (web only).
/// * [logicalShortestSide] — shortest side of the app window in logical
///   pixels; phones/tablets with >= 600 are reported as `tablet`.
@visibleForTesting
DeviceInfo buildDeviceInfo({
  required bool isWeb,
  required TargetPlatform platform,
  String? osVersionString,
  String? userAgent,
  double? logicalShortestSide,
}) {
  final osName = _osName(platform);
  final isApple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  if (isWeb) {
    final ua = userAgent == null || userAgent.isEmpty ? null : userAgent;
    return DeviceInfo(
      browser: ua == null ? null : _parseBrowser(ua),
      os: OsInfo(name: osName, version: ua == null ? null : _webOsVersion(platform, ua)),
      device: DeviceDetails(type: 'web', vendor: isApple ? 'Apple' : null),
      engine: const EngineInfo(name: 'Flutter'),
      ua: ua ?? 'Flutter (web)',
    );
  }

  final version = _nativeOsVersion(platform, osVersionString);
  final String type;
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      type = (logicalShortestSide ?? 0) >= 600 ? 'tablet' : 'mobile';
    case TargetPlatform.fuchsia:
      type = 'mobile';
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      type = 'desktop';
  }
  return DeviceInfo(
    os: OsInfo(name: osName, version: version),
    device: DeviceDetails(type: type, vendor: isApple ? 'Apple' : null),
    engine: const EngineInfo(name: 'Flutter'),
    ua: 'Flutter ($osName${version == null ? '' : ' $version'})',
  );
}

/// The OS names reported by the browser SDK's user-agent parser.
String _osName(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iOS';
    case TargetPlatform.macOS:
      return 'Mac OS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}

final _appleVersion = RegExp(r'Version (\d+(?:\.\d+)*)');
final _dottedVersion = RegExp(r'\d+(?:\.\d+)+');

String? _nativeOsVersion(TargetPlatform platform, String? raw) {
  if (raw == null || raw.isEmpty) return null;
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      // "Version 17.0 (Build 21A329)"
      return _appleVersion.firstMatch(raw)?.group(1);
    case TargetPlatform.windows:
      // "\"Windows 10 Pro\" 10.0 (Build 19045)"
      return _dottedVersion.firstMatch(raw)?.group(0);
    case TargetPlatform.android:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      // Only the kernel release is available without a plugin; it is not the
      // OS version, so leave it out (see LowcoAnalytics.setDeviceInfo).
      return null;
  }
}

const _windowsNt = {'10.0': '10', '6.3': '8.1', '6.2': '8', '6.1': '7', '6.0': 'Vista'};

String? _webOsVersion(TargetPlatform platform, String ua) {
  String? match(String pattern) => RegExp(pattern).firstMatch(ua)?.group(1);
  switch (platform) {
    case TargetPlatform.android:
      return match(r'Android (\d+(?:\.\d+)*)');
    case TargetPlatform.iOS:
      return match(r'(?:iPhone|CPU) OS (\d+(?:_\d+)*)')?.replaceAll('_', '.');
    case TargetPlatform.macOS:
      return match(r'Mac OS X (\d+(?:[._]\d+)*)')?.replaceAll('_', '.');
    case TargetPlatform.windows:
      final nt = match(r'Windows NT (\d+\.\d+)');
      return nt == null ? null : (_windowsNt[nt] ?? nt);
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return null;
  }
}

const _browsers = [
  ('Edge', r'Edg(?:e|A|iOS)?/(\d+(?:\.\d+)*)'),
  ('Opera', r'(?:OPR|OPT)/(\d+(?:\.\d+)*)'),
  ('Samsung Internet', r'SamsungBrowser/(\d+(?:\.\d+)*)'),
  ('Firefox', r'(?:Firefox|FxiOS)/(\d+(?:\.\d+)*)'),
  ('Chrome', r'(?:Chrome|CriOS)/(\d+(?:\.\d+)*)'),
  ('Safari', r'Version/(\d+(?:\.\d+)*).*Safari/'),
];

BrowserInfo? _parseBrowser(String ua) {
  for (final (name, pattern) in _browsers) {
    final version = RegExp(pattern).firstMatch(ua)?.group(1);
    if (version != null) {
      return BrowserInfo(name: name, version: version, major: version.split('.').first);
    }
  }
  return null;
}

double? _logicalShortestSide() {
  try {
    final view = ui.PlatformDispatcher.instance.implicitView;
    if (view == null || view.devicePixelRatio <= 0) return null;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.isEmpty ? null : size.shortestSide;
  } catch (_) {
    return null;
  }
}
