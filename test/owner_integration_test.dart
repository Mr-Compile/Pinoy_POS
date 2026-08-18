import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/stock_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart' as ai;
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:pinoy_pos/data/repositories/announcement_repository.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';

/// Integration tests that verify the full Owner feature chain:
///
///   Screen → Service → Repository → DAO → SQLite
///
/// Each test authenticates as the seeded owner and exercises every
/// service method that the corresponding Owner screen would call.
/// This catches runtime errors, RBAC issues, and database problems
/// that would cause "Riverpod errors" in the UI.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTest();
    final dbPath = p.join(await getDatabasesPath(), AppConstants.databaseName);
    final file = File(dbPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // File may still be locked on Windows; the database will re-open
        // on top of the existing file.
      }
    }
    final dbHelper = DatabaseHelper();
    await dbHelper.database;
    final seeder = DatabaseSeeder();
    await seeder.seed();

    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper().close();
  });

  /// Authenticate as the seeded owner.
  Future<User> authAsOwner() async {
    final authService = AuthService();
    final ok = await authService.login('owner', 'owner123');
    if (!ok) {
      throw StateError('Owner login failed');
    }
    return authService.currentUser!;
  }

  // ─── Dashboard / Reports ──────────────────────────────────────────────

  group('Owner Dashboard / Reports chain', () {
    test('ReportService returns metrics without throwing', () async {
      await authAsOwner();
      final svc = ReportService();

      expect(await svc.getTodaySales(), isA<double>());
      expect(await svc.getMonthSales(), isA<double>());
      expect(await svc.getLowStockCount(), isA<int>());
      expect(await svc.getTotalProducts(), isA<int>());
    });

    test('ReportService does not expose admin-only metrics to owner',
        () async {
      await authAsOwner();
      final svc = ReportService();

      // Owner does NOT have manage_users or backup_restore.
      expect(await svc.getTotalUsers(), 0);
      expect(await svc.getActiveUsers(), 0);
      expect(await svc.getLastBackupPath(), isNull);
      expect(await svc.getLastBackupDate(), isNull);
    });
  });

  // ─── Products ─────────────────────────────────────────────────────────

  group('Owner Products chain', () {
    test('ProductService CRUD works end-to-end', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final categorySvc = CategoryService();

      // Create a category first (needed for product).
      final cat = Category(name: 'Beverages', createdAt: DateTime.now());
      await categorySvc.createCategory(cat);
      final cats = await categorySvc.getActiveCategories();
      expect(cats, isNotEmpty);
      final categoryId = cats.first.id!;

      // Create product.
      final product = Product(
        name: 'Coke 500ml',
        price: 25.0,
        stock: 100,
        minStock: 10,
        categoryId: categoryId,
        createdAt: DateTime.now(),
      );
      final created = await productSvc.createProduct(product);
      expect(created, isTrue);

      // Read active products.
      final active = await productSvc.getActiveProducts();
      expect(active.any((p) => p.name == 'Coke 500ml'), isTrue);

      // Update.
      final fetched = active.firstWhere((p) => p.name == 'Coke 500ml');
      final updated = await productSvc.updateProduct(
        fetched.copyWith(price: 30.0),
      );
      expect(updated, isTrue);

      // Verify update persisted.
      final byId = await productSvc.getProductById(fetched.id!);
      expect(byId!.price, 30.0);

      // Soft delete.
      final deleted = await productSvc.deleteProduct(fetched.id!);
      expect(deleted, isTrue);

      // Should not appear in active list.
      final activeAfter = await productSvc.getActiveProducts();
      expect(activeAfter.any((p) => p.id == fetched.id), isFalse);

      // Restore.
      final restored = await productSvc.restoreProduct(fetched.id!);
      expect(restored, isTrue);

      final activeFinal = await productSvc.getActiveProducts();
      expect(activeFinal.any((p) => p.id == fetched.id), isTrue);
    });

    test('ProductRepository getDeleted works (for Trash)', () async {
      await authAsOwner();
      final repo = ProductRepository();
      expect(await repo.getDeleted(), isEmpty);
    });
  });

  // ─── Categories ───────────────────────────────────────────────────────

  group('Owner Categories chain', () {
    test('CategoryService CRUD works end-to-end', () async {
      await authAsOwner();
      final svc = CategoryService();

      // Create.
      final cat = Category(name: 'Snacks', createdAt: DateTime.now());
      expect(await svc.createCategory(cat), isTrue);

      // Read.
      final active = await svc.getActiveCategories();
      expect(active.any((c) => c.name == 'Snacks'), isTrue);

      // Update.
      final fetched = active.firstWhere((c) => c.name == 'Snacks');
      expect(
        await svc.updateCategory(fetched.copyWith(name: 'Snacks & Chips')),
        isTrue,
      );

      // Verify.
      final byId = await svc.getCategoryById(fetched.id!);
      expect(byId!.name, 'Snacks & Chips');

      // Delete.
      expect(await svc.deleteCategory(fetched.id!), isTrue);

      // Should not appear in active list.
      final after = await svc.getActiveCategories();
      expect(after.any((c) => c.id == fetched.id), isFalse);

      // Restore.
      expect(await svc.restoreCategory(fetched.id!), isTrue);
    });

    test('CategoryRepository getDeleted works (for Trash)', () async {
      await authAsOwner();
      final repo = CategoryRepository();
      expect(await repo.getDeleted(), isEmpty);
    });
  });

  // ─── Stock ────────────────────────────────────────────────────────────

  group('Owner Stock chain', () {
    test('StockService add and adjust work', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final stockSvc = StockService();

      // Create a product.
      final product = Product(
        name: 'Test Item',
        price: 10.0,
        stock: 50,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      await productSvc.createProduct(product);
      final fetched = (await productSvc.getActiveProducts())
          .firstWhere((p) => p.name == 'Test Item');

      // Add stock.
      final addOk = await stockSvc.addStock(fetched.id!, 10, 'Restock');
      expect(addOk, isTrue);

      // Verify stock increased.
      final afterAdd = await productSvc.getProductById(fetched.id!);
      expect(afterAdd!.stock, 60);

      // Adjust stock.
      final adjustOk = await stockSvc.adjustStock(fetched.id!, 30, 'Correction');
      expect(adjustOk, isTrue);

      final afterAdjust = await productSvc.getProductById(fetched.id!);
      expect(afterAdjust!.stock, 30);
    });

    test('StockService prevents negative stock via adjust', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final stockSvc = StockService();

      final product = Product(
        name: 'Neg Test',
        price: 10.0,
        stock: 5,
        minStock: 1,
        createdAt: DateTime.now(),
      );
      await productSvc.createProduct(product);
      final fetched = (await productSvc.getActiveProducts())
          .firstWhere((p) => p.name == 'Neg Test');

      // Adjust to negative should fail.
      final result = await stockSvc.adjustStock(fetched.id!, -1, 'Bad adjust');
      expect(result, isFalse);
    });

    test('StockService getStockHistory returns history', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final stockSvc = StockService();

      final product = Product(
        name: 'History Test',
        price: 10.0,
        stock: 10,
        minStock: 1,
        createdAt: DateTime.now(),
      );
      await productSvc.createProduct(product);
      final fetched = (await productSvc.getActiveProducts())
          .firstWhere((p) => p.name == 'History Test');

      await stockSvc.addStock(fetched.id!, 5, 'Test add');

      final history = await stockSvc.getStockHistory(fetched.id!);
      expect(history, isNotEmpty);
    });
  });

  // ─── Sales / POS ──────────────────────────────────────────────────────

  group('Owner Sales / POS chain', () {
    test('SalesService createSale and voidSale work', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final salesSvc = SalesService();

      // Create a product to sell.
      final product = Product(
        name: 'Sale Item',
        price: 20.0,
        stock: 100,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      await productSvc.createProduct(product);
      final fetched = (await productSvc.getActiveProducts())
          .firstWhere((p) => p.name == 'Sale Item');

      // Create a sale.
      final items = [
        SaleItem(
          saleId: 0,
          productId: fetched.id!,
          quantity: 3,
          unitPrice: 20.0,
          totalPrice: 60.0,
        ),
      ];
      final saleOk = await salesSvc.createSale(
        items: items,
        totalAmount: 60.0,
        cashReceived: 100.0,
      );
      expect(saleOk, isTrue);

      // Verify stock was deducted.
      final afterSale = await productSvc.getProductById(fetched.id!);
      expect(afterSale!.stock, 97);

      // Verify sale appears in list.
      final sales = await salesSvc.getSales();
      expect(sales, isNotEmpty);

      // Void the sale.
      final saleId = sales.first.id!;
      final voidOk = await salesSvc.voidSale(saleId);
      expect(voidOk, isTrue);

      // Verify stock was restored.
      final afterVoid = await productSvc.getProductById(fetched.id!);
      expect(afterVoid!.stock, 100);

      // Verify voided sale does not appear in active list.
      final salesAfter = await salesSvc.getSales();
      expect(salesAfter.any((s) => s.id == saleId), isFalse);
    });

    test('SalesService getTodaySales and getMonthSales work', () async {
      await authAsOwner();
      final svc = SalesService();
      expect(await svc.getTodaySales(), isA<double>());
      expect(await svc.getMonthSales(), isA<double>());
    });
  });

  // ─── Announcements ────────────────────────────────────────────────────

  group('Owner Announcements chain', () {
    test('AnnouncementRepository CRUD works', () async {
      await authAsOwner();
      final repo = AnnouncementRepository();

      // Create.
      final ann = Announcement(
        title: 'Test Announcement',
        content: 'Hello World',
        isPinned: false,
        createdAt: DateTime.now(),
      );
      await repo.insert(ann);

      // Read active.
      final active = await repo.getActiveAnnouncements();
      expect(active.any((a) => a.title == 'Test Announcement'), isTrue);

      // Update.
      final fetched = active.firstWhere((a) => a.title == 'Test Announcement');
      await repo.update(fetched.copyWith(title: 'Updated Title'));

      // Soft delete.
      await repo.softDelete(fetched.id!);

      // Should not appear in active.
      final after = await repo.getActiveAnnouncements();
      expect(after.any((a) => a.id == fetched.id), isFalse);

      // Should appear in deleted.
      final deleted = await repo.getDeleted();
      expect(deleted.any((a) => a.id == fetched.id), isTrue);

      // Restore.
      await repo.restore(fetched.id!);
      final restored = await repo.getActiveAnnouncements();
      expect(restored.any((a) => a.id == fetched.id), isTrue);
    });
  });

  // ─── Activity Logs ────────────────────────────────────────────────────

  group('Owner Activity Logs chain', () {
    test('ActivityLogService logs and retrieves activities', () async {
      await authAsOwner();
      final svc = ActivityLogService();

      await svc.logActivity(
        action: 'TEST_ACTION',
        entity: 'test',
        details: 'Integration test',
      );

      final activities = await svc.getRecentActivities();
      expect(activities.any((a) => a.action == 'TEST_ACTION'), isTrue);
    });
  });

  // ─── Settings ─────────────────────────────────────────────────────────

  group('Owner Settings chain', () {
    test('SettingsService getSettings and updateSettings work', () async {
      await authAsOwner();
      final svc = SettingsService();

      final settings = await svc.getSettings();
      expect(settings.storeName, isNotEmpty);

      final updated = await svc.updateSettings(
        settings.copyWith(storeName: 'My New Store'),
      );
      expect(updated, isTrue);

      // Verify persistence by creating a new service instance.
      final svc2 = SettingsService();
      final reloaded = await svc2.getSettings();
      expect(reloaded.storeName, 'My New Store');
    });
  });

  // ─── AI Usage ─────────────────────────────────────────────────────────

  group('Owner AI Advisor chain', () {
    test('AIUsageService records and counts queries', () async {
      await authAsOwner();
      final svc = ai.AIUsageService();

      // Record a query.
      final ok = await svc.recordQuery('What are my top products?', null);
      expect(ok, isTrue);

      // Check today's count.
      final count = await svc.getTodayUsageCount();
      expect(count, greaterThanOrEqualTo(1));
    });
  });

  // ─── Notifications ────────────────────────────────────────────────────

  group('Owner Notifications chain', () {
    test('NotificationService creates and lists notifications', () async {
      await authAsOwner();
      final svc = NotificationService();

      await svc.createNotification(
        title: 'Test Notification',
        message: 'This is a test',
        type: 'info',
      );

      final notifications = await svc.getNotifications();
      expect(notifications.any((n) => n.title == 'Test Notification'), isTrue);
    });
  });

  // ─── Trash ────────────────────────────────────────────────────────────

  group('Owner Trash chain', () {
    test('Deleted products and categories appear in trash', () async {
      await authAsOwner();
      final productSvc = ProductService();
      final categorySvc = CategoryService();
      final productRepo = ProductRepository();
      final categoryRepo = CategoryRepository();

      // Create and delete a product.
      final product = Product(
        name: 'Trash Product',
        price: 10.0,
        stock: 5,
        createdAt: DateTime.now(),
      );
      await productSvc.createProduct(product);
      final fetched = (await productSvc.getActiveProducts())
          .firstWhere((p) => p.name == 'Trash Product');
      await productSvc.deleteProduct(fetched.id!);

      // Should appear in deleted.
      final deletedProducts = await productRepo.getDeleted();
      expect(deletedProducts.any((p) => p.id == fetched.id), isTrue);

      // Create and delete a category.
      final cat = Category(name: 'Trash Cat', createdAt: DateTime.now());
      await categorySvc.createCategory(cat);
      final fetchedCat = (await categorySvc.getActiveCategories())
          .firstWhere((c) => c.name == 'Trash Cat');
      await categorySvc.deleteCategory(fetchedCat.id!);

      final deletedCats = await categoryRepo.getDeleted();
      expect(deletedCats.any((c) => c.id == fetchedCat.id), isTrue);
    });
  });

  // ─── RBAC ─────────────────────────────────────────────────────────────

  group('Owner RBAC', () {
    test('Owner has all expected permissions', () async {
      await authAsOwner();
      final sm = SessionManager();

      const expected = [
        'view_dashboard', 'view_pos', 'view_products', 'edit_products',
        'delete_products', 'view_categories', 'edit_categories',
        'delete_categories', 'view_stock', 'add_stock', 'adjust_stock',
        'view_sales', 'create_sales', 'void_sales', 'view_reports',
        'export_reports', 'view_announcements', 'manage_announcements',
        'view_trash', 'restore_trash', 'view_activity_logs',
        'view_ai_advisor', 'view_settings', 'edit_settings',
        'view_notifications', 'view_profile', 'view_more',
      ];

      for (final perm in expected) {
        expect(sm.hasPermission(perm), isTrue, reason: 'Missing: $perm');
      }
    });

    test('Owner does NOT have admin-only permissions', () async {
      await authAsOwner();
      final sm = SessionManager();

      const forbidden = [
        'manage_users', 'edit_users', 'delete_users',
        'reset_password', 'toggle_user_active', 'backup_restore',
      ];

      for (final perm in forbidden) {
        expect(sm.hasPermission(perm), isFalse, reason: 'Should not have: $perm');
      }
    });
  });

  // ─── Auth / Session ───────────────────────────────────────────────────

  group('Auth / Session chain', () {
    test('AuthService login and restoreSession work for owner', () async {
      final authService = AuthService();
      final ok = await authService.login('owner', 'owner123');
      expect(ok, isTrue);
      expect(authService.currentUser, isNotNull);
      expect(authService.currentUser!.role, UserRole.owner);

      // Restore session.
      final authService2 = AuthService();
      final restored = await authService2.restoreSession();
      expect(restored, isTrue);
      expect(authService2.currentUser, isNotNull);
      expect(authService2.currentUser!.role, UserRole.owner);
    });

    test('AuthService logout clears session', () async {
      final authService = AuthService();
      await authService.login('owner', 'owner123');
      expect(authService.isAuthenticated, isTrue);

      await authService.logout();
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentUser, isNull);
    });
  });
}
