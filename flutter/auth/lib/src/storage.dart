import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the serialized [TokenSet] (one JSON string per
/// `lowco:tokens:<tenantId>:<clientId>` key).
abstract class TokenStorage {
  /// Returns the stored value for [key], or `null` when absent.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// Default storage: the platform keystore via `flutter_secure_storage`
/// (Keychain on iOS/macOS, Keystore-backed storage on Android, libsecret on
/// Linux, DPAPI on Windows). On web `flutter_secure_storage` keeps a
/// WebCrypto-encrypted value in `localStorage`, which is no stronger than
/// ordinary browser storage.
class SecureTokenStorage implements TokenStorage {
  /// Uses [storage], or a default-configured `FlutterSecureStorage()`.
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Process-local storage (the TS SDK's `cacheLocation: "memory"`): the user
/// signs in again after every app restart. Handy in tests.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([Map<String, String>? initialValues]) : values = {...?initialValues};

  /// The current contents, exposed for inspection in tests.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
