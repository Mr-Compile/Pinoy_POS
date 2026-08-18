import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

class DatabaseSeeder {
  final UserRepository _userRepository = UserRepository();

  Future<void> seed() async {
    final defaultUsers = [
      ('owner', 'owner123', UserRole.owner, 'Store Owner'),
      ('admin', 'admin123', UserRole.admin, 'Administrator'),
      ('staff', 'staff123', UserRole.staff, 'Staff Member'),
    ];

    for (final (username, password, role, fullName) in defaultUsers) {
      final existing = await _userRepository.getByUsername(username);
      if (existing == null) {
        final user = User(
          username: username,
          passwordHash: SecurityHelper.hashPassword(password),
          role: role,
          fullName: fullName,
          createdAt: DateTime.now(),
        );
        await _userRepository.insert(user);
      }
    }
  }
}
