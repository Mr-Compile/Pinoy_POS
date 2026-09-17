import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Verifies the v29 → v30 migration: the dedicated payment merchant
// identity columns are added to settings and seeded from the existing
// store identity so current installs keep their checkout label.
Future<Database> _v29SchemaDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      store_name TEXT NOT NULL,
      store_address TEXT,
      store_phone TEXT,
      currency TEXT NOT NULL DEFAULT 'PHP',
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

  test('v30 migration adds merchant columns seeded from store identity',
      () async {
    final db = await _v29SchemaDb();
    await db.insert('settings', {
      'store_name': 'My Sari-Sari Store',
      'store_phone': '0917 000 0000',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    await helper.runV30MigrationForTest(db);

    final columns = await _columns(db);
    expect(columns, contains('gcash_merchant_name'));
    expect(columns, contains('gcash_merchant_phone'));

    final row = (await db.query('settings')).single;
    expect(row['store_name'], 'My Sari-Sari Store');
    expect(row['gcash_merchant_name'], 'My Sari-Sari Store');
    expect(row['gcash_merchant_phone'], '0917 000 0000');
    await db.close();
  });

  test('v30 migration leaves empty merchant fields when store has none',
      () async {
    final db = await _v29SchemaDb();
    await db.insert('settings', {
      'store_name': 'Store',
      'store_phone': null,
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    await helper.runV30MigrationForTest(db);

    final row = (await db.query('settings')).single;
    expect(row['gcash_merchant_name'], 'Store');
    expect(row['gcash_merchant_phone'], isNull);
    await db.close();
  });

  test('v30 migration is idempotent', () async {
    final db = await _v29SchemaDb();
    await db.insert('settings', {
      'store_name': 'Store',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    await helper.runV30MigrationForTest(db);
    await db.update(
      'settings',
      {'gcash_merchant_name': 'Custom Merchant'},
    );
    // Running again must not overwrite the user's merchant identity.
    await helper.runV30MigrationForTest(db);

    final row = (await db.query('settings')).single;
    expect(row['gcash_merchant_name'], 'Custom Merchant');
    await db.close();
  });
}
