import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:pinoy_pos/core/constants.dart';

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
    // Handle migrations when version changes
    if (oldVersion < newVersion) {
      // Add migration logic here when needed
    }
  }

  Future<void> _createTables(Database db) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        pin TEXT,
        role TEXT NOT NULL,
        full_name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        last_login TEXT,
        created_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    // Categories table
    await db.execute('''
      CREATE TABLE categories (
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
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 10,
        barcode TEXT UNIQUE,
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
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL NOT NULL,
        cash_received REAL NOT NULL,
        change REAL NOT NULL,
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
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Stock history table
    await db.execute('''
      CREATE TABLE stock_history (
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

    // Announcements table
    await db.execute('''
      CREATE TABLE announcements (
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
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_name TEXT NOT NULL,
        store_address TEXT,
        store_phone TEXT,
        currency TEXT NOT NULL DEFAULT 'PHP',
        receipt_footer TEXT,
        theme TEXT,
        accent_color TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Activity log table
    await db.execute('''
      CREATE TABLE activity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
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
      CREATE TABLE ai_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        query TEXT NOT NULL,
        response TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Create indexes
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX idx_products_active ON products(is_active)');
    await db.execute('CREATE INDEX idx_sales_user ON sales(user_id)');
    await db.execute('CREATE INDEX idx_sales_date ON sales(created_at)');
    await db.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');
    await db.execute('CREATE INDEX idx_sale_items_product ON sale_items(product_id)');
    await db.execute('CREATE INDEX idx_stock_history_product ON stock_history(product_id)');
    await db.execute('CREATE INDEX idx_stock_history_date ON stock_history(created_at)');
    await db.execute('CREATE INDEX idx_notifications_user ON notifications(user_id)');
    await db.execute('CREATE INDEX idx_notifications_read ON notifications(is_read)');
    await db.execute('CREATE INDEX idx_activity_log_user ON activity_log(user_id)');
    await db.execute('CREATE INDEX idx_activity_log_date ON activity_log(created_at)');
    await db.execute('CREATE INDEX idx_ai_usage_user ON ai_usage(user_id)');
    await db.execute('CREATE INDEX idx_ai_usage_date ON ai_usage(created_at)');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // Transaction support
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }
}
