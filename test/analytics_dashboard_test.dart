import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/reporting_period.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/sales_analytics_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';

/// Integration tests for the new period-aware analytics and dashboard
/// services.
///
/// Verifies that:
///   - confirmed sales are counted by [SalesAnalyticsService]
///   - cancelled / soft-deleted sales are excluded
///   - Staff analytics are scoped to the current user
///   - [DashboardService] surfaces the same analytics data
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

    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    final dbHelper = DatabaseHelper();
    await dbHelper.close();
    SessionManager.resetForTest();
  });

  group('SalesAnalyticsService', () {
    test('returns correct confirmed-only totals for the current day', () async {
      await _login('owner');
      final product = await _createProduct('Adobo Rice', 85.0, 20);

      final success = await _createSale(product, 3);
      expect(success, isTrue);

      final analytics = await SalesAnalyticsService().getAnalytics(
        ReportingPeriod.today,
      );

      expect(analytics.totalSales, product.price * 3);
      expect(analytics.transactionCount, 1);
      expect(analytics.averageTransaction, 255.0);
      expect(analytics.itemsSold, 3);
      expect(analytics.trend.isNotEmpty, isTrue);
      expect(analytics.paymentBreakdown, isNotEmpty);
      expect(analytics.paymentBreakdown.first.method, 'Cash');
      expect(analytics.paymentBreakdown.first.total, 255.0);
      expect(analytics.topProducts, isNotEmpty);
      expect(analytics.topProducts.first.productName, 'Adobo Rice');
      expect(analytics.topProducts.first.totalQuantity, 3);
      expect(analytics.categorySales, isNotEmpty);
      expect(analytics.peakSalesPeriod.peakHour, isNotNull);
      expect(analytics.peakSalesPeriod.peakDay, isNotNull);
    });

    test('excludes cancelled and soft-deleted sales', () async {
      await _login('owner');
      final product = await _createProduct('Sisig Meal', 120.0, 20);

      await _createSale(product, 1);
      await _createSale(product, 1);

      // Cancel/soft-delete the second sale.
      final sales = await SaleRepository().getAll();
      final second = sales.first;
      final cancelled = second.copyWith(
        paymentStatus: 'cancelled',
        deletedAt: DateTime.now(),
      );
      await SaleRepository().update(cancelled);

      final analytics = await SalesAnalyticsService().getAnalytics(
        ReportingPeriod.today,
      );

      expect(analytics.totalSales, 120.0);
      expect(analytics.transactionCount, 1);
      expect(analytics.itemsSold, 1);
    });

    test('Staff analytics are scoped to the current user only', () async {
      await _login('owner');
      final product = await _createProduct('Burger Steak', 95.0, 20);

      // Owner makes one sale.
      await _createSale(product, 2);

      // Staff makes a separate sale.
      await _login('staff');
      await _createSale(product, 1);

      final staffAnalytics = await SalesAnalyticsService().getAnalytics(
        ReportingPeriod.today,
      );

      expect(staffAnalytics.totalSales, 95.0);
      expect(staffAnalytics.transactionCount, 1);
      expect(staffAnalytics.itemsSold, 1);
    });
  });

  group('DashboardService', () {
    test('Owner dashboard returns period-aware analytics', () async {
      await _login('owner');
      final product = await _createProduct('Tapsilog', 110.0, 20);
      await _createSale(product, 1);
      await _createSale(product, 1);

      final dashboardData = await DashboardService().getDashboard(
        ReportingPeriod.today,
      );

      expect(dashboardData, isNotNull);
      expect(dashboardData, isA<OwnerDashboardData>());

      final data = dashboardData as OwnerDashboardData;
      expect(data.analytics.totalSales, product.price * 2);
      expect(data.analytics.transactionCount, 2);
      expect(data.recentSales.length, 2);
      expect(data.lowStockProducts, isA<List<Product>>());
    });

    test('Staff dashboard returns own-scoped analytics', () async {
      await _login('owner');
      final product = await _createProduct('Longsilog', 100.0, 20);
      await _createSale(product, 1);

      await _login('staff');
      await _createSale(product, 1);

      final dashboardData = await DashboardService().getDashboard(
        ReportingPeriod.today,
      );

      expect(dashboardData, isNotNull);
      expect(dashboardData, isA<StaffDashboardData>());

      final data = dashboardData as StaffDashboardData;
      expect(data.analytics.totalSales, 100.0);
      expect(data.analytics.transactionCount, 1);
    });
  });
}

Future<void> _login(String username) async {
  final result = await AuthService().login(username, '${username}123');
  expect(result, LoginResult.success);
}

Future<Product> _createProduct(String name, double price, int stock) async {
  final category = await CategoryService().createCategory(
    Category(name: 'Test Category', createdAt: DateTime.now()),
  );
  expect(category, isTrue);

  final categories = await CategoryService().getActiveCategories();
  final categoryId = categories.first.id!;

  final product = Product(
    name: name,
    price: price,
    stock: stock,
    minStock: 5,
    categoryId: categoryId,
    createdAt: DateTime.now(),
  );
  final success = await ProductService().createProduct(product);
  expect(success, isTrue);

  final products = await ProductRepository().getAll();
  return products.firstWhere((p) => p.name == name);
}

Future<bool> _createSale(Product product, int quantity) async {
  final price = product.price;
  final item = SaleItem(
    productId: product.id!,
    quantity: quantity,
    unitPrice: price,
    totalPrice: quantity * price,
  );
  return SalesService().createSale(
    items: [item],
    totalAmount: quantity * price,
    paymentMethod: 'Cash',
    cashReceived: quantity * price,
  );
}
