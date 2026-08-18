import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication service.
///
/// Owns ONLY login / logout / session-restore logic.  User management CRUD
/// (create / update / delete / activate / deactivate / restore) has been
/// moved to [UserService] so that authentication and user management are
/// cleanly separated and cannot form a circular dependency.
///
/// The currently authenticated user is stored in the [SessionManager]
/// singleton so that other services can read it without instantiating
/// [AuthService].
class AuthService {
  final UserRepository _userRepository = UserRepository();
  final SessionManager _sessionManager = SessionManager();
  static const String _sessionKey = 'user_session';

  User? get currentUser => _sessionManager.currentUser;
  bool get isAuthenticated => _sessionManager.isAuthenticated;

  Future<bool> login(String username, String password) async {
    final user = await _userRepository.getByUsername(username);

    if (user == null) {
      return false;
    }

    if (!user.isActive) {
      return false;
    }

    if (!SecurityHelper.verifyPassword(password, user.passwordHash)) {
      return false;
    }

    _sessionManager.setCurrentUser(user);
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);

    return true;
  }

  Future<bool> loginWithPin(String username, String pin) async {
    final user = await _userRepository.getByUsername(username);

    if (user == null || user.pin == null) {
      return false;
    }

    if (!user.isActive) {
      return false;
    }

    if (user.pin != pin) {
      return false;
    }

    _sessionManager.setCurrentUser(user);
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);

    return true;
  }

  Future<void> logout() async {
    _sessionManager.clearCurrentUser();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionKey);

    if (userId == null) {
      return false;
    }

    final user = await _userRepository.getById(userId);

    if (user == null || !user.isActive || user.isDeleted) {
      await logout();
      return false;
    }

    _sessionManager.setCurrentUser(user);
    return true;
  }

  /// Reloads the current user from the database and updates the session.
  /// Called after the current user's own record is edited.
  Future<void> refreshCurrentUser() async {
    final currentId = _sessionManager.currentUser?.id;
    if (currentId == null) return;

    final user = await _userRepository.getById(currentId);
    if (user != null && user.isActive && !user.isDeleted) {
      _sessionManager.setCurrentUser(user);
    }
  }

  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }

  bool hasPermission(String permission) {
    return _sessionManager.hasPermission(permission);
  }

  /// Updates the current user's own profile (full name, PIN, color
  /// preference). No special permission is required - users can always
  /// edit their own profile. Restricted fields (role, username, isActive)
  /// are never modified here.
  ///
  /// Returns true on success, false on failure.
  Future<bool> updateProfile({
    required int userId,
    required String fullName,
    String? pin,
    String? colorPreference,
  }) async {
    final current = _sessionManager.currentUser;
    if (current == null || current.id != userId) {
      return false;
    }

    final updated = current.copyWith(
      fullName: fullName,
      pin: pin ?? current.pin,
      colorPreference: colorPreference ?? current.colorPreference,
      updatedAt: DateTime.now(),
    );

    await _userRepository.update(updated);
    _sessionManager.setCurrentUser(updated);
    return true;
  }

  /// Updates only the current user's color preference. Convenience wrapper
  /// around [updateProfile] for the color-preference picker dialog.
  Future<bool> updateColorPreference(int userId, String colorPreference) async {
    return updateProfile(
      userId: userId,
      fullName: _sessionManager.currentUser?.fullName ?? '',
      colorPreference: colorPreference,
    );
  }
}