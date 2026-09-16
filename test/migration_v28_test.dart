import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Verifies the v28 migration against a database that still has the old
// per-user override columns. Covers both the DROP COLUMN path (which runs
// on modern SQLite) and the table-rebuild fallback used on pre-3.35 builds.
Future<Database> _oldSchemaDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      pin TEXT,
      pin_length INTEGER,
      role TEXT NOT NULL,
      full_name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      color_preference TEXT,
      profile_image_path TEXT,
      last_login TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      deleted_at TEXT,
      must_change_password INTEGER NOT NULL DEFAULT 0,
      has_changed_username INTEGER NOT NULL DEFAULT 0,
      inactivity_timeout_minutes INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE ai_quota (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL UNIQUE,
      daily_quota INTEGER NOT NULL,
      daily_usage INTEGER NOT NULL DEFAULT 0,
      quota_date TEXT NOT NULL,
      last_reset_at TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  ''');

  await db.insert('users', {
    'username': 'u1',
    'password_hash': 'x',
    'role': 'staff',
    'full_name': 'User One',
    'created_at': '2026-01-01T00:00:00',
    'inactivity_timeout_minutes': 30,
  });
  await db.insert('ai_quota', {
    'user_id': 1,
    'daily_quota': 55,
    'daily_usage': 7,
    'quota_date': '2026-01-01T00:00:00',
    'last_reset_at': '2026-01-01T00:00:00',
  });
  return db;
}

Future<void> _expectColumnsDropped(Database db) async {
  final userCols = (await db.rawQuery('PRAGMA table_info(users)'))
      .map((c) => c['name'])
      .toSet();
  final quotaCols = (await db.rawQuery('PRAGMA table_info(ai_quota)'))
      .map((c) => c['name'])
      .toSet();

  expect(userCols, isNot(contains('inactivity_timeout_minutes')));
  expect(quotaCols, isNot(contains('daily_quota')));

  final user = (await db.query('users')).single;
  final quota = (await db.query('ai_quota')).single;
  expect(user['username'], 'u1');
  expect(quota['daily_usage'], 7);
}

void main() {
  sqfliteFfiInit();
  final helper = DatabaseHelper();

  test('v28 migration drops override columns and preserves rows', () async {
    final db = await _oldSchemaDb();
    await helper.runV28MigrationForTest(db);
    await _expectColumnsDropped(db);
    await db.close();
  });

  test('v28 rebuild fallback drops columns and preserves rows', () async {
    final db = await _oldSchemaDb();
    await helper.runV28RebuildFallbackForTest(db);
    await _expectColumnsDropped(db);

    // Indexes dropped with the tables must be recreated.
    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    ))
        .map((r) => r['name'])
        .toSet();
    expect(indexes, contains('idx_users_username_active'));
    expect(indexes, contains('idx_ai_quota_user'));
    expect(indexes, contains('idx_ai_quota_date'));

    await db.close();
  });
}
