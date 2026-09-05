import 'dart:convert';

import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/session_metadata.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/secure_storage_service.dart';
import 'package:pinoy_pos/services/session_settings_service.dart';
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
  final SessionSettingsService _sessionSettingsService = SessionSettingsService();
  final SecureStorageService _secureStorage = SecureStorageService();
  static const String _sessionKey = 'user_session';
  static const String _sessionTokenKey = 'session_token';

  SessionMetadata? _currentMetadata;

  AuthService();

  User? get currentUser => _sessionManager.currentUser;
  bool get isAuthenticated => _sessionManager.isAuthenticated;
  SessionMetadata? get currentSessionMetadata => _currentMetadata;

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
      await _createSession(user);

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
    await _saveSession(user, pinVerified: true);

    return true;
  }

  Future<void> logout() async {
    _sessionManager.clearCurrentUser();
    _currentMetadata = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await _secureStorage.delete(key: _sessionTokenKey);
  }

  Future<SessionStatus> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionKey);

    if (userId == null) {
      return SessionStatus.none;
    }

    final metadata = await _loadSessionMetadata();
    if (metadata == null || metadata.userId != userId) {
      await logout();
      return SessionStatus.none;
    }

    final user = await _userRepository.getById(userId);
    if (user == null || !user.isActive || user.isDeleted) {
      await logout();
      return SessionStatus.expired;
    }

    _currentMetadata = metadata;
    _sessionManager.setCurrentUser(user);

    final now = DateTime.now();
    if (now.isAfter(metadata.sessionExpiresAt)) {
      await logout();
      return SessionStatus.expired;
    }

    final inactivityTimeout =
        await _sessionSettingsService.getEffectiveInactivityTimeout(user);
    final inactivityExpired =
        now.difference(metadata.lastActivityAt) > inactivityTimeout;

    if (inactivityExpired) {
      if (user.hasPin) {
        return SessionStatus.locked;
      }
      await logout();
      return SessionStatus.expired;
    }

    if (metadata.pinVerified || !user.hasPin) {
      return SessionStatus.active;
    }
    return SessionStatus.locked;
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

  /// Starts a new persisted session for [user] with a fresh 8-hour expiry.
  Future<void> _createSession(User user) async {
    final now = DateTime.now();
    final metadata = SessionMetadata(
      userId: user.id!,
      sessionExpiresAt: now.add(SessionSettingsService.maxSessionLifetime),
      lastActivityAt: now,
      pinVerified: !user.hasPin,
    );

    _currentMetadata = metadata;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, user.id!);
    await _persistSessionMetadata(metadata);
  }

  /// Updates the last activity timestamp on the existing persisted session.
  Future<void> _saveSession(User user, {bool? pinVerified}) async {
    final now = DateTime.now();
    final existing = _currentMetadata;
    final expiresAt = existing?.sessionExpiresAt ??
        now.add(SessionSettingsService.maxSessionLifetime);

    final metadata = SessionMetadata(
      userId: user.id!,
      sessionExpiresAt: expiresAt,
      lastActivityAt: now,
      pinVerified: pinVerified ?? existing?.pinVerified ?? !user.hasPin,
    );

    _currentMetadata = metadata;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, user.id!);
    await _persistSessionMetadata(metadata);
  }

  Future<SessionMetadata?> _loadSessionMetadata() async {
    final raw = await _secureStorage.read(key: _sessionTokenKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SessionMetadata.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSessionMetadata(SessionMetadata metadata) async {
    await _secureStorage.write(
      key: _sessionTokenKey,
      value: _encodeMetadata(metadata),
    );
  }

  String _encodeMetadata(SessionMetadata metadata) {
    return jsonEncode(metadata.toMap());
  }

  /// Updates the last activity timestamp on the persisted session.
  ///
  /// Called by [SessionTimeoutService] after the inactivity timer resets.
  /// The write is intentionally throttled by the caller.
  Future<void> touchSession(DateTime lastActivityAt) async {
    final metadata = _currentMetadata;
    if (metadata == null) return;
    final updated = metadata.copyWith(lastActivityAt: lastActivityAt);
    _currentMetadata = updated;
    await _persistSessionMetadata(updated);
  }

  /// Updates the PIN-verified flag on the persisted session.
  Future<void> setPinVerified(bool value) async {
    final metadata = _currentMetadata;
    if (metadata == null) return;
    final updated = metadata.copyWith(pinVerified: value);
    _currentMetadata = updated;
    await _persistSessionMetadata(updated);
  }

  Future<void> _markPinVerified(User user) async {
    final metadata = _currentMetadata;
    if (metadata == null) return;
    final updated = metadata.copyWith(
      pinVerified: true,
      lastActivityAt: DateTime.now(),
    );
    _currentMetadata = updated;
    await _persistSessionMetadata(updated);
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
    await _markPinVerified(user);
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

    // Enforce the one-time username change rule.
    final isChangingUsername = trimmedUsername != current.username;
    if (isChangingUsername && current.hasChangedUsername) {
      return false;
    }

    // Check username uniqueness if it is being changed.
    if (isChangingUsername) {
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
      hasChangedUsername: current.hasChangedUsername || isChangingUsername,
      updatedAt: DateTime.now(),
    );

    await _userRepository.update(updated);
    _sessionManager.setCurrentUser(updated);
    return true;
  }
}
