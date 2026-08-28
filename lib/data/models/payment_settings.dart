import 'package:pinoy_pos/data/models/settings.dart';

/// Operational payment/GCash settings exposed to users who can create sales
/// (e.g. Staff) without leaking full store configuration such as API keys.
class PaymentSettings {
  final bool gcashEnabled;
  final bool gcashReferenceRequired;
  final String gcashCustomerNameRequirement;
  final String gcashPaymentProofRequirement;
  final String gcashVerificationMode;
  final int gcashReferenceMinLength;

  const PaymentSettings({
    required this.gcashEnabled,
    required this.gcashReferenceRequired,
    required this.gcashCustomerNameRequirement,
    required this.gcashPaymentProofRequirement,
    required this.gcashVerificationMode,
    required this.gcashReferenceMinLength,
  });

  factory PaymentSettings.fromSettings(Settings settings) {
    return PaymentSettings(
      gcashEnabled: settings.gcashEnabled,
      gcashReferenceRequired: settings.gcashReferenceRequired,
      gcashCustomerNameRequirement: settings.gcashCustomerNameRequirement,
      gcashPaymentProofRequirement: settings.gcashPaymentProofRequirement,
      gcashVerificationMode: settings.gcashVerificationMode,
      gcashReferenceMinLength: settings.gcashReferenceMinLength,
    );
  }

  bool get customerNameRequired => gcashCustomerNameRequirement == 'required';
  bool get customerNameVisible => gcashCustomerNameRequirement != 'off';

  bool get paymentProofRequired => gcashPaymentProofRequirement == 'required';
  bool get paymentProofVisible => gcashPaymentProofRequirement != 'off';

  bool get verificationRequired => gcashVerificationMode == 'owner_admin';
}
