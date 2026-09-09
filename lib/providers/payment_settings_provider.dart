import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';

/// Operational GCash/payment settings for the POS flow.
///
/// This provider is deliberately separate from the full [settingsProvider]
/// because Staff can read the operational payment rules without receiving
/// sensitive store configuration (e.g. Groq API keys).
final paymentSettingsProvider = FutureProvider<PaymentSettings>((ref) async {
  final settingsService = ref.watch(settingsServiceProvider);
  return settingsService.getPaymentSettings();
});

/// Decoded content of the merchant payment QR stored at the given relative
/// image path. The result is cached per path so reopening the GCash payment
/// screen does not decode the image again.
final paymentQrDecodeProvider =
    FutureProvider.family<DecodedPaymentQr, String?>((ref, imagePath) async {
  if (imagePath == null || imagePath.isEmpty) {
    return const DecodedPaymentQr.notDetected();
  }
  return ref.watch(paymentQrServiceProvider).decodePaymentQr(imagePath);
});
