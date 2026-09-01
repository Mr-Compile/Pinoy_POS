import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A thin wrapper around [FlutterSecureStorage] for sensitive values.
///
/// Currently used for the Groq API key so it is never stored in the
/// SQLite settings table as plain text.
class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> delete({required String key}) => _storage.delete(key: key);
}
