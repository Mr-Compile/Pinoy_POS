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
  final String? gcashQrPreviewPath;

  /// Merchant name shown on the GCash payment screen.
  final String storeName;

  /// Merchant contact number shown on the GCash payment screen.
  final String storePhone;

  const PaymentSettings({
    required this.gcashEnabled,
    required this.gcashReferenceRequired,
    required this.gcashCustomerNameRequirement,
    required this.gcashPaymentProofRequirement,
    required this.gcashVerificationMode,
    required this.gcashReferenceMinLength,
    this.gcashQrImagePath,
    this.gcashQrImageType,
    this.gcashQrPreviewPath,
    this.storeName = 'Pinoy POS',
    this.storePhone = '',
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
      gcashQrPreviewPath: settings.gcashQrPreviewPath,
      storeName: settings.storeName.isNotEmpty ? settings.storeName : 'Pinoy POS',
      storePhone: settings.storePhone,
    );
  }

  /// Whether the customer name is required at checkout.
  ///
  /// Although the backing column is named `gcash_customer_name_requirement`
  /// for historical reasons, this rule is enforced for every payment method
  /// so the setting controls the POS consistently.
  bool get customerNameRequired => gcashCustomerNameRequirement == 'required';

  /// Whether the customer name field should be shown at checkout.
  bool get customerNameVisible => gcashCustomerNameRequirement != 'off';

  bool get paymentProofRequired => gcashPaymentProofRequirement == 'required';
  bool get paymentProofVisible => gcashPaymentProofRequirement != 'off';

  /// Whether Staff-tendered GCash payments must be verified before the sale
  /// is finalized. The Owner's own sales are never held for verification —
  /// see [PaymentVerificationService.requiresVerificationFor].
  bool get verificationRequired => gcashVerificationMode != 'immediate';

  /// Whether a System Admin is an authorized verifier under the configured
  /// mode. Admin verification has been removed; only the Owner may verify
  /// Staff-tendered GCash payments.
  bool get adminCanVerify => false;
}
