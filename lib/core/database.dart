import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/file_type_utils.dart';
import 'package:pinoy_pos/core/security.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration from v1 → v2: add updated_at, color_preference to users;
    // add role to activity_log; replace column-level UNIQUE on username with
    // a partial unique index that only applies to non-deleted users (so that
    // soft-deleted usernames can be reused).
    if (oldVersion < 2) {
      // Add new columns to users table.
      await db.execute('ALTER TABLE users ADD COLUMN color_preference TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN updated_at TEXT');

      // Add role column to activity_log (renamed to activity_logs in v3).
      await db.execute('ALTER TABLE activity_log ADD COLUMN role TEXT');

      // Recreate users table without the column-level UNIQUE constraint so
      // that soft-deleted users don't block username reuse.  We temporarily
      // disable foreign-key enforcement for the migration; this is safe
      // because we copy every row verbatim and preserve all ids.
      await db.execute('PRAGMA foreign_keys = OFF');

      await db.execute('''
        CREATE TABLE users_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          pin TEXT,
          role TEXT NOT NULL,
          full_name TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          color_preference TEXT,
          last_login TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT,
          deleted_at TEXT
        )
      ''');

      await db.execute('''
        INSERT INTO users_new
          (id, username, password_hash, pin, role, full_name, is_active,
           color_preference, last_login, created_at, updated_at, deleted_at)
        SELECT
          id, username, password_hash, pin, role, full_name, is_active,
          NULL, last_login, created_at, NULL, deleted_at
        FROM users
      ''');

      await db.execute('DROP TABLE users');
      await db.execute('ALTER TABLE users_new RENAME TO users');

      // Partial unique index: username must be unique only among non-deleted
      // users.  This is compatible with the soft-delete design.
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active '
        'ON users(username) WHERE deleted_at IS NULL',
      );

      await db.execute('PRAGMA foreign_keys = ON');
    }

    // Migration from v2 → v3: rename activity_log → activity_logs;
    // create trash, backup_history, export_history tables.
    if (oldVersion < 3) {
      // Rename activity_log to activity_logs to match DAO convention.
      await db.execute('ALTER TABLE activity_log RENAME TO activity_logs');

      // Recreate indexes with updated table name.
      await db.execute('DROP INDEX IF EXISTS idx_activity_log_user');
      await db.execute('DROP INDEX IF EXISTS idx_activity_log_date');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_logs_user ON activity_logs(user_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_logs_date ON activity_logs(created_at)');

      // Create missing tables.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS trash (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entity_type TEXT NOT NULL,
          entity_id INTEGER NOT NULL,
          entity_name TEXT,
          deleted_by INTEGER,
          deleted_at TEXT NOT NULL,
          expires_at TEXT,
          FOREIGN KEY (deleted_by) REFERENCES users(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS backup_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL,
          file_size INTEGER,
          created_by INTEGER,
          created_at TEXT NOT NULL,
          FOREIGN KEY (created_by) REFERENCES users(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS export_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          report_type TEXT NOT NULL,
          file_format TEXT NOT NULL,
          file_path TEXT NOT NULL,
          date_range_start TEXT,
          date_range_end TEXT,
          created_by INTEGER,
          created_at TEXT NOT NULL,
          FOREIGN KEY (created_by) REFERENCES users(id)
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_trash_entity ON trash(entity_type, entity_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_backup_history_date ON backup_history(created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_export_history_date ON export_history(created_at)');
    }

    // Migration from v3 → v4: add profile_image_path to users table.
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN profile_image_path TEXT',
      );
    }

    // Migration from v4 → v5: add Groq AI configuration columns to settings.
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE settings ADD COLUMN groq_api_key TEXT');
      await db.execute('ALTER TABLE settings ADD COLUMN groq_model TEXT');
    }

    // Migration from v5 → v6: hash all existing plaintext PINs in the
    // users table and add a pin_length column to record the original
    // PIN length (needed for dynamic auto-submit since the hash does
    // not reveal the original length).
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE users ADD COLUMN pin_length INTEGER');

      final rows = await db.query('users', columns: ['id', 'pin']);
      for (final row in rows) {
        final pin = row['pin'] as String?;
        if (pin != null && pin.isNotEmpty && pin.length < 64) {
          // Plaintext PIN — record its length, then hash it.
          await db.update(
            'users',
            {
              'pin': SecurityHelper.hashPin(pin),
              'pin_length': pin.length,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else if (pin != null && pin.isNotEmpty) {
          // Already hashed (64 chars) — we don't know the original
          // length, so default to 4 (the minimum).
          await db.update(
            'users',
            {'pin_length': 4},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }

    // Migration from v6 → v7: add must_change_password column to users
    // table for first-login forced password change tracking.
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Migration from v7 → v8: create backup_metadata table for strict
    // backup import validation.
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS backup_metadata (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          app_name TEXT NOT NULL,
          app_version TEXT NOT NULL,
          database_version INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }

    // Migration from v8 → v9: add storage metadata to backup_history so
    // backups can be stored as Android SAF content URIs in addition to
    // traditional file paths.
    if (oldVersion < 9) {
      await db.execute('ALTER TABLE backup_history ADD COLUMN storage_type TEXT');
      await db.execute('ALTER TABLE backup_history ADD COLUMN display_name TEXT');
      await db.execute('ALTER TABLE backup_history ADD COLUMN location_json TEXT');
    }

    // Migration from v9 → v10: add payment_method to sales so reports can
    // break down revenue by payment method (Cash, GCash, Card, etc.).
    if (oldVersion < 10) {
      await db.execute('ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT \'Cash\'');
    }

    // Migration from v10 → v11: add GCash/payment verification fields to sales
    // and GCash configuration columns to settings.
    if (oldVersion < 11) {
      await db.execute('ALTER TABLE sales ADD COLUMN payment_status TEXT NOT NULL DEFAULT \'confirmed\'');
      await db.execute('ALTER TABLE sales ADD COLUMN reference_number TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN payment_proof_path TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN payment_proof_type TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN verified_at TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN verified_by INTEGER');

      await db.execute('ALTER TABLE settings ADD COLUMN gcash_enabled INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE settings ADD COLUMN gcash_reference_required INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE settings ADD COLUMN gcash_customer_name_requirement TEXT NOT NULL DEFAULT \'optional\'');
      await db.execute('ALTER TABLE settings ADD COLUMN gcash_payment_proof_requirement TEXT NOT NULL DEFAULT \'optional\'');
      await db.execute('ALTER TABLE settings ADD COLUMN gcash_verification_mode TEXT NOT NULL DEFAULT \'immediate\'');
      await db.execute('ALTER TABLE settings ADD COLUMN gcash_reference_min_length INTEGER NOT NULL DEFAULT 6');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_payment_method ON sales(payment_method)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_payment_status ON sales(payment_status)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_gcash_reference '
        'ON sales(reference_number) '
        'WHERE payment_method = \'GCash\' AND deleted_at IS NULL AND reference_number IS NOT NULL '
        'AND payment_status NOT IN (\'cancelled\', \'refunded\')',
      );
    }

    // Migration from v11 → v12: add product_name to sale_items so receipts
    // can display the historical product name even if the product is later
    // renamed or deleted.
    if (oldVersion < 12) {
      await db.execute('ALTER TABLE sale_items ADD COLUMN product_name TEXT');
    }

    // Migration from v12 -> v13: add AI quota table and default AI quota
    // column to settings. Seed an ai_quota row for every existing user.
    if (oldVersion < 13) {
      await db.execute('ALTER TABLE settings ADD COLUMN ai_daily_quota INTEGER NOT NULL DEFAULT 20');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_quota (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL UNIQUE,
          daily_quota INTEGER NOT NULL,
          daily_usage INTEGER NOT NULL DEFAULT 0,
          quota_date TEXT NOT NULL,
          last_reset_at TEXT,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_quota_user ON ai_quota(user_id)',
      );

      final defaultQuota = AppConstants.defaultDailyAIQuota;
      final now = DateTime.now().toIso8601String();
      final today = DateTime.now().toIso8601String();

      await db.execute('''
        INSERT INTO ai_quota (user_id, daily_quota, daily_usage, quota_date, last_reset_at)
        SELECT id, ?, 0, ?, ?
        FROM users
        WHERE deleted_at IS NULL
      ''', [defaultQuota, today, now]);
    }

    // Migration from v13 → v14: add has_changed_username to users table
    // so self-service username changes can be limited to one per user.
    if (oldVersion < 14) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN has_changed_username INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Migration from v14 → v15: remove the unused accent_color column
    // from settings. The app now derives color entirely from the semantic
    // primary seed and the Material 3 ColorScheme.
    if (oldVersion < 15) {
      try {
        await db.execute('ALTER TABLE settings DROP COLUMN accent_color');
      } catch (e) {
        // Some older SQLite versions or Windows FFI builds do not support
        // DROP COLUMN. Recreate the table and copy the data instead.
        await db.execute('PRAGMA foreign_keys = OFF');
        await db.execute('''
          CREATE TABLE settings_new (
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
            gcash_reference_min_length INTEGER NOT NULL DEFAULT 6,
            ai_daily_quota INTEGER NOT NULL DEFAULT 20,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          INSERT INTO settings_new
            (id, store_name, store_address, store_phone, currency, receipt_footer,
             theme, groq_api_key, groq_model, gcash_enabled, gcash_reference_required,
             gcash_customer_name_requirement, gcash_payment_proof_requirement,
             gcash_verification_mode, gcash_reference_min_length, ai_daily_quota,
             created_at, updated_at)
          SELECT
            id, store_name, store_address, store_phone, currency, receipt_footer,
            theme, groq_api_key, groq_model, gcash_enabled, gcash_reference_required,
            gcash_customer_name_requirement, gcash_payment_proof_requirement,
            gcash_verification_mode, gcash_reference_min_length, ai_daily_quota,
            created_at, updated_at
          FROM settings
        ''');
        await db.execute('DROP TABLE settings');
        await db.execute('ALTER TABLE settings_new RENAME TO settings');
        await db.execute('PRAGMA foreign_keys = ON');
      }
    }

    // Migration from v15 → v16: backfill actual MIME types for payment proofs.
    // Previous versions stored the generic string 'image' in
    // payment_proof_type. Detect the real type from file signatures and
    // update the column so exports and previews can rely on it.
    if (oldVersion < 16) {
      await _backfillPaymentProofTypes(db);
    }
  }

  /// Backfills payment_proof_type for existing sales by detecting the actual
  /// file type from the stored payment evidence.
  ///
  /// Missing or unreadable files have their type cleared. Failures are caught
  /// per-file and per-batch so a single bad proof cannot block the upgrade.
  Future<void> _backfillPaymentProofTypes(Database db) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final rows = await db.query(
        'sales',
        columns: ['id', 'payment_proof_path', 'payment_proof_type'],
        where: 'payment_proof_path IS NOT NULL AND payment_proof_path != ?',
        whereArgs: [''],
      );

      for (final row in rows) {
        final id = row['id'] as int?;
        final path = row['payment_proof_path'] as String?;
        if (id == null || path == null || path.isEmpty) continue;

        try {
          final file = File(join(appDir.path, path));
          if (!await file.exists()) {
            await db.update(
              'sales',
              {'payment_proof_type': null},
              where: 'id = ?',
              whereArgs: [id],
            );
            continue;
          }

          final raf = await file.open();
          final bytes = await raf.read(64);
          await raf.close();

          final fileType = FileTypeUtils.detect(bytes, fileName: file.path);
          await db.update(
            'sales',
            {'payment_proof_type': fileType?.mime},
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (_) {
          // Leave the row as-is on a per-file error; do not block the upgrade.
        }
      }
    } catch (_) {
      // Do not block the app upgrade if the backfill cannot complete.
    }
  }

  Future<void> _createTables(Database db) async {
    // Users table
    // NOTE: every CREATE statement uses IF NOT EXISTS so that _onCreate is
    // idempotent. If a previous launch crashed partway through database
    // initialization (leaving some tables/indexes created but user_version
    // not yet committed), the next launch re-runs _onCreate and can complete
    // instead of throwing "table/index already exists". Without this, a
    // single interrupted first run would permanently brick the database and
    // every screen that depends on it (i.e. all Owner screens) would fail.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
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

    // Categories table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    // Products table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 10,
        image_url TEXT,
        category_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    // Sales table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL NOT NULL,
        cash_received REAL NOT NULL,
        change REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'Cash',
        payment_status TEXT NOT NULL DEFAULT 'confirmed',
        reference_number TEXT,
        customer_name TEXT,
        payment_proof_path TEXT,
        payment_proof_type TEXT,
        verified_at TEXT,
        verified_by INTEGER,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        receipt_number TEXT UNIQUE,
        notes TEXT,
        deleted_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Sale items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Stock history table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        operation TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        previous_stock INTEGER NOT NULL,
        new_stock INTEGER NOT NULL,
        reason TEXT,
        user_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Notifications table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
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

    // Announcements table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS announcements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        expires_at TEXT,
        created_by INTEGER,
        created_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');

    // Settings table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
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
        gcash_reference_min_length INTEGER NOT NULL DEFAULT 6,
        ai_daily_quota INTEGER NOT NULL DEFAULT 20,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Activity log table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        role TEXT,
        action TEXT NOT NULL,
        entity TEXT,
        entity_id INTEGER,
        details TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // AI usage table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        query TEXT NOT NULL,
        response TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');


    // AI quota table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_quota (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        daily_quota INTEGER NOT NULL,
        daily_usage INTEGER NOT NULL DEFAULT 0,
        quota_date TEXT NOT NULL,
        last_reset_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    // Trash table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trash (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        entity_name TEXT,
        deleted_by INTEGER,
        deleted_at TEXT NOT NULL,
        expires_at TEXT,
        FOREIGN KEY (deleted_by) REFERENCES users(id)
      )
    ''');

    // Backup history table
    // file_path now stores a storage reference (filesystem path or URI).
    // storage_type distinguishes fileSystem / androidSaf / webDownload.
    // display_name is the human-readable filename shown in the UI.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        storage_type TEXT,
        display_name TEXT,
        location_json TEXT,
        file_size INTEGER,
        created_by INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');

    // Export history table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS export_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_type TEXT NOT NULL,
        file_format TEXT NOT NULL,
        file_path TEXT NOT NULL,
        date_range_start TEXT,
        date_range_end TEXT,
        created_by INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');

    // Backup metadata table — stores a single row identifying this
    // database as a genuine Pinoy POS backup.  Used by the import
    // validation to reject arbitrary SQLite files that happen to have
    // the right table names.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_name TEXT NOT NULL,
        app_version TEXT NOT NULL,
        database_version INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Create indexes
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    // Partial unique index: username must be unique only among non-deleted
    // users.  Compatible with the soft-delete design.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active '
      'ON users(username) WHERE deleted_at IS NULL',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_user ON sales(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_payment_method ON sales(payment_method)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_payment_status ON sales(payment_status)');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_gcash_reference '
      'ON sales(reference_number) '
      'WHERE payment_method = \'GCash\' AND deleted_at IS NULL AND reference_number IS NOT NULL '
      'AND payment_status NOT IN (\'cancelled\', \'refunded\')',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_history_product ON stock_history(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_history_date ON stock_history(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(is_read)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_logs_user ON activity_logs(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_logs_date ON activity_logs(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trash_entity ON trash(entity_type, entity_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_backup_history_date ON backup_history(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_export_history_date ON export_history(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_usage_user ON ai_usage(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_usage_date ON ai_usage(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_quota_user ON ai_quota(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_quota_date ON ai_quota(quota_date)');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Resets the singleton state for testing.  Closes any open database
  /// and clears the cached instance so the next access re-creates it.
  ///
  /// The close is awaited so that the underlying file handle is fully
  /// released before a test deletes the database file.  Without awaiting,
  /// Windows keeps the file locked and the deletion fails, which previously
  /// left a stale database on disk and caused _onCreate to re-run against
  /// an already-initialized file (throwing "index already exists").
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _database?.close();
    _database = null;
  }

  /// Drops every known table and recreates the full schema + indexes on the
  /// current database instance.  Intended for test setups only: it avoids
  /// the Windows file-lock race that occurs when tests try to delete and
  /// re-open the database file between runs.  Because the database version
  /// is already at [AppConstants.databaseVersion], a plain re-open would NOT
  /// trigger `_onCreate`, leaving dropped tables empty.  This method
  /// explicitly recreates them.
  @visibleForTesting
  Future<void> recreateSchemaForTest() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS sale_items');
      await txn.execute('DROP TABLE IF EXISTS sales');
      await txn.execute('DROP TABLE IF EXISTS stock_history');
      await txn.execute('DROP TABLE IF EXISTS notifications');
      await txn.execute('DROP TABLE IF EXISTS announcements');
      await txn.execute('DROP TABLE IF EXISTS settings');
      await txn.execute('DROP TABLE IF EXISTS activity_logs');
      await txn.execute('DROP TABLE IF EXISTS ai_usage');
      await txn.execute('DROP TABLE IF EXISTS ai_quota');
      await txn.execute('DROP TABLE IF EXISTS trash');
      await txn.execute('DROP TABLE IF EXISTS backup_history');
      await txn.execute('DROP TABLE IF EXISTS export_history');
      await txn.execute('DROP TABLE IF EXISTS backup_metadata');
      await txn.execute('DROP TABLE IF EXISTS products');
      await txn.execute('DROP TABLE IF EXISTS categories');
      await txn.execute('DROP TABLE IF EXISTS users');
    });
    await _createTables(db);
    await _createIndexes(db);
  }

  // Transaction support
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }
}
