// Fallback for platforms with neither `dart:io` nor `dart:js_interop`.

/// `Platform.operatingSystemVersion` on native platforms.
String? operatingSystemVersion() => null;

/// `navigator.userAgent` on web.
String? browserUserAgent() => null;
