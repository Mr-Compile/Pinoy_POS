import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Central authority for GCash payment verification rules.
///
/// The policy distinguishes two roles:
///
/// - **Operator** — the logged-in user tendering the sale at POS.
/// - **Verifier** — a user authorized to approve a Staff-tendered GCash
///   payment before the sale is finalized.
///
/// Rules:
/// - Verification only applies to GCash payments.
/// - The Owner never requires verification for their own sale — the Owner
///   is the highest authorized operational role.
/// - Any other operator (e.g. Staff) requires verification only when
///   [PaymentSettings.verificationRequired] is enabled.
/// - The Owner is always the only authorized verifier. System Admins may not
///   verify GCash payments.
class PaymentVerificationService {
  final SettingsService _settingsService = SettingsService();
  final SessionManager _sessionManager = SessionManager();

  /// Whether a [paymentMethod] payment tendered by an operator with
  /// [operatorRole] requires verification under [settings].
  ///
  /// This is a pure policy check: the Owner is always exempt, and
  /// verification only applies to GCash.
  bool requiresVerificationFor({
    required UserRole? operatorRole,
    required String paymentMethod,
    required PaymentSettings settings,
  }) {
    if (paymentMethod != 'GCash') return false;
    if (operatorRole == null) return false;
    if (operatorRole == UserRole.owner) return false;
    return settings.verificationRequired;
  }

  /// Whether the currently logged-in operator's [paymentMethod] payment
  /// requires verification. Loads settings when [settings] is not provided.
  Future<bool> requiresVerification({
    required String paymentMethod,
    PaymentSettings? settings,
  }) async {
    final resolved =
        settings ?? await _settingsService.getPaymentSettings();
    return requiresVerificationFor(
      operatorRole: _sessionManager.currentUser?.role,
      paymentMethod: paymentMethod,
      settings: resolved,
    );
  }

  /// Whether a user with [role] is an authorized verifier under [settings].
  ///
  /// The Owner is the only user who can verify Staff-tendered GCash payments
  /// while verification is enabled.
  bool canRoleVerify(UserRole? role, PaymentSettings settings) {
    if (!settings.verificationRequired) return false;
    if (role == UserRole.owner) return true;
    return false;
  }

  /// Whether the current user is allowed to confirm or reject a pending
  /// GCash payment on the sale detail screen. Requires both the
  /// `verify_payments` permission and a role that [canRoleVerify] accepts.
  Future<bool> currentUserCanVerify() async {
    if (!_sessionManager.hasPermission('verify_payments')) return false;
    final settings = await _settingsService.getPaymentSettings();
    return canRoleVerify(_sessionManager.currentUser?.role, settings);
  }
}
