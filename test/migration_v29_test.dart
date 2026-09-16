import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Verifies the v29 migration against a database that still has the dead
// columns removed in v29 (users.color_preference, settings.theme,
// attachments.is_active, export_history.thumbnail_path,
// notifications.read_at). Covers both the DROP COLUMN path (which runs on
// modern SQLite) and the table-rebuild fallback used on pre-3.35 builds.
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
      has_changed_username INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      store_name TEXT NOT NULL,
      store_address TEXT,
      store_phone TEXT,
      currency TEXT NOT NULL DEFAULT 'PHP',
      receipt_footer TEXT,
      theme TEXT,
      groq_api_key TEXT,
      groq_model TEXT,
      gcash_enabled INTEGER NOT NULL DEFAULT 1,
      gcash_reference_required INTEGER NOT NULL DEFAULT 1,
      gcash_customer_name_requirement TEXT NOT NULL DEFAULT 'optional',
      gcash_payment_proof_requirement TEXT NOT NULL DEFAULT 'optional',
      gcash_verification_mode TEXT NOT NULL DEFAULT 'immediate',
      gcash_reference_min_length INTEGER NOT NULL DEFAULT 13,
      gcash_qr_image_path TEXT,
      gcash_qr_image_type TEXT,
      gcash_qr_preview_path TEXT,
      ai_daily_quota INTEGER NOT NULL DEFAULT 20,
      inactivity_timeout_minutes INTEGER NOT NULL DEFAULT 15,
      session_warning_seconds INTEGER NOT NULL DEFAULT 30,
      auto_backup_enabled INTEGER NOT NULL DEFAULT 0,
      auto_backup_frequency TEXT NOT NULL DEFAULT '7_days',
      auto_backup_time TEXT NOT NULL DEFAULT '02:00',
      auto_backup_last_run TEXT,
      auto_backup_scheduled_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL,
      file_path TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      file_name TEXT NOT NULL,
      attachment_type TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      deleted_at TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE export_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      report_type TEXT NOT NULL,
      file_format TEXT NOT NULL,
      file_path TEXT NOT NULL,
      date_range_start TEXT,
      date_range_end TEXT,
      created_by INTEGER,
      created_at TEXT NOT NULL,
      status TEXT,
      submitted_at TEXT,
      viewed_at TEXT,
      file_size INTEGER,
      thumbnail_path TEXT,
      report_number TEXT,
      deleted_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE notifications (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      type TEXT,
      user_id INTEGER,
      is_read INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      read_at TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');

  await db.insert('users', {
    'username': 'u1',
    'password_hash': 'x',
    'role': 'staff',
    'full_name': 'User One',
    'color_preference': 'blue',
    'created_at': '2026-01-01T00:00:00',
  });
  await db.insert('settings', {
    'store_name': 'Test Store',
    'theme': 'dark',
    'created_at': '2026-01-01T00:00:00',
    'updated_at': '2026-01-01T00:00:00',
  });
  await db.insert('attachments', {
    'entity_type': 'product',
    'entity_id': 1,
    'file_path': 'img.jpg',
    'mime_type': 'image/jpeg',
    'file_name': 'img.jpg',
    'is_active': 1,
    'created_at': '2026-01-01T00:00:00',
  });
  await db.insert('export_history', {
    'report_type': 'sales',
    'file_format': 'pdf',
    'file_path': 'reports/r.pdf',
    'created_at': '2026-01-01T00:00:00',
    'status': 'generated',
    'thumbnail_path': 'thumbs/r.png',
    'report_number': 'RPT-0001',
  });
  await db.insert('notifications', {
    'title': 'Low stock',
    'message': 'Product X is low',
    'type': 'low_stock',
    'user_id': 1,
    'is_read': 1,
    'created_at': '2026-01-01T00:00:00',
    'read_at': '2026-01-02T00:00:00',
  });
  return db;
}

Future<Set<Object?>> _columns(Database db, String table) async =>
    (await db.rawQuery('PRAGMA table_info($table)'))
        .map((c) => c['name'])
        .toSet();

Future<void> _expectColumnsDropped(Database db) async {
  expect(await _columns(db, 'users'), isNot(contains('color_preference')));
  expect(await _columns(db, 'settings'), isNot(contains('theme')));
  expect(await _columns(db, 'attachments'), isNot(contains('is_active')));
  expect(
    await _columns(db, 'export_history'),
    isNot(contains('thumbnail_path')),
  );
  expect(await _columns(db, 'notifications'), isNot(contains('read_at')));

  expect((await db.query('users')).single['username'], 'u1');
  expect((await db.query('settings')).single['store_name'], 'Test Store');
  expect((await db.query('attachments')).single['file_path'], 'img.jpg');
  expect(
    (await db.query('export_history')).single['report_number'],
    'RPT-0001',
  );
  expect((await db.query('notifications')).single['is_read'], 1);
}

Future<void> _expectIndexesRecreated(Database db) async {
  final indexes = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  ))
      .map((r) => r['name'])
      .toSet();
  expect(indexes, contains('idx_users_username_active'));
  expect(indexes, contains('idx_attachments_entity'));
  expect(indexes, contains('idx_export_history_date'));
  expect(indexes, contains('idx_notifications_user'));
  expect(indexes, contains('idx_notifications_read'));
}

void main() {
  sqfliteFfiInit();
  final helper = DatabaseHelper();

  test('v29 migration drops dead columns and preserves rows', () async {
    final db = await _oldSchemaDb();
    await helper.runV29MigrationForTest(db);
    await _expectColumnsDropped(db);
    await db.close();
  });

  test('v29 rebuild fallback drops columns and preserves rows', () async {
    final db = await _oldSchemaDb();
    await helper.runV29RebuildFallbackForTest(db);
    await _expectColumnsDropped(db);
    await _expectIndexesRecreated(db);
    await db.close();
  });
}
