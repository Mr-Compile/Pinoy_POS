import 'package:pinoy_pos/core/app_security_constants.dart';

/// Verifies a SuperAdmin authorization string for protected quota actions.
///
/// This is deliberately separate from user login credentials. It is used only
/// inside the AI quota management flow to authorize changes that affect all
/// users. The password itself is never logged, displayed, or returned.
class SuperAdminVerificationService {
  /// Returns true when [password] matches the protected SuperAdmin secret.
  ///
  /// The comparison is exact and case-sensitive. Never log [password].
  bool verifySuperAdminPassword(String password) {
    return password == AppSecurityConstants.superAdminPassword;
  }
}
