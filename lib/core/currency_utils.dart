import 'package:intl/intl.dart';

/// Formatting and symbol helpers for the store currency.
///
/// The default fallback is PHP (Philippine Peso) so callers that do not
/// know the configured currency still produce a sensible display.
class CurrencyUtils {
  CurrencyUtils._();

  /// Formats [amount] with the correct currency symbol and two decimals.
  static String format(
    double amount, {
    String? currency,
    int decimalDigits = 2,
  }) {
    final code = currency ?? 'PHP';
    final formatter = NumberFormat.simpleCurrency(
      name: code,
      decimalDigits: decimalDigits,
    );
    return formatter.format(amount);
  }

  /// Formats [amount] as an integer currency value (no decimals).
  static String formatWhole(
    double amount, {
    String? currency,
  }) {
    return format(amount, currency: currency, decimalDigits: 0);
  }

  /// Returns the currency symbol for [currency].
  static String symbol({String? currency}) {
    final code = currency ?? 'PHP';
    final formatter = NumberFormat.simpleCurrency(
      name: code,
      decimalDigits: 0,
    );
    if (formatter.currencySymbol.isNotEmpty &&
        formatter.currencySymbol != code) {
      return formatter.currencySymbol;
    }
    if (code == 'PHP') return '₱';
    return code;
  }

  /// Returns a plain string like "₱1,234.50" from a raw amount string,
  /// preserving the number and replacing the leading symbol.
  static String fromNumber(
    num amount, {
    String? currency,
    int decimalDigits = 2,
  }) {
    return format(amount.toDouble(), currency: currency, decimalDigits: decimalDigits);
  }
}
