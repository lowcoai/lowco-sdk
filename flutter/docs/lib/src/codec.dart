// Internal encoding / lenient decoding helpers shared by the transport and
// the resources. Not exported from the package.

import 'dart:convert';

import 'errors.dart';
import 'json.dart';

/// `toEncodable` for [jsonEncode]: model classes expose `toJson()`.
Object? toEncodable(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  return (value as dynamic).toJson();
}

/// Encodes query parameters: `null` values are skipped, strings are sent
/// as-is, booleans as `true`/`false`, numbers via their string form and
/// anything else as JSON.
Map<String, String> encodeQuery(Map<String, Object?> query) => {
      for (final e in query.entries)
        if (e.value != null) e.key: encodeQueryValue(e.value!),
    };

String encodeQueryValue(Object value) {
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) {
    // Whole doubles have no ".0", like JavaScript's String(n).
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() < 1e21) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  return jsonEncode(value, toEncodable: toEncodable);
}

/// Percent-encodes one single-segment path parameter (bucket name, key, node
/// id, ...) with `encodeURIComponent` semantics, so a `/` becomes `%2F`.
///
/// Throws [DocsException] (status `0`, nothing sent) for `.` and `..`: URL
/// normalisation would silently send the request to a different route.
String seg(String value) => Uri.encodeComponent(_checkSegment(value, value));

/// Encodes a wildcard `{path}` parameter: leading slashes are stripped and
/// every segment is percent-encoded while the `/` separators are kept
/// (`a b/c.txt` becomes `a%20b/c.txt`).
///
/// Throws [DocsException] (status `0`, nothing sent) when a segment is `.` or
/// `..`.
String segs(String path) {
  var start = 0;
  while (start < path.length && path.codeUnitAt(start) == 0x2F) {
    start++;
  }
  return path
      .substring(start)
      .split('/')
      .map((s) => Uri.encodeComponent(_checkSegment(s, path)))
      .join('/');
}

String _checkSegment(String segment, String value) {
  if (segment == '.' || segment == '..') {
    throw DocsException(
      message: 'Invalid path "$value": "." and ".." segments are not allowed.',
      status: 0,
    );
  }
  return segment;
}

T decodeOne<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObject(data, fromJson) ?? fromJson(const {});

List<T> decodeMany<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObjectList(data, fromJson) ?? <T>[];

/// The `data` of a `MessageResponse` (a confirmation such as `file deleted`).
String decodeMessage(Object? data) => readString(data) ?? '';
