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
  final String? gcashQrImagePath;
  final String? gcashQrImageType;

  const PaymentSettings({
    required this.gcashEnabled,
    required this.gcashReferenceRequired,
    required this.gcashCustomerNameRequirement,
    required this.gcashPaymentProofRequirement,
    required this.gcashVerificationMode,
    required this.gcashReferenceMinLength,
    this.gcashQrImagePath,
    this.gcashQrImageType,
  });

  factory PaymentSettings.fromSettings(Settings settings) {
    return PaymentSettings(
      gcashEnabled: settings.gcashEnabled,
      gcashReferenceRequired: settings.gcashReferenceRequired,
      gcashCustomerNameRequirement: settings.gcashCustomerNameRequirement,
      gcashPaymentProofRequirement: settings.gcashPaymentProofRequirement,
      gcashVerificationMode: settings.gcashVerificationMode,
      gcashReferenceMinLength: settings.gcashReferenceMinLength,
      gcashQrImagePath: settings.gcashQrImagePath,
      gcashQrImageType: settings.gcashQrImageType,
    );
  }

  bool get customerNameRequired => gcashCustomerNameRequirement == 'required';
  bool get customerNameVisible => gcashCustomerNameRequirement != 'off';

  bool get paymentProofRequired => gcashPaymentProofRequirement == 'required';
  bool get paymentProofVisible => gcashPaymentProofRequirement != 'off';

  /// Whether Staff-tendered GCash payments must be verified before the sale
  /// is finalized. The Owner's own sales are never held for verification —
  /// see [PaymentVerificationService.requiresVerificationFor].
  bool get verificationRequired => gcashVerificationMode != 'immediate';

  /// Whether a System Admin is an authorized verifier under the configured
  /// mode. The Owner is always an authorized verifier while verification is
  /// enabled. The legacy 'admin' mode is treated as 'owner_admin' because
  /// an Admin-only configuration would leave sales unverifiable (the Owner
  /// must always retain the ability to verify).
  bool get adminCanVerify =>
      gcashVerificationMode == 'admin' ||
      gcashVerificationMode == 'owner_admin';
}
