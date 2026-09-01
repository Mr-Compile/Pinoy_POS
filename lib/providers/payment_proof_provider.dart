import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/payment_proof_service.dart';

final paymentProofServiceProvider = Provider<PaymentProofService>((ref) {
  return PaymentProofService();
});
