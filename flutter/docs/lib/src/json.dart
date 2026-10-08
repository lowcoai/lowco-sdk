// Lenient JSON readers shared by the model classes. They coerce instead of
// throwing so a server that widens a field's type does not break decoding.

String? readString(Object? v) => v == null ? null : (v is String ? v : '$v');

int? readInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

bool? readBool(Object? v) {
  if (v is bool) return v;
  if (v == 'true') return true;
  if (v == 'false') return false;
  return null;
}

Map<String, dynamic>? readMap(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry('$k', value)) : null;

Map<String, String>? readStringMap(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry('$k', '$value')) : null;

List<String>? readStringList(Object? v) => v is List
    ? [
        for (final e in v)
          if (e != null) '$e'
      ]
    : null;

T? readObject<T>(Object? v, T Function(Map<String, dynamic>) fromJson) =>
    v is Map ? fromJson(readMap(v)!) : null;

List<T>? readObjectList<T>(Object? v, T Function(Map<String, dynamic>) fromJson) => v is List
    ? [
        for (final e in v)
          if (e is Map) fromJson(readMap(e)!)
      ]
    : null;
