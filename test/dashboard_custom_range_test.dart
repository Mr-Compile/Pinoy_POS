import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/dashboard_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';

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
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    SessionManager.resetForTest();
  });

  test('custom range with no data returns zero analytics', () async {
    await _login('owner');
    final product = await _createProduct('Past Product', 100.0, 20);

    // Create a sale 60 days ago.
    final today = DateTime.now();
    final saleDate = today.subtract(const Duration(days: 60));
    await _createSale(product, 1, createdAt: saleDate);

    // Query a custom range covering the last 30 days (does not include the sale).
    final start = today.subtract(const Duration(days: 30));
    final filter = SalesPeriodFilter(
      period: SalesPeriod.custom,
      selectedDate: start,
      customEnd: today,
    );

    final dashboardData = await DashboardService().getDashboard(filter);
    expect(dashboardData, isNotNull);
    expect(dashboardData, isA<OwnerDashboardData>());

    final data = dashboardData as OwnerDashboardData;
    expect(data.analytics.totalSales, 0.0,
        reason: 'totalSales should be 0 for an empty custom range');
    expect(data.analytics.transactionCount, 0,
        reason: 'transactionCount should be 0 for an empty custom range');
    expect(data.analytics.itemsSold, 0,
        reason: 'itemsSold should be 0 for an empty custom range');
    for (final point in data.analytics.trend) {
      expect(point.total, 0.0,
          reason: 'trend points should be zero for an empty custom range');
      expect(point.count, 0,
          reason: 'trend counts should be zero for an empty custom range');
    }
    expect(data.analytics.paymentBreakdown.isEmpty, isTrue,
        reason: 'paymentBreakdown should be empty for an empty custom range');
    expect(data.analytics.topProducts.isEmpty, isTrue,
        reason: 'topProducts should be empty for an empty custom range');
    expect(data.analytics.categorySales.isEmpty, isTrue,
        reason: 'categorySales should be empty for an empty custom range');
    expect(data.analytics.sales.isEmpty, isTrue,
        reason: 'sales list should be empty for an empty custom range');
    expect(data.recentSales.isEmpty, isTrue,
        reason: 'recentSales should be empty for an empty custom range');
  });

  test('custom range with data excludes sales outside the range', () async {
    await _login('owner');
    final product = await _createProduct('Range Product', 100.0, 20);

    final today = DateTime.now();
    final saleInRange = today.subtract(const Duration(days: 5));
    final saleOutOfRange = today.subtract(const Duration(days: 60));

    await _createSale(product, 2, createdAt: saleInRange);
    await _createSale(product, 1, createdAt: saleOutOfRange);

    final start = today.subtract(const Duration(days: 30));
    final filter = SalesPeriodFilter(
      period: SalesPeriod.custom,
      selectedDate: start,
      customEnd: today,
    );

    final dashboardData = await DashboardService().getDashboard(filter);
    final data = dashboardData as OwnerDashboardData;

    expect(data.analytics.totalSales, 200.0,
        reason: 'Only the in-range sale should be counted');
    expect(data.analytics.transactionCount, 1,
        reason: 'Only the in-range sale should be counted');
    expect(data.analytics.itemsSold, 2,
        reason: 'Only the in-range sale items should be counted');
  });

  test('end-date transaction is included in the custom range', () async {
    await _login('owner');
    final product = await _createProduct('End Date Product', 100.0, 20);

    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 5));
    final end = today.subtract(const Duration(days: 2));

    // Sale exactly at the end of the selected end date (11:59 PM local).
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    await _createSale(product, 1, createdAt: endOfDay);

    final filter = SalesPeriodFilter(
      period: SalesPeriod.custom,
      selectedDate: start,
      customEnd: end,
    );

    final dashboardData = await DashboardService().getDashboard(filter);
    final data = dashboardData as OwnerDashboardData;

    expect(data.analytics.totalSales, 100.0,
        reason: 'A sale on the end date should be included');
    expect(data.analytics.transactionCount, 1);
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

Future<void> _createSale(Product product, int quantity, {DateTime? createdAt}) async {
  final price = product.price;
  final item = SaleItem(
    productId: product.id!,
    quantity: quantity,
    unitPrice: price,
    totalPrice: quantity * price,
  );

  // Create a sale today, then patch its createdAt to the desired historical
  // date so we can test custom range filtering without rebuilding the sale
  // creation service.
  final success = await SalesService().createSale(
    items: [item],
    totalAmount: quantity * price,
    paymentMethod: 'Cash',
    cashReceived: quantity * price,
  );
  expect(success, isTrue);

  if (createdAt != null) {
    final sales = await SaleRepository().getAll();
    final userSales = sales.where((s) => s.userId == SessionManager().currentUser!.id!).toList()
      ..sort((a, b) => b.id!.compareTo(a.id!));
    expect(userSales, isNotEmpty, reason: 'Expected a sale to be created for the current user');
    final sale = userSales.first;
    final updated = sale.copyWith(createdAt: createdAt);
    await SaleRepository().update(updated);
  }
}
