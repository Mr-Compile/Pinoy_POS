import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Result of an at-till verifier authentication attempt.
class VerifierAuthResult {
  /// The authenticated verifier, present only when [isSuccess] is true.
  final User? verifier;

  /// Human-readable error shown to the operator when authentication fails.
  final String? error;

  const VerifierAuthResult._({this.verifier, this.error});

  factory VerifierAuthResult.success(User verifier) =>
      VerifierAuthResult._(verifier: verifier);

  factory VerifierAuthResult.failure(String error) =>
      VerifierAuthResult._(error: error);

  bool get isSuccess => verifier != null;
}

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
/// - The Owner is always an authorized verifier. A System Admin is an
///   authorized verifier only when the policy allows it
///   ([PaymentSettings.adminCanVerify]).
class PaymentVerificationService {
  final SettingsService _settingsService = SettingsService();
  final SessionManager _sessionManager = SessionManager();
  final UserRepository _userRepository = UserRepository();

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
  /// The Owner can always verify while verification is enabled. A System
  /// Admin can verify only when the configured policy includes them.
  bool canRoleVerify(UserRole? role, PaymentSettings settings) {
    if (!settings.verificationRequired) return false;
    if (role == UserRole.owner) return true;
    if (role == UserRole.admin) return settings.adminCanVerify;
    return false;
  }

  /// Whether the current user is allowed to confirm or reject a pending
  /// GCash payment (the legacy verification queue on the sale detail
  /// screen). Requires both the `verify_payments` permission and a role
  /// that [canRoleVerify] accepts.
  Future<bool> currentUserCanVerify() async {
    if (!_sessionManager.hasPermission('verify_payments')) return false;
    final settings = await _settingsService.getPaymentSettings();
    return canRoleVerify(_sessionManager.currentUser?.role, settings);
  }

  /// Authenticates a verifier by username and password **without** changing
  /// the current session.
  ///
  /// Used at the point of sale: an authorized verifier physically approves a
  /// Staff-tendered GCash payment by entering their own credentials.
  ///
  /// Returns [VerifierAuthResult] — success carries the verifier [User] so
  /// the sale can record `verified_by`. Failure carries a message that is
  /// safe to show the operator (it never reveals which part failed for
  /// credential errors).
  Future<VerifierAuthResult> authenticateVerifier({
    required String username,
    required String password,
    PaymentSettings? settings,
  }) async {
    final resolved =
        settings ?? await _settingsService.getPaymentSettings();

    if (!resolved.verificationRequired) {
      return VerifierAuthResult.failure(
        'GCash payment verification is currently disabled.',
      );
    }

    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty || password.isEmpty) {
      return VerifierAuthResult.failure(
        'Enter the verifier\'s username and password.',
      );
    }

    const invalidCredentials = 'Incorrect username or password.';

    final user = await _userRepository.getByUsername(trimmedUsername);
    if (user == null || !user.isActive || user.isDeleted) {
      return VerifierAuthResult.failure(invalidCredentials);
    }

    if (!SecurityHelper.verifyPassword(password, user.passwordHash)) {
      return VerifierAuthResult.failure(invalidCredentials);
    }

    if (user.id != null && user.id == _sessionManager.currentUser?.id) {
      return VerifierAuthResult.failure(
        'The operator cannot verify their own sale.',
      );
    }

    if (!canRoleVerify(user.role, resolved)) {
      return VerifierAuthResult.failure(
        'This account is not authorized to verify GCash payments.',
      );
    }

    return VerifierAuthResult.success(user);
  }
}
