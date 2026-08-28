import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_quota_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/user_service.dart';

/// Integration tests for AI quota enforcement and administration.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));

    final dbHelper = DatabaseHelper();
    await dbHelper.recreateSchemaForTest();

    final seeder = DatabaseSeeder();
    await seeder.seed();

    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
  });

  Future<User> authenticateAsAdmin() async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;

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

    final maps = await db.query('users', where: 'id = ?', whereArgs: [adminId]);
    final admin = User.fromMap(maps.first);
    SessionManager().setCurrentUser(admin);
    return admin;
  }

  group('Schema and model', () {
    test('creates ai_quota table with expected columns', () async {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final tables = await db.query('sqlite_master',
          where: 'type = ? AND name = ?', whereArgs: ['table', 'ai_quota']);
      expect(tables, isNotEmpty);

      final columns = await db.rawQuery('PRAGMA table_info(ai_quota)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      expect(columnNames, containsAll(['id', 'user_id', 'daily_quota', 'daily_usage', 'quota_date', 'last_reset_at']));
    });

    test('settings table has ai_daily_quota column', () async {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final columns = await db.rawQuery('PRAGMA table_info(settings)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      expect(columnNames, contains('ai_daily_quota'));
    });

    test('seeder creates ai_quota rows for default users', () async {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final users = await db.query('users', where: 'deleted_at IS NULL');
      final quotaRows = await db.query('ai_quota');

      expect(quotaRows.length, users.length);
    });

    test('AIQuota toMap and fromMap round-trip', () {
      final now = DateTime.now();
      final original = AIQuota(
        id: 1,
        userId: 5,
        dailyQuota: 20,
        dailyUsage: 3,
        quotaDate: now,
        lastResetAt: now,
      );

      final map = original.toMap();
      final restored = AIQuota.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.dailyQuota, original.dailyQuota);
      expect(restored.dailyUsage, original.dailyUsage);
      expect(restored.quotaDate, original.quotaDate);
      expect(restored.lastResetAt, original.lastResetAt);
    });
  });

  group('Daily enforcement', () {
    test('new user has default quota of 20', () async {
      await authenticateAsAdmin();
      final userService = UserService();

      final result = await userService.createUser(
        username: 'newstaff',
        fullName: 'New Staff',
        role: UserRole.staff,
      );

      expect(result.success, isTrue);

      final aiQuotaService = AIQuotaService();
      final quota = await aiQuotaService.getQuotaForUser(result.user!.id!);

      expect(quota.dailyQuota, 20);
      expect(quota.dailyUsage, 0);
    });

    test('canUseAI returns false when daily quota is exhausted', () async {
      await authenticateAsAdmin();
      final userService = UserService();

      final result = await userService.createUser(
        username: 'limited',
        fullName: 'Limited User',
        role: UserRole.staff,
      );

      final aiQuotaService = AIQuotaService();
      await aiQuotaService.updateUserQuota(
        result.user!.id!,
        value: 2,
        verified: true,
      );

      SessionManager().setCurrentUser(result.user!);

      expect(await aiQuotaService.canUseAI(), isTrue);
      await aiQuotaService.recordQuery('query 1');
      expect(await aiQuotaService.canUseAI(), isTrue);
      await aiQuotaService.recordQuery('query 2');
      expect(await aiQuotaService.canUseAI(), isFalse);
    });

    test('daily usage resets on a new day', () async {
      await authenticateAsAdmin();
      final userService = UserService();

      final result = await userService.createUser(
        username: 'daily',
        fullName: 'Daily User',
        role: UserRole.staff,
      );

      final aiQuotaService = AIQuotaService();
      await aiQuotaService.updateUserQuota(
        result.user!.id!,
        value: 20,
        verified: true,
      );

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.update(
        'ai_quota',
        {
          'daily_usage': 20,
          'quota_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        },
        where: 'user_id = ?',
        whereArgs: [result.user!.id!],
      );

      SessionManager().setCurrentUser(result.user!);

      expect(await aiQuotaService.canUseAI(), isTrue);
      expect(await aiQuotaService.getTodayUsageCount(), 0);
    });
  });

  group('SuperAdmin verification', () {
    test('protected operations fail without verification', () async {
      await authenticateAsAdmin();
      final aiQuotaService = AIQuotaService();

      final result = await aiQuotaService.setDefaultQuota(
        value: 30,
        applyToExisting: false,
        verified: false,
      );

      expect(result.success, isFalse);
    });

    test('set default quota with correct password succeeds', () async {
      await authenticateAsAdmin();
      final aiQuotaService = AIQuotaService();

      final result = await aiQuotaService.setDefaultQuota(
        value: 30,
        applyToExisting: false,
        verified: true,
      );

      expect(result.success, isTrue);

      final settingsService = SettingsService();
      final settings = await settingsService.getSettings();
      expect(settings.aiDailyQuota, 30);
    });

    test('set default quota rejects invalid values', () async {
      await authenticateAsAdmin();
      final aiQuotaService = AIQuotaService();

      final negative = await aiQuotaService.setDefaultQuota(
        value: -1,
        applyToExisting: false,
        verified: true,
      );
      expect(negative.success, isFalse);

      final tooLarge = await aiQuotaService.setDefaultQuota(
        value: 10000,
        applyToExisting: false,
        verified: true,
      );
      expect(tooLarge.success, isFalse);
    });
  });

  group('Audit logging', () {
    test('set default quota logs AI_QUOTA_DEFAULT_CHANGED', () async {
      await authenticateAsAdmin();
      final aiQuotaService = AIQuotaService();

      await aiQuotaService.setDefaultQuota(
        value: 30,
        applyToExisting: false,
        verified: true,
      );

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final logs = await db.query(
        'activity_logs',
        where: 'action = ?',
        whereArgs: ['AI_QUOTA_DEFAULT_CHANGED'],
      );

      expect(logs, isNotEmpty);
      final log = logs.first;
      expect(log['role'], 'admin');
    });
  });
}
