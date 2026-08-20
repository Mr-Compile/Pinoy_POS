import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class SecurityHelper {
  SecurityHelper._();

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  static bool verifyPassword(String password, String hash) {
    final passwordHash = hashPassword(password);
    return passwordHash == hash;
  }

  /// Hashes a PIN using the same SHA-256 algorithm as passwords.
  /// The PIN is never stored or compared in plaintext.
  static String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Securely verifies a PIN against a stored hash.
  /// Returns true if the PIN matches the stored hash.
  static bool verifyPin(String pin, String hash) {
    final pinHash = hashPin(pin);
    return pinHash == hash;
  }

  /// Checks whether a stored PIN value appears to be a legacy plaintext
  /// PIN (not hashed).  A SHA-256 hash is always 64 hex characters.
  /// A plaintext PIN of 4-6 digits is only 4-6 characters.
  static bool isPlaintextPin(String storedValue) {
    return storedValue.length < 64;
  }

  static String generatePin() {
    final random = Random.secure();
    return (1000 + random.nextInt(9000)).toString();
  }

  static String generateReceiptNumber() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final random = Random.secure().nextInt(9999);
    return 'RCP$timestamp$random';
  }
}
