import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Verifies the v30 → v31 migration: the decoded payment-QR payload cache
// column is added to settings so payment screens stop re-decoding the
// stored QR image on every open.
Future<Database> _v30SchemaDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      store_name TEXT NOT NULL,
      store_address TEXT,
      store_phone TEXT,
      currency TEXT NOT NULL DEFAULT 'PHP',
      gcash_qr_image_path TEXT,
      gcash_qr_image_type TEXT,
      gcash_qr_preview_path TEXT,
      gcash_merchant_name TEXT,
      gcash_merchant_phone TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  return db;
}

Future<Set<Object?>> _columns(Database db) async =>
    (await db.rawQuery('PRAGMA table_info(settings)'))
        .map((c) => c['name'])
        .toSet();

void main() {
  sqfliteFfiInit();
  final helper = DatabaseHelper();

  test('v31 migration adds the QR payload cache column', () async {
    final db = await _v30SchemaDb();
    await db.insert('settings', {
      'store_name': 'Store',
      'gcash_qr_image_path': 'gcash_qr/qr.png',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    await helper.runV31MigrationForTest(db);

    final columns = await _columns(db);
    expect(columns, contains('gcash_qr_payload'));

    // Existing QR data is untouched; the payload starts empty so the first
    // open decodes once and caches.
    final row = (await db.query('settings')).single;
    expect(row['gcash_qr_image_path'], 'gcash_qr/qr.png');
    expect(row['gcash_qr_payload'], isNull);
    await db.close();
  });

  test('v31 migration is idempotent', () async {
    final db = await _v30SchemaDb();
    await db.insert('settings', {
      'store_name': 'Store',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    await helper.runV31MigrationForTest(db);
    await db.update('settings', {'gcash_qr_payload': 'cached-payload'});
    // Running again must not drop the cached payload.
    await helper.runV31MigrationForTest(db);

    final row = (await db.query('settings')).single;
    expect(row['gcash_qr_payload'], 'cached-payload');
    await db.close();
  });
}
