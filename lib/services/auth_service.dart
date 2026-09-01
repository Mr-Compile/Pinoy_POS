import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a post-login PIN verification attempt.
enum PinVerifyResult {
  success,
  incorrect,
  inactive,
  userDeleted,
  userNotFound,
  noPin,
  noSession,
}

/// Result of a login attempt.
///
/// Allows the UI to show differentiated error messages instead of a
/// generic "invalid credentials" for every failure.
enum LoginResult {
  success,
  invalidCredentials,
  inactiveAccount,
  error,
}

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

  Future<LoginResult> login(String username, String password) async {
    try {
      final user = await _userRepository.getByUsername(username);

      if (user == null) {
        return LoginResult.invalidCredentials;
      }

      if (!user.isActive) {
        return LoginResult.inactiveAccount;
      }

      if (!SecurityHelper.verifyPassword(password, user.passwordHash)) {
        return LoginResult.invalidCredentials;
      }

      _sessionManager.setCurrentUser(user);
      await _userRepository.updateLastLogin(user.id!);
      await _saveSession(user.id!);

      return LoginResult.success;
    } catch (_) {
      return LoginResult.error;
    }
  }

  Future<bool> loginWithPin(String username, String pin) async {
    final user = await _userRepository.getByUsername(username);

    if (user == null || user.pin == null) {
      return false;
    }

    if (!user.isActive || user.isDeleted) {
      return false;
    }

    if (!SecurityHelper.verifyPin(pin, user.pin!)) {
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

  /// Verifies a PIN for the post-login PIN lock flow.
  /// The user must already be authenticated via password and set in
  /// the SessionManager.  Returns a [PinVerifyResult] indicating
  /// success, incorrect PIN, inactive account, deleted account, or
  /// configuration error.
  Future<PinVerifyResult> verifyPin(String pin) async {
    final current = _sessionManager.currentUser;
    if (current == null) {
      return PinVerifyResult.noSession;
    }

    // Re-fetch the user to get the latest state from the database.
    final user = await _userRepository.getById(current.id!);
    if (user == null) {
      return PinVerifyResult.userNotFound;
    }

    if (user.isDeleted) {
      return PinVerifyResult.userDeleted;
    }

    if (!user.isActive) {
      return PinVerifyResult.inactive;
    }

    if (user.pin == null || user.pin!.isEmpty) {
      return PinVerifyResult.noPin;
    }

    if (!SecurityHelper.verifyPin(pin, user.pin!)) {
      return PinVerifyResult.incorrect;
    }

    // PIN is correct — update the session with the fresh user data.
    _sessionManager.setCurrentUser(user);
    return PinVerifyResult.success;
  }

  /// Returns the configured PIN length for the current user, or 0
  /// if no PIN is set.
  int get currentPinLength {
    final user = _sessionManager.currentUser;
    if (user == null || !user.hasPin) return 0;
    return user.configuredPinLength;
  }

  /// Whether the current authenticated user has a PIN configured.
  bool get currentUserHasPin {
    final user = _sessionManager.currentUser;
    return user != null && user.hasPin;
  }

  /// Updates the current user's own profile (full name, username, PIN,
  /// profile image). No special permission is required - users can always
  /// edit their own profile. Restricted fields (role, isActive) are never
  /// modified here.
  ///
  /// If [pin] is null, the existing PIN is preserved.  If [pin] is an
  /// empty string, the PIN is cleared.  Otherwise the PIN is hashed
  /// before storage.
  ///
  /// Returns true on success, false on failure.
  Future<bool> updateProfile({
    required int userId,
    required String fullName,
    String? username,
    String? pin,
    String? profileImagePath,
  }) async {
    final current = _sessionManager.currentUser;
    if (current == null || current.id != userId) {
      return false;
    }

    final trimmedUsername = (username ?? current.username).trim();
    if (trimmedUsername.isEmpty) {
      return false;
    }

    // Check username uniqueness if it is being changed.
    if (trimmedUsername != current.username) {
      final existing = await _userRepository.getByUsername(trimmedUsername);
      if (existing != null && existing.id != userId) {
        return false;
      }
    }

    // Determine the new PIN value and length.
    // If pin is null, keep the existing PIN.  If pin is an empty
    // string, clear the PIN.  Otherwise, hash the new PIN.
    String? newPin;
    int? newPinLength;
    if (pin == null) {
      newPin = current.pin;
      newPinLength = current.pinLength;
    } else if (pin.isEmpty) {
      newPin = null;
      newPinLength = null;
    } else {
      newPin = SecurityHelper.hashPin(pin);
      newPinLength = pin.length;
    }

    final updated = current.copyWith(
      username: trimmedUsername,
      fullName: fullName,
      pin: newPin,
      pinLength: newPinLength,
      profileImagePath: profileImagePath ?? current.profileImagePath,
      updatedAt: DateTime.now(),
    );

    await _userRepository.update(updated);
    _sessionManager.setCurrentUser(updated);
    return true;
  }
}
