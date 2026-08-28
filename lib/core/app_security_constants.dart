/// Centralized, scope-limited protected configuration.
///
/// The SuperAdmin password is used ONLY for AI quota administration.
/// It is not used for user authentication, login, backup encryption, or
/// any other security-sensitive operation. It is never displayed in the UI
/// and must never be logged.
class AppSecurityConstants {
  AppSecurityConstants._();

  static const String superAdminPassword = 'SuperAdmin';
}
