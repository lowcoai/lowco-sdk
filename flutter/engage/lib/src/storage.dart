import 'package:shared_preferences/shared_preferences.dart';

/// Key/value persistence used by [LowcoAnalytics] for the device id, the
/// session and first-touch attribution.
///
/// The keys are the same `localStorage` keys the browser SDK uses:
/// `lowco_uuid`, `lowco_session_id`, `lowco_session_last_event` and
/// `lowco_first_touch`.
abstract class EngageStorage {
  /// Returns the stored value for [key], or `null` when absent.
  Future<String?> getString(String key);

  /// Stores [value] under [key].
  Future<void> setString(String key, String value);

  /// Removes [key].
  Future<void> remove(String key);
}

/// Default storage backed by `package:shared_preferences`
/// (`NSUserDefaults`, Android `SharedPreferences`, `localStorage` on web).
///
/// Call `WidgetsFlutterBinding.ensureInitialized()` before
/// `LowcoAnalytics.instance.init(...)` when initializing ahead of `runApp`.
class SharedPreferencesEngageStorage implements EngageStorage {
  SharedPreferencesEngageStorage();

  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> get _instance => _prefs ??= SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async => (await _instance).getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await (await _instance).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _instance).remove(key);
  }
}

/// Process-local storage: nothing survives an app restart. Useful in tests
/// or when persistence is not wanted.
class InMemoryEngageStorage implements EngageStorage {
  InMemoryEngageStorage([Map<String, String>? initialValues]) : values = {...?initialValues};

  /// The current contents, exposed for inspection in tests.
  final Map<String, String> values;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
