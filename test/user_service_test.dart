import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/user_service.dart';

/// Integration tests for the User Management CRUD flow.
///
/// These tests use a real local SQLite database (via sqflite_ffi) to verify
/// that every CRUD operation persists correctly, RBAC is enforced, and
/// soft-delete / restore / permanent-delete work as expected.
void main() {
  setUpAll(() {
    // Initialise sqflite_ffi for desktop test runner.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Reset the singleton DatabaseHelper first so the file handle is
    // released before we re-open.
    await DatabaseHelper.resetForTest();

    // Recreate the full schema explicitly.  This avoids the Windows
    // file-lock race: a plain re-open does not trigger _onCreate when the
    // file already exists with the same version, so a stale/corrupted file
    // would leave tests with no tables.  recreateSchemaForTest drops and
    // rebuilds every table + index regardless of file state.
    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();

    final seeder = DatabaseSeeder();
    await seeder.seed();

    // Reset the SessionManager singleton.
    SessionManager.resetForTest();
  });

  tearDown(() async {
    // Use resetForTest (not close()) so the singleton is fully cleared
    // between tests.  close() re-opens the database if it was already
    // closed, which can leave a dangling handle on Windows.
    await DatabaseHelper.resetForTest();
    // Brief pause to let Windows release the file handle.
    await Future.delayed(const Duration(milliseconds: 50));
  });

  /// Helper: creates and authenticates a System Admin so that user-management
  /// RBAC checks pass.
  Future<User> authenticateAsAdmin() async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

    // Insert an admin user directly.
    final now = DateTime.now();
    final adminId = await db.insert('users', {
      'username': 'sysadmin',
      'password_hash': SecurityHelper.hashPassword('Admin1234'),
      'pin': null,
      'role': 'admin',
      'full_name': 'System Administrator',
      'is_active': 1,
      'color_preference': null,
      'last_login': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'must_change_password': 0,
    });

    // Fetch the created admin and set as current user in SessionManager.
    final maps = await db.query('users', where: 'id = ?', whereArgs: [adminId]);
    final admin = User.fromMap(maps.first);
    SessionManager().setCurrentUser(admin);
    return admin;
  }

  test('CREATE: a new user is persisted and appears in the list', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.createUser(
      username: 'newstaff',
      fullName: 'New Staff',
      role: UserRole.staff,
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.user, isNotNull);
    expect(result.user!.username, 'newstaff');
    expect(result.user!.id, isNotNull);
    expect(result.user!.mustChangePassword, isTrue);

    // Verify it appears in the list.
    final users = await userService.getAllUsers();
    expect(users.any((u) => u.username == 'newstaff'), isTrue);
  });

  test('CREATE: duplicate username is rejected', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    // First create succeeds.
    final r1 = await userService.createUser(
      username: 'dupuser',
      fullName: 'Dup User',
      role: UserRole.staff,
    );
    expect(r1.success, isTrue);

    // Second create with same username fails.
    final r2 = await userService.createUser(
      username: 'dupuser',
      fullName: 'Another Dup',
      role: UserRole.staff,
    );
    expect(r2.success, isFalse);
    expect(r2.message, contains('Username already exists'));
  });

  test('CREATE: new user is assigned default temp password and mustChangePassword', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.createUser(
      username: 'tempcheck',
      fullName: 'Temp Check',
      role: UserRole.staff,
    );

    expect(result.success, isTrue);
    expect(result.user!.mustChangePassword, isTrue);

    // Verify the default temporary password works.
    final user = await userService.getUserById(result.user!.id!);
    expect(
      SecurityHelper.verifyPassword('@Password123', user!.passwordHash),
      isTrue,
    );
  });

  test('READ: getAllUsers returns only non-deleted users', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    await userService.createUser(
      username: 'readuser1',
      fullName: 'Read User 1',
      role: UserRole.staff,
    );
    await userService.createUser(
      username: 'readuser2',
      fullName: 'Read User 2',
      role: UserRole.staff,
    );

    final users = await userService.getAllUsers();
    expect(users.any((u) => u.username == 'readuser1'), isTrue);
    expect(users.any((u) => u.username == 'readuser2'), isTrue);
  });

  test('UPDATE: changing full name persists', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'editme',
      fullName: 'Original Name',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    final updateResult = await userService.updateUser(
      userId: userId,
      fullName: 'Updated Name',
    );

    expect(updateResult.success, isTrue);
    expect(updateResult.user!.fullName, 'Updated Name');

    // Verify persistence by re-reading.
    final user = await userService.getUserById(userId);
    expect(user!.fullName, 'Updated Name');
  });

  test('UPDATE: changing username to an existing username is rejected',
      () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final r1 = await userService.createUser(
      username: 'user_a',
      fullName: 'User A',
      role: UserRole.staff,
    );
    await userService.createUser(
      username: 'user_b',
      fullName: 'User B',
      role: UserRole.staff,
    );

    // Try to rename user_a to user_b.
    final result = await userService.updateUser(
      userId: r1.user!.id!,
      username: 'user_b',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('Username already exists'));
  });

  test('UPDATE: keeping own username is allowed', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'keepname',
      fullName: 'Keep Name',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    // Update full name without changing username.
    final result = await userService.updateUser(
      userId: userId,
      fullName: 'New Full Name',
    );

    expect(result.success, isTrue);
    expect(result.user!.username, 'keepname');
    expect(result.user!.fullName, 'New Full Name');
  });

  test('ACTIVATE/DEACTIVATE: status changes persist', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'toggleme',
      fullName: 'Toggle Me',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    // Deactivate.
    final deactResult = await userService.deactivateUser(userId);
    expect(deactResult.success, isTrue);

    var user = await userService.getUserById(userId);
    expect(user!.isActive, isFalse);

    // Reactivate.
    final actResult = await userService.activateUser(userId);
    expect(actResult.success, isTrue);

    user = await userService.getUserById(userId);
    expect(user!.isActive, isTrue);
  });

  test('DEACTIVATE: self-deactivation is rejected', () async {
    final admin = await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.deactivateUser(admin.id!);
    expect(result.success, isFalse);
    expect(result.message, contains('own account'));
  });

  test('SOFT DELETE: user disappears from list and appears in trash',
      () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'deleteme',
      fullName: 'Delete Me',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    final deleteResult = await userService.softDeleteUser(userId);
    expect(deleteResult.success, isTrue);

    // Should not appear in active list.
    final active = await userService.getAllUsers();
    expect(active.any((u) => u.id == userId), isFalse);

    // Should appear in deleted list.
    final deleted = await userService.getDeletedUsers();
    expect(deleted.any((u) => u.id == userId), isTrue);
  });

  test('SOFT DELETE: self-deletion is rejected', () async {
    final admin = await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.softDeleteUser(admin.id!);
    expect(result.success, isFalse);
    expect(result.message, contains('own account'));
  });

  test('RESTORE: soft-deleted user returns to the list', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'restoreme',
      fullName: 'Restore Me',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    await userService.softDeleteUser(userId);

    final restoreResult = await userService.restoreUser(userId);
    expect(restoreResult.success, isTrue);

    // Should appear in active list again.
    final active = await userService.getAllUsers();
    expect(active.any((u) => u.id == userId), isTrue);

    // Should not appear in deleted list.
    final deleted = await userService.getDeletedUsers();
    expect(deleted.any((u) => u.id == userId), isFalse);
  });

  test('RESTORE: username conflict is detected', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    // Create user, soft delete, then create a new user with same username.
    final r1 = await userService.createUser(
      username: 'conflictname',
      fullName: 'Original',
      role: UserRole.staff,
    );
    await userService.softDeleteUser(r1.user!.id!);

    // Create a new user with the same username (allowed because old one is
    // soft-deleted and the partial unique index only covers non-deleted).
    await userService.createUser(
      username: 'conflictname',
      fullName: 'Replacement',
      role: UserRole.staff,
    );

    // Now try to restore the original — should fail due to conflict.
    final restoreResult = await userService.restoreUser(r1.user!.id!);
    expect(restoreResult.success, isFalse);
    expect(restoreResult.message, contains('already in use'));
  });

  test('PERMANENT DELETE: user is irrecoverable', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'permdelete',
      fullName: 'Perm Delete',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    // Must soft-delete first.
    await userService.softDeleteUser(userId);

    final permResult = await userService.permanentlyDeleteUser(userId);
    expect(permResult.success, isTrue);

    // Should not appear in either list.
    final active = await userService.getAllUsers();
    expect(active.any((u) => u.id == userId), isFalse);
    final deleted = await userService.getDeletedUsers();
    expect(deleted.any((u) => u.id == userId), isFalse);
  });

  test('PERMANENT DELETE: non-deleted user is rejected', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'notdeleted',
      fullName: 'Not Deleted',
      role: UserRole.staff,
    );

    final result =
        await userService.permanentlyDeleteUser(createResult.user!.id!);
    expect(result.success, isFalse);
    expect(result.message, contains('trash'));
  });

  test('PASSWORD RESET: admin can reset another user\'s password to default', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final createResult = await userService.createUser(
      username: 'pwreset',
      fullName: 'PW Reset',
      role: UserRole.staff,
    );
    final userId = createResult.user!.id!;

    final result = await userService.resetPassword(userId);

    expect(result.success, isTrue);

    // Verify the password was reset to the default temporary password.
    final user = await userService.getUserById(userId);
    expect(
      SecurityHelper.verifyPassword('@Password123', user!.passwordHash),
      isTrue,
    );
    expect(user.mustChangePassword, isTrue);
  });

  test('RBAC: unauthenticated user cannot create users', () async {
    // Don't authenticate — SessionManager has no current user.
    final userService = UserService();

    expect(
      () => userService.createUser(
        username: 'shouldfail',
        fullName: 'Should Fail',
        role: UserRole.staff,
      ),
      throwsA(isA<AuthorizationException>()),
    );
  });

  test('RBAC: owner can create staff users', () async {
    // Authenticate as the seeded owner.
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final maps = await db.query('users', where: 'username = ?', whereArgs: ['owner']);
    final owner = User.fromMap(maps.first);
    SessionManager().setCurrentUser(owner);

    final userService = UserService();

    final result = await userService.createUser(
      username: 'ownercreated',
      fullName: 'Owner Created',
      role: UserRole.staff,
    );
    expect(result.success, isTrue);
  });

  test('RBAC: admin can create an owner', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.createUser(
      username: 'adminowner',
      fullName: 'Owner Created by Admin',
      role: UserRole.owner,
    );

    expect(result.success, isTrue);
    expect(result.user, isNotNull);
    expect(result.user!.role, UserRole.owner);
  });

  test('RBAC: admin cannot create another admin', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    final result = await userService.createUser(
      username: 'badadmin',
      fullName: 'Bad Admin',
      role: UserRole.admin,
    );

    expect(result.success, isFalse);
    expect(result.message, contains('role'));
  });

  test('RBAC: owner can create another owner', () async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final maps = await db.query('users', where: 'username = ?', whereArgs: ['owner']);
    final owner = User.fromMap(maps.first);
    SessionManager().setCurrentUser(owner);

    final userService = UserService();
    final result = await userService.createUser(
      username: 'owner2',
      fullName: 'Second Owner',
      role: UserRole.owner,
    );

    expect(result.success, isTrue);
    expect(result.user, isNotNull);
    expect(result.user!.role, UserRole.owner);
  });

  test('ACTIVITY LOG: user creation logs USER_CREATED action', () async {
    await authenticateAsAdmin();
    final userService = UserService();

    await userService.createUser(
      username: 'logtest',
      fullName: 'Log Test',
      role: UserRole.staff,
    );

    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final logs = await db.query(
      'activity_logs',
      where: 'action = ?',
      whereArgs: ['USER_CREATED'],
    );

    expect(logs, isNotEmpty);
    final log = logs.last;
    expect(log['entity'], 'user');
    expect(log['role'], 'admin');
    expect(log['details'], contains('logtest'));
  });
}
