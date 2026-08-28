import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/database.dart';
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
        final id = await _userRepository.insert(user);

        await _seedAiQuota(id);
      }
    }
  }

  Future<void> _seedAiQuota(int userId) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

    final existing = await db.query(
      'ai_quota',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    await db.insert('ai_quota', {
      'user_id': userId,
      'daily_quota': AppConstants.defaultDailyAIQuota,
      'daily_usage': 0,
      'quota_date': now.toIso8601String(),
      'last_reset_at': now.toIso8601String(),
    });
  }
}
