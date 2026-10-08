import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Not available in the browser (parsed from the user agent instead).
String? operatingSystemVersion() => null;

/// `navigator.userAgent`.
String? browserUserAgent() {
  try {
    final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
    return navigator?.getProperty<JSString?>('userAgent'.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}
