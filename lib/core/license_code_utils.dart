import 'package:flutter/services.dart';

/// Live-formats a license code field as `XXXX-XXXX` while the user types.
///
/// Input is normalized to uppercase alphanumeric, capped at 8 characters,
/// with the dash inserted after the fourth — typing or pasting
/// `nrv27yme`, `nrv2 7yme`, or `NRV2-7YME` all land on `NRV2-7YME`.
/// Redemption normalizes the same way, so the dash is purely cosmetic.
class LicenseCodeInputFormatter extends TextInputFormatter {
  /// Alphanumeric characters in a code — 4 on each side of the dash.
  static const int codeLength = 8;

  /// Canonical display form: uppercase `XXXX-XXXX`.
  static String format(String input) {
    var chars = input.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    if (chars.length > codeLength) chars = chars.substring(0, codeLength);
    return chars.length > 4
        ? '${chars.substring(0, 4)}-${chars.substring(4)}'
        : chars;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
