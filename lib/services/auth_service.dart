import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final UserRepository _userRepository = UserRepository();
  User? _currentUser;
  static const String _sessionKey = 'user_session';

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

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

    _currentUser = user;
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

    _currentUser = user;
    await _userRepository.updateLastLogin(user.id!);
    await _saveSession(user.id!);
    
    return true;
  }

  Future<void> logout() async {
    _currentUser = null;
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

    _currentUser = user;
    return true;
  }

  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }

  bool hasPermission(String permission) {
    if (_currentUser == null) return false;
    
    switch (_currentUser!.role) {
      case UserRole.owner:
        return true;
      case UserRole.admin:
        return _getAdminPermissions().contains(permission);
      case UserRole.staff:
        return _getStaffPermissions().contains(permission);
    }
  }

  List<String> _getAdminPermissions() {
    return [
      'view_dashboard',
      'manage_users',
      'view_settings',
      'view_more',
    ];
  }

  List<String> _getStaffPermissions() {
    return [
      'view_dashboard',
      'view_pos',
      'view_sales',
      'view_reports',
      'view_more',
      'add_stock',
    ];
  }

  Future<bool> createUser({
    required String username,
    required String password,
    required String fullName,
    required UserRole role,
    String? pin,
  }) async {
    final existingUser = await _userRepository.getByUsernameWithDeleted(username);
    if (existingUser != null) {
      return false;
    }

    if (password.length < AppConstants.minPasswordLength) {
      return false;
    }

    final passwordHash = SecurityHelper.hashPassword(password);
    
    final user = User(
      username: username,
      passwordHash: passwordHash,
      pin: pin,
      role: role,
      fullName: fullName,
      createdAt: DateTime.now(),
    );

    await _userRepository.insert(user);
    return true;
  }

  Future<bool> changePassword(int userId, String oldPassword, String newPassword) async {
    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    if (!SecurityHelper.verifyPassword(oldPassword, user.passwordHash)) {
      return false;
    }

    if (newPassword.length < AppConstants.minPasswordLength) {
      return false;
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(passwordHash: newPasswordHash);
    await _userRepository.update(updatedUser);
    
    return true;
  }

  Future<bool> resetPassword(int userId, String newPassword) async {
    final user = await _userRepository.getById(userId);
    if (user == null) return false;

    if (newPassword.length < AppConstants.minPasswordLength) {
      return false;
    }

    final newPasswordHash = SecurityHelper.hashPassword(newPassword);
    final updatedUser = user.copyWith(passwordHash: newPasswordHash);
    await _userRepository.update(updatedUser);
    
    return true;
  }
}
