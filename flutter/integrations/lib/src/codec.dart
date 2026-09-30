// Internal encoding / lenient decoding helpers shared by the transport and
// the resources. Not exported from the package.

import 'dart:convert';

import 'json.dart';

/// `toEncodable` for [jsonEncode]: model classes expose `toJson()`.
Object? toEncodable(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  return (value as dynamic).toJson();
}

/// Encodes query parameters like the TS SDK: `null` values are skipped,
/// strings are sent as-is, booleans as `true`/`false`, numbers via their
/// string form and anything else as JSON.
Map<String, String> encodeQuery(Map<String, Object?> query) => {
      for (final e in query.entries)
        if (e.value != null) e.key: encodeQueryValue(e.value!),
    };

String encodeQueryValue(Object value) {
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) {
    // Match JavaScript's String(n): whole doubles have no ".0".
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

/// Percent-encodes one path segment.
String seg(String value) => Uri.encodeComponent(value);

T decodeOne<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObject(data, fromJson) ?? fromJson(const {});

List<T> decodeMany<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObjectList(data, fromJson) ?? <T>[];

Map<String, dynamic> decodeMap(Object? data) => readMap(data) ?? <String, dynamic>{};

List<Map<String, dynamic>> decodeMapList(Object? data) => readMapList(data) ?? [];

List<Object?> decodeList(Object? data) => readDynamicList(data) ?? [];

/// `Record<ApplicationType, ApplicationSubType[]>` -> `Map<String, List<String>>`.
Map<String, List<String>> decodeStringListMap(Object? data) => {
      for (final e in (readMap(data) ?? const <String, dynamic>{}).entries)
        e.key: readStringList(e.value) ?? <String>[],
    };
