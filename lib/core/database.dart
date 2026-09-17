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

  /// Test-only override for the database filename. When set, [database]
  /// opens (and re-opens) this filename instead of the production
  /// [AppConstants.databaseName]. This avoids Windows file-lock races between
  /// consecutive tests that share the same [DatabaseHelper] singleton.
  static String? _testDbName;
  static int _testRun = 0;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  String get _dbName => _testDbName ?? AppConstants.databaseName;

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, _dbName);

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
          snapshot_json TEXT,
          attachment_count INTEGER NOT NULL DEFAULT 0,
          total_size_bytes INTEGER NOT NULL DEFAULT 0,
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
    // break down revenue by payment method (Cash and GCash).
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
      await db.execute('ALTER TABLE settings ADD COLUMN ai_daily_quota INTEGER NOT NULL DEFAULT ${AppConstants.defaultDailyAIQuota}');

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
            ai_daily_quota INTEGER NOT NULL DEFAULT ${AppConstants.defaultDailyAIQuota},
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

    // Migration from v16 → v17: re-detect payment proof types with the
    // expanded image signature set and larger read buffer so files that
    // previously failed detection (no extension, HEIC, AVIF, etc.) get a
    // correct MIME value.
    if (oldVersion < 17) {
      await _backfillPaymentProofTypes(db);
    }

    // Migration from v17 → v18: extend export_history for the report
    // submission / owner inbox workflow.
    if (oldVersion < 18) {
      await _migrateExportHistoryV18(db);
    }

    // Migration from v18 → v19: add GCash QR merchant image storage.
    if (oldVersion < 19) {
      await _migrateSettingsV19(db);
    }

    // Migration from v19 → v20: generic attachments and trash snapshots.
    if (oldVersion < 20) {
      await _migrateV20(db);
    }

    // Migration from v20 → v21: add inactivity timeout settings.
    if (oldVersion < 21) {
      await _migrateV21(db);
    }

    // Migration from v21 → v22: normalize the GCash verification mode.
    // The legacy 'admin' value was a dead configuration — the System Admin
    // could not reach pending sales — and under the at-till verification
    // flow the Owner must always remain an authorized verifier, so 'admin'
    // is folded into 'owner_admin'. Valid values are now 'immediate'
    // (verification off), 'owner', and 'owner_admin'.
    if (oldVersion < 22) {
      await db.execute(
        "UPDATE settings SET gcash_verification_mode = 'owner_admin' WHERE gcash_verification_mode = 'admin'",
      );
    }

    // Migration from v22 → v23: add the session-expiry warning threshold.
    // Default 30 seconds; always clamped below the inactivity timeout at
    // runtime by SessionSettingsService.
    if (oldVersion < 23) {
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN session_warning_seconds INTEGER NOT NULL DEFAULT 30',
        );
      } catch (_) {
        // Column may already exist.
      }
    }

    // Migration from v23 → v24: add the generated GCash QR preview path.
    // Nullable because older uploads have no preview and the app falls back
    // to the original uploaded image.
    if (oldVersion < 24) {
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN gcash_qr_preview_path TEXT',
        );
      } catch (_) {
        // Column may already exist.
      }
    }

    // Migration from v24 → v25: add automatic backup schedule columns.
    if (oldVersion < 25) {
      final autoBackupColumns = [
        'auto_backup_enabled INTEGER NOT NULL DEFAULT 0',
        'auto_backup_frequency TEXT NOT NULL DEFAULT \'7_days\'',
        'auto_backup_time TEXT NOT NULL DEFAULT \'02:00\'',
        'auto_backup_last_run TEXT',
      ];
      for (final column in autoBackupColumns) {
        try {
          await db.execute('ALTER TABLE settings ADD COLUMN $column');
        } catch (_) {
          // Column may already exist.
        }
      }
    }

    // Migration from v25 → v26: add the automatic backup schedule anchor.
    // The anchor records when the schedule was saved so the next run is a
    // fixed date instead of drifting with the current date. Backfill from
    // the last run (or the row's last update) so existing schedules keep a
    // stable anchor immediately.
    if (oldVersion < 26) {
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN auto_backup_scheduled_at TEXT',
        );
      } catch (_) {
        // Column may already exist.
      }
      try {
        await db.execute(
          'UPDATE settings SET auto_backup_scheduled_at = '
          'COALESCE(auto_backup_last_run, updated_at) '
          'WHERE auto_backup_scheduled_at IS NULL',
        );
      } catch (_) {
        // Backfill is best-effort; the service self-heals a missing anchor.
      }
    }

    // Migration from v26 → v27: raise the GCash reference minimum length
    // floor to 13 — a real GCash reference is 13 digits. Stored values at
    // or above the floor (custom lengths the owner deliberately set) are
    // preserved.
    if (oldVersion < 27) {
      try {
        await db.execute(
          'UPDATE settings SET gcash_reference_min_length = '
          '${AppConstants.minGcashReferenceLength} '
          'WHERE gcash_reference_min_length < '
          '${AppConstants.minGcashReferenceLength}',
        );
      } catch (_) {
        // Column may not exist on a damaged database; the model default
        // still applies at read time.
      }
    }

    // Migration from v27 → v28: drop the vestigial per-user override
    // columns. The session inactivity timeout and the AI daily quota are
    // global settings now — `users.inactivity_timeout_minutes` and
    // `ai_quota.daily_quota` are no longer read or written.
    if (oldVersion < 28) {
      await _migrateV28(db);
    }

    // Migration from v28 → v29: drop dead columns that are never read or
    // never populated — users.color_preference, settings.theme (the real
    // theme lives in SharedPreferences), attachments.is_active (lifecycle
    // is tracked by deleted_at), export_history.thumbnail_path (thumbnails
    // were never generated), and notifications.read_at (written but never
    // read — is_read alone carries the state).
    if (oldVersion < 29) {
      await _migrateV29(db);
    }

    // Migration from v29 → v30: add payment-specific merchant identity
    // columns to settings (gcash_merchant_name / gcash_merchant_phone).
    // These were previously aliased onto store_name / store_phone, which
    // coupled Payment Settings to Store Information. The existing values
    // are seeded from the store columns so users keep their current
    // payment identity; the two identities are independent from here on.
    // The `ai_chat_messages` table itself is created by the _createTables
    // call at the end of this method.
    if (oldVersion < 30) {
      await _migrateV30(db);
    }

    // Create any tables that were introduced after the backup's original
    // version but do not have an explicit migration block above (e.g.
    // `announcements`, `ai_usage`).  All CREATE statements in _createTables
    // use IF NOT EXISTS, so this is idempotent and will not overwrite or
    // recreate tables that already exist.
    await _createTables(db);
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
          final bytes = await raf.read(512);
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

  /// Migration from v17 → v18: extend export_history for report submissions.
  ///
  /// Adds status/submission/viewed metadata, soft-delete, file size,
  /// thumbnail path and a human-readable report number. Existing rows default
  /// to status 'generated' and retain their original created_at date.
  Future<void> _migrateExportHistoryV18(Database db) async {
    const newColumns = [
      'status',
      'submitted_at',
      'viewed_at',
      'file_size',
      'thumbnail_path',
      'report_number',
      'deleted_at',
    ];

    for (final column in newColumns) {
      try {
        await db.execute('ALTER TABLE export_history ADD COLUMN $column TEXT');
      } catch (_) {
        // Column may already exist; continue with the rest.
      }
    }

    // Backfill existing rows without a status so the UI never sees null.
    try {
      await db.execute(
        "UPDATE export_history SET status = 'generated' WHERE status IS NULL",
      );
    } catch (_) {
      // Ignore; the column may not have been added.
    }
  }

  /// Migration from v18 → v19: add GCash QR merchant image storage to settings.
  Future<void> _migrateSettingsV19(Database db) async {
    const newColumns = [
      'gcash_qr_image_path',
      'gcash_qr_image_type',
    ];

    for (final column in newColumns) {
      try {
        await db.execute('ALTER TABLE settings ADD COLUMN $column TEXT');
      } catch (_) {
        // Column may already exist; continue with the rest.
      }
    }
  }

  Future<void> _createAttachmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_name TEXT NOT NULL,
        attachment_type TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_entity '
      'ON attachments(entity_type, entity_id, deleted_at)',
    );
  }

  /// Migration from v19 → v20: add generic attachments, extend trash with
  /// snapshot JSON, and add attachment columns to existing tables.
  Future<void> _migrateV20(Database db) async {
    // Add snapshot_json to existing trash table.
    try {
      await db.execute('ALTER TABLE trash ADD COLUMN snapshot_json TEXT');
    } catch (_) {
      // Column may already exist.
    }

    // Add attachment count and size columns for UI and lifecycle tracking.
    try {
      await db.execute('ALTER TABLE trash ADD COLUMN attachment_count INTEGER NOT NULL DEFAULT 0');
    } catch (_) {
      // Column may already exist.
    }
    try {
      await db.execute('ALTER TABLE trash ADD COLUMN total_size_bytes INTEGER NOT NULL DEFAULT 0');
    } catch (_) {
      // Column may already exist.
    }

    // Create attachments table for new installs and upgrades.
    await _createAttachmentsTable(db);
  }

  /// Migration from v20 → v21: add per-user and store inactivity timeout
  /// configuration.
  Future<void> _migrateV21(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE users ADD COLUMN inactivity_timeout_minutes INTEGER',
      );
    } catch (_) {
      // Column may already exist.
    }

    try {
      await db.execute(
        'ALTER TABLE settings ADD COLUMN inactivity_timeout_minutes INTEGER NOT NULL DEFAULT 15',
      );
    } catch (_) {
      // Column may already exist.
    }
  }

  /// Migration from v27 → v28: drop the per-user override columns that are
  /// now dead — `ai_quota.daily_quota` (the quota limit is the global
  /// `settings.ai_daily_quota`) and `users.inactivity_timeout_minutes`
  /// (the session timeout is the global `settings.inactivity_timeout_minutes`).
  Future<void> _migrateV28(Database db) async {
    try {
      await db.execute('ALTER TABLE ai_quota DROP COLUMN daily_quota');
    } catch (_) {
      // Older SQLite builds do not support DROP COLUMN; rebuild the table.
      await _rebuildAiQuotaWithoutDailyQuota(db);
    }

    try {
      await db.execute(
        'ALTER TABLE users DROP COLUMN inactivity_timeout_minutes',
      );
    } catch (_) {
      // Older SQLite builds do not support DROP COLUMN; rebuild the table.
      await _rebuildUsersWithoutInactivityTimeout(db);
    }
  }

  /// Recreates ai_quota without the daily_quota column for SQLite builds
  /// that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildAiQuotaWithoutDailyQuota(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE ai_quota_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        daily_usage INTEGER NOT NULL DEFAULT 0,
        quota_date TEXT NOT NULL,
        last_reset_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT INTO ai_quota_new (id, user_id, daily_usage, quota_date, last_reset_at)
      SELECT id, user_id, daily_usage, quota_date, last_reset_at FROM ai_quota
    ''');
    await db.execute('DROP TABLE ai_quota');
    await db.execute('ALTER TABLE ai_quota_new RENAME TO ai_quota');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_quota_user ON ai_quota(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_quota_date ON ai_quota(quota_date)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Exposes the v28 migration so tests can exercise it against an
  /// old-schema database.
  @visibleForTesting
  Future<void> runV28MigrationForTest(Database db) => _migrateV28(db);

  /// Exposes the v28 table-rebuild fallback so tests can validate its SQL
  /// even on SQLite builds where DROP COLUMN already succeeds.
  @visibleForTesting
  Future<void> runV28RebuildFallbackForTest(Database db) async {
    await _rebuildAiQuotaWithoutDailyQuota(db);
    await _rebuildUsersWithoutInactivityTimeout(db);
  }

  /// Migration from v28 → v29: drop dead columns. See the _onUpgrade
  /// comment for why each column is unused.
  Future<void> _migrateV29(Database db) async {
    try {
      await db.execute('ALTER TABLE users DROP COLUMN color_preference');
    } catch (_) {
      // Older SQLite builds do not support DROP COLUMN; rebuild the table.
      await _rebuildUsersV29(db);
    }

    try {
      await db.execute('ALTER TABLE settings DROP COLUMN theme');
    } catch (_) {
      await _rebuildSettingsV29(db);
    }

    try {
      await db.execute('ALTER TABLE attachments DROP COLUMN is_active');
    } catch (_) {
      await _rebuildAttachmentsV29(db);
    }

    try {
      await db.execute('ALTER TABLE export_history DROP COLUMN thumbnail_path');
    } catch (_) {
      await _rebuildExportHistoryV29(db);
    }

    try {
      await db.execute('ALTER TABLE notifications DROP COLUMN read_at');
    } catch (_) {
      await _rebuildNotificationsV29(db);
    }
  }

  /// Recreates users without the color_preference column for SQLite builds
  /// that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildUsersV29(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE users_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        pin TEXT,
        pin_length INTEGER,
        role TEXT NOT NULL,
        full_name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
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
      INSERT INTO users_new (id, username, password_hash, pin, pin_length, role,
        full_name, is_active, profile_image_path, last_login, created_at,
        updated_at, deleted_at, must_change_password, has_changed_username)
      SELECT id, username, password_hash, pin, pin_length, role, full_name,
        is_active, profile_image_path, last_login, created_at, updated_at,
        deleted_at, must_change_password, has_changed_username
      FROM users
    ''');
    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_new RENAME TO users');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active '
      'ON users(username) WHERE deleted_at IS NULL',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Recreates settings without the theme column for SQLite builds that
  /// lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildSettingsV29(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE settings_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_name TEXT NOT NULL,
        store_address TEXT,
        store_phone TEXT,
        currency TEXT NOT NULL DEFAULT 'PHP',
        receipt_footer TEXT,
        groq_api_key TEXT,
        groq_model TEXT,
        gcash_enabled INTEGER NOT NULL DEFAULT 1,
        gcash_reference_required INTEGER NOT NULL DEFAULT 1,
        gcash_customer_name_requirement TEXT NOT NULL DEFAULT 'optional',
        gcash_payment_proof_requirement TEXT NOT NULL DEFAULT 'optional',
        gcash_verification_mode TEXT NOT NULL DEFAULT 'immediate',
        gcash_reference_min_length INTEGER NOT NULL DEFAULT ${AppConstants.minGcashReferenceLength},
        gcash_qr_image_path TEXT,
        gcash_qr_image_type TEXT,
        gcash_qr_preview_path TEXT,
        ai_daily_quota INTEGER NOT NULL DEFAULT ${AppConstants.defaultDailyAIQuota},
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
      INSERT INTO settings_new (id, store_name, store_address, store_phone,
        currency, receipt_footer, groq_api_key, groq_model, gcash_enabled,
        gcash_reference_required, gcash_customer_name_requirement,
        gcash_payment_proof_requirement, gcash_verification_mode,
        gcash_reference_min_length, gcash_qr_image_path, gcash_qr_image_type,
        gcash_qr_preview_path, ai_daily_quota, inactivity_timeout_minutes,
        session_warning_seconds, auto_backup_enabled, auto_backup_frequency,
        auto_backup_time, auto_backup_last_run, auto_backup_scheduled_at,
        created_at, updated_at)
      SELECT id, store_name, store_address, store_phone, currency,
        receipt_footer, groq_api_key, groq_model, gcash_enabled,
        gcash_reference_required, gcash_customer_name_requirement,
        gcash_payment_proof_requirement, gcash_verification_mode,
        gcash_reference_min_length, gcash_qr_image_path, gcash_qr_image_type,
        gcash_qr_preview_path, ai_daily_quota, inactivity_timeout_minutes,
        session_warning_seconds, auto_backup_enabled, auto_backup_frequency,
        auto_backup_time, auto_backup_last_run, auto_backup_scheduled_at,
        created_at, updated_at
      FROM settings
    ''');
    await db.execute('DROP TABLE settings');
    await db.execute('ALTER TABLE settings_new RENAME TO settings');
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Recreates attachments without the is_active column for SQLite builds
  /// that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildAttachmentsV29(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE attachments_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_name TEXT NOT NULL,
        attachment_type TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO attachments_new (id, entity_type, entity_id, file_path,
        mime_type, file_name, attachment_type, deleted_at, created_at)
      SELECT id, entity_type, entity_id, file_path, mime_type, file_name,
        attachment_type, deleted_at, created_at
      FROM attachments
    ''');
    await db.execute('DROP TABLE attachments');
    await db.execute('ALTER TABLE attachments_new RENAME TO attachments');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_entity '
      'ON attachments(entity_type, entity_id, deleted_at)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Recreates export_history without the thumbnail_path column for SQLite
  /// builds that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildExportHistoryV29(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE export_history_new (
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
        report_number TEXT,
        deleted_at TEXT,
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');
    await db.execute('''
      INSERT INTO export_history_new (id, report_type, file_format, file_path,
        date_range_start, date_range_end, created_by, created_at, status,
        submitted_at, viewed_at, file_size, report_number, deleted_at)
      SELECT id, report_type, file_format, file_path, date_range_start,
        date_range_end, created_by, created_at, status, submitted_at,
        viewed_at, file_size, report_number, deleted_at
      FROM export_history
    ''');
    await db.execute('DROP TABLE export_history');
    await db.execute('ALTER TABLE export_history_new RENAME TO export_history');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_export_history_date '
      'ON export_history(created_at)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Recreates notifications without the read_at column for SQLite builds
  /// that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildNotificationsV29(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE notifications_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT,
        user_id INTEGER,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
    await db.execute('''
      INSERT INTO notifications_new (id, title, message, type, user_id,
        is_read, created_at)
      SELECT id, title, message, type, user_id, is_read, created_at
      FROM notifications
    ''');
    await db.execute('DROP TABLE notifications');
    await db.execute('ALTER TABLE notifications_new RENAME TO notifications');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_user '
      'ON notifications(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_read '
      'ON notifications(is_read)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Exposes the v29 migration so tests can exercise it against an
  /// old-schema database.
  @visibleForTesting
  Future<void> runV29MigrationForTest(Database db) => _migrateV29(db);

  /// Migration from v29 → v30: add the payment-side merchant identity
  /// columns (settings.gcash_merchant_name / gcash_merchant_phone) and seed
  /// them from the store columns so existing installs keep their current
  /// payment identity. The `ai_chat_messages` table is created separately
  /// by the _createTables call at the end of _onUpgrade.
  Future<void> _migrateV30(Database db) async {
    for (final column in [
      'gcash_merchant_name TEXT',
      'gcash_merchant_phone TEXT',
    ]) {
      try {
        await db.execute('ALTER TABLE settings ADD COLUMN $column');
      } catch (_) {
        // Column may already exist.
      }
    }
    try {
      await db.execute('''
        UPDATE settings
        SET gcash_merchant_name = store_name,
            gcash_merchant_phone = store_phone
        WHERE (gcash_merchant_name IS NULL OR gcash_merchant_name = '')
          AND store_name IS NOT NULL
      ''');
      await db.execute('''
        UPDATE settings
        SET gcash_merchant_phone = store_phone
        WHERE (gcash_merchant_phone IS NULL OR gcash_merchant_phone = '')
          AND store_phone IS NOT NULL
      ''');
    } catch (_) {
      // Seeding is best-effort; empty merchant fields are valid.
    }
  }

  Future<void> runV30MigrationForTest(Database db) => _migrateV30(db);

  /// Exposes the v29 table-rebuild fallbacks so tests can validate their
  /// SQL even on SQLite builds where DROP COLUMN already succeeds.
  @visibleForTesting
  Future<void> runV29RebuildFallbackForTest(Database db) async {
    await _rebuildUsersV29(db);
    await _rebuildSettingsV29(db);
    await _rebuildAttachmentsV29(db);
    await _rebuildExportHistoryV29(db);
    await _rebuildNotificationsV29(db);
  }

  /// Recreates users without the inactivity_timeout_minutes column for
  /// SQLite builds that lack ALTER TABLE ... DROP COLUMN (pre-3.35).
  Future<void> _rebuildUsersWithoutInactivityTimeout(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.execute('''
      CREATE TABLE users_new (
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
      INSERT INTO users_new (id, username, password_hash, pin, pin_length, role,
        full_name, is_active, color_preference, profile_image_path, last_login,
        created_at, updated_at, deleted_at, must_change_password,
        has_changed_username)
      SELECT id, username, password_hash, pin, pin_length, role, full_name,
        is_active, color_preference, profile_image_path, last_login, created_at,
        updated_at, deleted_at, must_change_password, has_changed_username
      FROM users
    ''');
    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_new RENAME TO users');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active '
      'ON users(username) WHERE deleted_at IS NULL',
    );
    await db.execute('PRAGMA foreign_keys = ON');
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
    // gcash_merchant_name / gcash_merchant_phone are the payment-side
    // merchant identity configured in Payment Settings — deliberately
    // separate from store_name / store_phone (Store Information). The
    // decoded QR payload remains authoritative at checkout; these are a
    // fallback for QRs that do not encode merchant details.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_name TEXT NOT NULL,
        store_address TEXT,
        store_phone TEXT,
        currency TEXT NOT NULL DEFAULT 'PHP',
        receipt_footer TEXT,
        groq_api_key TEXT,
        groq_model TEXT,
        gcash_enabled INTEGER NOT NULL DEFAULT 1,
        gcash_reference_required INTEGER NOT NULL DEFAULT 1,
        gcash_customer_name_requirement TEXT NOT NULL DEFAULT 'optional',
        gcash_payment_proof_requirement TEXT NOT NULL DEFAULT 'optional',
        gcash_verification_mode TEXT NOT NULL DEFAULT 'immediate',
        gcash_reference_min_length INTEGER NOT NULL DEFAULT ${AppConstants.minGcashReferenceLength},
        gcash_qr_image_path TEXT,
        gcash_qr_image_type TEXT,
        gcash_qr_preview_path TEXT,
        gcash_merchant_name TEXT,
        gcash_merchant_phone TEXT,
        ai_daily_quota INTEGER NOT NULL DEFAULT ${AppConstants.defaultDailyAIQuota},
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


    // AI quota table — per-user usage counter only; the quota limit is the
    // global settings.ai_daily_quota value.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_quota (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        daily_usage INTEGER NOT NULL DEFAULT 0,
        quota_date TEXT NOT NULL,
        last_reset_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    // AI chat history — the persisted advisor conversation. Unlike
    // `ai_usage` (a quota/audit log of query→response pairs), this table
    // stores every message so the chat survives app restarts. Rows are
    // scoped per user and only deleted when the user explicitly starts a
    // new conversation (or the user account itself is deleted).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        is_user INTEGER NOT NULL,
        text TEXT NOT NULL,
        is_error INTEGER NOT NULL DEFAULT 0,
        response_json TEXT,
        follow_ups_json TEXT,
        created_at TEXT NOT NULL,
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
        snapshot_json TEXT,
        attachment_count INTEGER NOT NULL DEFAULT 0,
        total_size_bytes INTEGER NOT NULL DEFAULT 0,
        deleted_by INTEGER,
        deleted_at TEXT NOT NULL,
        expires_at TEXT,
        FOREIGN KEY (deleted_by) REFERENCES users(id)
      )
    ''');

    // Attachments table
    await _createAttachmentsTable(db);

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
        status TEXT,
        submitted_at TEXT,
        viewed_at TEXT,
        file_size INTEGER,
        report_number TEXT,
        deleted_at TEXT,
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_user '
      'ON ai_chat_messages(user_id, id)',
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Closes the database only if it is currently open.
  ///
  /// Unlike [close], this never tries to open a database that is not already
  /// cached. This is important during restore, when the file at the database
  /// path may be in a transient/corrupt state and opening it could fail.
  Future<void> closeIfOpen() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Returns the filesystem path of the Pinoy POS database without opening it.
  Future<String> get databasePath async {
    final databasePath = await getDatabasesPath();
    return join(databasePath, _dbName);
  }

  /// Resets the singleton state for testing.  Closes any open database,
  /// clears the cached instance, and assigns a unique database filename for
  /// the next test.  It also deletes the previous test database file so test
  /// runs do not accumulate temp files.
  ///
  /// The unique filename avoids the Windows file-lock race that occurs when
  /// the same database file is closed and immediately reopened by the next
  /// test in the same test file.
  @visibleForTesting
  static Future<void> resetForTest() async {
    final previousName = _testDbName;

    await _database?.close();
    _database = null;

    if (previousName != null) {
      try {
        final databasePath = await getDatabasesPath();
        final previousPath = join(databasePath, previousName);
        final file = File(previousPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore deletion failures caused by a still-locked handle; the
        // unique filename means a stale file cannot affect the next test.
      }
    }

    _testDbName = 'pinoy_pos_test_${_testRun++}.db';
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
      await txn.execute('DROP TABLE IF EXISTS ai_chat_messages');
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
