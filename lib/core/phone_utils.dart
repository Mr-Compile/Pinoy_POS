import 'package:flutter/services.dart';

/// Helpers for Philippine mobile numbers stored and displayed in the
/// `09XX XXX XXXX` format (11 digits, `09` prefix).
class PhoneUtils {
  PhoneUtils._();

  /// Placeholder/example shown in mobile number inputs. Deliberately a
  /// masked placeholder — never a real-looking number, so a user never
  /// mistakes the hint for their own number.
  static const String phMobileHint = '09XX XXX XXXX';

  /// Strips every non-digit character and converts a `+63`/`63` country-code
  /// prefix to the local `0` trunk prefix. The result is digits only and is
  /// not length-capped so callers can detect over-long input.
  static String normalizePhMobile(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  /// Groups the normalized digits as `09XX XXX XXXX`.
  static String formatPhMobile(String input) {
    final digits = normalizePhMobile(input);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// True when [input] is an 11-digit PH mobile number (`09XXXXXXXXX`).
  static bool isValidPhMobile(String input) {
    final digits = normalizePhMobile(input);
    return digits.length == 11 && digits.startsWith('09');
  }
}

/// Live-formats a text field as `09XX XXX XXXX` while the user types.
/// Digits only, `+63`/`63` input is normalized to `0`, capped at 11 digits.
class PhMobileInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = PhoneUtils.normalizePhMobile(newValue.text);
    if (digits.length > 11) digits = digits.substring(0, 11);

    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
