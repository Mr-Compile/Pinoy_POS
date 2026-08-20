import 'package:pinoy_pos/core/constants.dart';

/// Five user-facing password strength levels, ordered from weakest to
/// strongest.
enum PasswordStrengthLevel {
  veryWeak,
  weak,
  fair,
  good,
  strong;

  /// Human-readable label displayed in the UI.
  String get label => switch (this) {
        PasswordStrengthLevel.veryWeak => 'Very Weak',
        PasswordStrengthLevel.weak => 'Weak',
        PasswordStrengthLevel.fair => 'Fair',
        PasswordStrengthLevel.good => 'Good',
        PasswordStrengthLevel.strong => 'Strong',
      };

  /// Numeric score 0–4 used by the strength meter bar.
  int get score => switch (this) {
        PasswordStrengthLevel.veryWeak => 0,
        PasswordStrengthLevel.weak => 1,
        PasswordStrengthLevel.fair => 2,
        PasswordStrengthLevel.good => 3,
        PasswordStrengthLevel.strong => 4,
      };

  /// Whether this level meets the application's minimum acceptable
  /// password policy.  VERY WEAK and WEAK are always rejected.
  bool get isAcceptable =>
      this == PasswordStrengthLevel.good ||
      this == PasswordStrengthLevel.strong;
}

/// Result of a password strength evaluation.
class PasswordStrengthResult {
  final PasswordStrengthLevel level;
  final String guidance;

  /// Individual requirement checks for the UI checklist.
  final bool meetsMinLength;
  final bool notCommonPassword;
  final bool doesNotContainUsername;
  final bool isStrongEnough;

  PasswordStrengthResult({
    required this.level,
    required this.guidance,
    required this.meetsMinLength,
    required this.notCommonPassword,
    required this.doesNotContainUsername,
    required this.isStrongEnough,
  });

  /// Whether the password can be submitted.
  bool get isAcceptable => level.isAcceptable && isStrongEnough;
}

/// Centralized password strength evaluator.
///
/// This service owns all password-strength business logic.  The UI
/// displays the result; it never computes strength independently.
///
/// Evaluation factors (weighted):
///   - Length (strong weight)
///   - Common / known weak passwords (strong penalty)
///   - Username inclusion (strong penalty)
///   - Repeated characters (moderate penalty)
///   - Obvious sequences (moderate penalty)
///   - Character variety (positive signal, but NOT sufficient alone)
///
/// IMPORTANT: A password is NOT considered secure merely because it
/// contains uppercase, lowercase, a number, and a symbol.  Length and
/// resistance to common/predictable passwords carry strong weight.
class PasswordStrengthService {
  PasswordStrengthService._();

  // ── Common / known weak passwords (offline, no network required) ──
  static const Set<String> _commonPasswords = {
    // ── Default / temporary passwords ──
    '@password123', 'password', 'password123', 'password1',
    'admin', 'admin123', 'admin1234', 'administrator',
    'owner', 'owner123', 'staff', 'staff123',
    'qwerty', 'qwerty123', 'qwertyuiop',
    '123456', '1234567', '12345678', '123456789', '1234567890',
    '0123456789', '111111', '000000', '123123', 'abc123',
    'abcd1234', 'password!', 'p@ssword', 'p@ssw0rd', 'p@ss123',
    // ── Common Filipino / POS patterns ──
    'pinoy', 'pinoy123', 'pos', 'pos123', 'store', 'store123',
    'tindahan', 'tindahan123',
    // ── Keyboard walks ──
    'asdfgh', 'asdfghjkl', 'zxcvbn', 'zxcvbnm',
    'qazwsx', 'qazwsxedc',
    // ── Simple patterns ──
    'aaaa1111', 'abcdabcd', 'letmein', 'welcome', 'welcome1',
    'monkey', 'monkey123', 'dragon', 'dragon123',
    'sunshine', 'princess', 'football', 'baseball',
    'iloveyou', 'trustno1', 'superman', 'batman',
  };

  // ── Obvious keyboard / numeric sequences ──
  static const List<String> _sequences = [
    'abcdefghijklmnopqrstuvwxyz',
    'qwertyuiopasdfghjklzxcvbnm',
    '1234567890',
    '0987654321',
  ];

  /// Evaluates the strength of [password].
  ///
  /// If [username] is provided, the password is checked for username
  /// inclusion.  If [currentPassword] is provided, the password is
  /// checked against the old password (must not be the same).
  static PasswordStrengthResult evaluate({
    required String password,
    String? username,
    String? currentPassword,
  }) {
    final pwd = password;
    final pwdLower = pwd.toLowerCase();

    // ── Requirement checks ──
    final meetsMinLength =
        pwd.length >= AppConstants.minPasswordLength;
    final notCommonPassword = !_commonPasswords.contains(pwdLower);
    final doesNotContainUsername = username == null ||
        username.isEmpty ||
        !pwdLower.contains(username.toLowerCase());

    // ── Penalties (each reduces the score) ──
    int penalties = 0;

    // Common password — severe penalty.
    if (!notCommonPassword) {
      penalties += 3;
    }

    // Contains username — severe penalty.
    if (!doesNotContainUsername) {
      penalties += 2;
    }

    // Same as current password — severe penalty.
    if (currentPassword != null &&
        currentPassword.isNotEmpty &&
        pwd == currentPassword) {
      penalties += 3;
    }

    // Repeated characters (e.g. "aaaaaa", "111111").
    if (_hasRepeatedChars(pwdLower)) {
      penalties += 1;
    }

    // Obvious sequence (e.g. "abcdef", "123456", "qwerty").
    if (_hasSequence(pwdLower)) {
      penalties += 2;
    }

    // Too short — severe penalty.
    if (pwd.length < AppConstants.minPasswordLength) {
      penalties += 2;
    } else if (pwd.length < 10) {
      // 8–9 chars: minor penalty (meets minimum but not generous).
      penalties += 1;
    }

    // ── Positive signals ──
    int positives = 0;

    // Length bonus.
    if (pwd.length >= 12) positives += 1;
    if (pwd.length >= 16) positives += 1;
    if (pwd.length >= 20) positives += 1;

    // Character variety (positive signal, but NOT sufficient alone).
    final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
    final hasLower = pwd.contains(RegExp(r'[a-z]'));
    final hasDigit = pwd.contains(RegExp(r'[0-9]'));
    final hasSymbol = pwd.contains(RegExp(r'[^a-zA-Z0-9]'));

    final varietyCount =
        [hasUpper, hasLower, hasDigit, hasSymbol].where((b) => b).length;
    if (varietyCount >= 3) positives += 1;
    if (varietyCount == 4) positives += 1;

    // ── Calculate final score ──
    // Base score starts at 2 (fair) and is adjusted by penalties and
    // positives.  Clamped to [0, 4].
    int score = 2 - penalties + positives;
    score = score.clamp(0, 4);

    final level = PasswordStrengthLevel.values[score];

    // ── Guidance message ──
    String guidance;
    if (pwd.isEmpty) {
      guidance = 'Enter a password.';
    } else if (!meetsMinLength) {
      guidance = 'Use at least ${AppConstants.minPasswordLength} characters.';
    } else if (!notCommonPassword) {
      guidance = 'This password is too common. Choose a less predictable password.';
    } else if (!doesNotContainUsername) {
      guidance = 'Your password should not contain your username.';
    } else if (_hasRepeatedChars(pwdLower)) {
      guidance = 'Avoid repeated characters.';
    } else if (_hasSequence(pwdLower)) {
      guidance = 'Avoid predictable sequences like "abc" or "123".';
    } else if (level == PasswordStrengthLevel.fair) {
      guidance = 'Add more length to make your password stronger.';
    } else if (level == PasswordStrengthLevel.good) {
      guidance = 'Good password. Consider adding more length for extra security.';
    } else if (level == PasswordStrengthLevel.strong) {
      guidance = 'Strong password.';
    } else {
      guidance = 'Choose a stronger password.';
    }

    final isStrongEnough = level.isAcceptable;

    return PasswordStrengthResult(
      level: level,
      guidance: guidance,
      meetsMinLength: meetsMinLength,
      notCommonPassword: notCommonPassword,
      doesNotContainUsername: doesNotContainUsername,
      isStrongEnough: isStrongEnough,
    );
  }

  /// Validates a password for submission.  Returns null if valid,
  /// or a human-readable error message.
  ///
  /// This is the single validation entry point used by:
  ///   - Forced first-login password change
  ///   - Normal change password
  ///   - Admin password reset (when a custom password is used)
  static String? validate({
    required String password,
    String? username,
    String? currentPassword,
  }) {
    if (password.isEmpty) {
      return 'Password is required';
    }
    if (password.length < AppConstants.minPasswordLength) {
      return 'Password must be at least ${AppConstants.minPasswordLength} characters';
    }
    if (password.length > AppConstants.maxPasswordLength) {
      return 'Password must not exceed ${AppConstants.maxPasswordLength} characters';
    }

    final result = evaluate(
      password: password,
      username: username,
      currentPassword: currentPassword,
    );

    if (!result.isAcceptable) {
      return result.guidance;
    }

    return null;
  }

  /// Returns true if [password] contains 3+ consecutive identical
  /// characters (e.g. "aaa", "111").
  static bool _hasRepeatedChars(String password) {
    if (password.length < 3) return false;
    for (int i = 0; i <= password.length - 3; i++) {
      if (password[i] == password[i + 1] && password[i] == password[i + 2]) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if [password] contains a sequence of 4+ consecutive
  /// characters from a known sequence (alphabetical, numeric, keyboard).
  static bool _hasSequence(String password) {
    if (password.length < 4) return false;
    for (final seq in _sequences) {
      for (int i = 0; i <= seq.length - 4; i++) {
        final sub = seq.substring(i, i + 4);
        if (password.contains(sub)) {
          return true;
        }
      }
    }
    return false;
  }
}
