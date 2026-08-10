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
