import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/decoded_payment_qr.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/providers/service_providers.dart';

/// Operational GCash/payment settings for the POS flow.
///
/// This provider is deliberately separate from the full [settingsProvider]
/// because Staff can read the operational payment rules without receiving
/// sensitive store configuration (e.g. Groq API keys). Access is limited to
/// `create_sales` (Owner/Staff) and `verify_payments` (Owner); System Admin
/// cannot read the Owner's payment configuration.
final paymentSettingsProvider = FutureProvider<PaymentSettings>((ref) async {
  final settingsService = ref.watch(settingsServiceProvider);
  return settingsService.getPaymentSettings();
});

/// Decoded content of the merchant payment QR stored at the given relative
/// image path.
///
/// The payload is persisted on the settings row at upload time (or lazily
/// on first open for QRs uploaded before the cache existed), so repeat
/// opens parse a stored string instead of image-decoding the QR again.
/// The Riverpod family cache is only an in-memory layer on top.
final paymentQrDecodeProvider =
    FutureProvider.family<DecodedPaymentQr, String?>((ref, imagePath) async {
  return ref.watch(settingsServiceProvider).getDecodedPaymentQr(imagePath);
});
