import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';

class DatabaseSeeder {
  final UserRepository _userRepository = UserRepository();

  Future<void> seed() async {
    final existingOwner = await _userRepository.getByUsername('owner');
    
    if (existingOwner == null) {
      final owner = User(
        username: 'owner',
        passwordHash: SecurityHelper.hashPassword('admin123'),
        role: UserRole.owner,
        fullName: 'Store Owner',
        createdAt: DateTime.now(),
      );
      await _userRepository.insert(owner);
    }
  }
}
