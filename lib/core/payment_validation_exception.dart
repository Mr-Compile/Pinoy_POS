/// Exception thrown when a payment fails validation before the sale is
/// persisted. The message is intended to be shown to the cashier in a
/// global error dialog.
class PaymentValidationException implements Exception {
  final String message;
  final String? details;

  PaymentValidationException(this.message, {this.details});

  @override
  String toString() => 'PaymentValidationException: $message';
}
