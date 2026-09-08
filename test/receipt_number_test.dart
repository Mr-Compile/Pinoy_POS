import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';

/// Tests for the date-sequential receipt number format `YYYYMMDD-NNNN`.
///
/// The sequence must be persisted in the sales table (surviving restarts
/// and working offline), reset per business date, and never produce a
/// duplicate even when a number is already taken.
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
    await Future.delayed(const Duration(milliseconds: 500));
  });

  String prefixFor(DateTime date) {
    return '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> loginAsOwner() async {
    final authService = AuthService();
    final result = await authService.login('owner', 'owner123');
    if (result != LoginResult.success) {
      throw StateError('Login failed for owner: $result');
    }
  }

  Future<int> createTestProduct() async {
    final categoryService = CategoryService();
    final productService = ProductService();

    await categoryService.createCategory(
      Category(name: 'Test Category', createdAt: DateTime.now()),
    );
    final categoryId = (await categoryService.getActiveCategories()).first.id!;

    await productService.createProduct(
      Product(
        name: 'Test Product',
        price: 50.0,
        stock: 100,
        minStock: 1,
        categoryId: categoryId,
        createdAt: DateTime.now(),
      ),
    );
    return (await productService.getActiveProducts()).first.id!;
  }

  List<SaleItem> itemsFor(int productId, {int quantity = 1}) {
    return [
      SaleItem(
        productId: productId,
        quantity: quantity,
        unitPrice: 50.0,
        totalPrice: 50.0 * quantity,
      ),
    ];
  }

  /// Inserts a sale row directly (bypassing the service) so tests can
  /// pre-seed receipt numbers and simulate prior days / legacy data.
  Future<void> insertRawSale({
    required String receiptNumber,
    required DateTime createdAt,
    String paymentStatus = 'confirmed',
  }) async {
    final userId = SessionManager().currentUser!.id!;
    await SaleRepository().insert(
      Sale(
        totalAmount: 50.0,
        cashReceived: 50.0,
        change: 0.0,
        paymentMethod: 'Cash',
        paymentStatus: paymentStatus,
        userId: userId,
        createdAt: createdAt,
        receiptNumber: receiptNumber,
      ),
    );
  }

  group('receipt number format', () {
    test('first sale of the day gets YYYYMMDD-0001', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();

      final success = await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );
      expect(success, isTrue);

      final sales = await salesService.getFilteredSales();
      expect(sales, hasLength(1));
      expect(sales.first.receiptNumber, '${prefixFor(DateTime.now())}-0001');
    });

    test(
      'sequence increments for each completed sale on the same date',
      () async {
        await loginAsOwner();
        final productId = await createTestProduct();
        final salesService = SalesService();
        final prefix = prefixFor(DateTime.now());

        for (var i = 0; i < 3; i++) {
          await salesService.createSale(
            items: itemsFor(productId),
            totalAmount: 50.0,
            cashReceived: 50.0,
          );
        }

        final sales = await salesService.getFilteredSales();
        final numbers = sales.map((s) => s.receiptNumber).toSet();
        expect(numbers, {'$prefix-0001', '$prefix-0002', '$prefix-0003'});
      },
    );

    test('receipt numbers match the expected format', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();

      await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );

      final sales = await salesService.getFilteredSales();
      expect(sales.first.receiptNumber, matches(RegExp(r'^\d{8}-\d{4}$')));
    });
  });

  group('sequence persistence and daily reset', () {
    test(
      'continues from the highest persisted sequence for the date',
      () async {
        await loginAsOwner();
        final prefix = prefixFor(DateTime.now());
        await insertRawSale(
          receiptNumber: '$prefix-0005',
          createdAt: DateTime.now(),
        );

        final next = await SaleRepository().nextReceiptNumber(DateTime.now());
        expect(next, '$prefix-0006');
      },
    );

    test('a new business date starts at 0001', () async {
      await loginAsOwner();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final next = await SaleRepository().nextReceiptNumber(tomorrow);
      expect(next, '${prefixFor(tomorrow)}-0001');
    });

    test('numbers from a different date do not affect today', () async {
      await loginAsOwner();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await insertRawSale(
        receiptNumber: '${prefixFor(yesterday)}-0007',
        createdAt: yesterday,
      );

      final next = await SaleRepository().nextReceiptNumber(DateTime.now());
      expect(next, '${prefixFor(DateTime.now())}-0001');
    });

    test('legacy RCP receipt numbers do not affect the sequence', () async {
      await loginAsOwner();
      await insertRawSale(
        receiptNumber: 'RCP1725790000000123',
        createdAt: DateTime.now(),
      );

      final next = await SaleRepository().nextReceiptNumber(DateTime.now());
      expect(next, '${prefixFor(DateTime.now())}-0001');
    });
  });

  group('duplicate protection', () {
    test('createSale skips a receipt number that is already taken', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();
      final prefix = prefixFor(DateTime.now());

      // Simulate a number already consumed by another transaction.
      await insertRawSale(
        receiptNumber: '$prefix-0001',
        createdAt: DateTime.now(),
      );

      final success = await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );
      expect(success, isTrue);

      final sales = await salesService.getFilteredSales();
      final numbers = sales.map((s) => s.receiptNumber).toSet();
      expect(numbers, {'$prefix-0001', '$prefix-0002'});
    });

    test('consumed numbers from voided sales are not reused', () async {
      await loginAsOwner();
      final prefix = prefixFor(DateTime.now());
      await insertRawSale(
        receiptNumber: '$prefix-0001',
        createdAt: DateTime.now(),
        paymentStatus: 'cancelled',
      );

      final next = await SaleRepository().nextReceiptNumber(DateTime.now());
      expect(next, '$prefix-0002');
    });
  });

  group('search and sorting', () {
    test('search finds a sale by its full receipt number', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();
      final prefix = prefixFor(DateTime.now());

      await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );
      await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );

      final exact = await salesService.getFilteredSales(search: '$prefix-0002');
      expect(exact, hasLength(1));
      expect(exact.first.receiptNumber, '$prefix-0002');

      final byDate = await salesService.getFilteredSales(search: prefix);
      expect(byDate.length, 2);

      final bySequence = await salesService.getFilteredSales(search: '0001');
      expect(bySequence.length, greaterThanOrEqualTo(1));
    });

    test('receipt numbers sort chronologically with created_at', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();

      for (var i = 0; i < 3; i++) {
        await salesService.createSale(
          items: itemsFor(productId),
          totalAmount: 50.0,
          cashReceived: 50.0,
        );
      }

      final sales = await salesService.getFilteredSales();
      // Newest first; receipt numbers must descend accordingly.
      expect(sales[0].receiptNumber, endsWith('-0003'));
      expect(sales[1].receiptNumber, endsWith('-0002'));
      expect(sales[2].receiptNumber, endsWith('-0001'));
    });
  });

  group('lifecycle', () {
    test('a failed sale does not consume a receipt number', () async {
      await loginAsOwner();
      final productId = await createTestProduct();
      final salesService = SalesService();
      final prefix = prefixFor(DateTime.now());

      // Insufficient cash → validation fails before any insert.
      await expectLater(
        salesService.createSale(
          items: itemsFor(productId),
          totalAmount: 50.0,
          cashReceived: 10.0,
        ),
        throwsA(anything),
      );

      final success = await salesService.createSale(
        items: itemsFor(productId),
        totalAmount: 50.0,
        cashReceived: 50.0,
      );
      expect(success, isTrue);

      final sales = await salesService.getFilteredSales();
      expect(sales, hasLength(1));
      expect(sales.first.receiptNumber, '$prefix-0001');
    });
  });
}
