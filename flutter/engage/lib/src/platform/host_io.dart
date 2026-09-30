import 'dart:io' show Platform;

/// `Platform.operatingSystemVersion`, e.g. `Version 17.0 (Build 21A329)` on iOS.
String? operatingSystemVersion() {
  try {
    return Platform.operatingSystemVersion;
  } catch (_) {
    return null;
  }
}

/// Not available outside the browser.
String? browserUserAgent() => null;
