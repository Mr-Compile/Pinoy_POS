import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Resets [FlutterSecureStorage] to an in-memory, empty store for the
/// duration of a test. This keeps session metadata and AI keys isolated
/// between tests and avoids writing real DPAPI-encrypted files on Windows.
class SecureStorageTestHelper {
  static final Map<String, String> _store = {};

  /// Call from a test's `setUp` before any code that may read or write
  /// secure storage.
  static void setUp() {
    _store.clear();
    FlutterSecureStorage.setMockInitialValues(_store);
  }
}
