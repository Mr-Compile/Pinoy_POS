import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/receipt_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Integration tests for the GCash payment flow.
///
/// - Owner creates a product and category, logs in, and sets payment rules.
/// - Staff creates a GCash sale.
/// - Owner/Admin confirms or rejects pending GCash payments.
/// - Duplicate references and validation rules are rejected.
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

  Future<User> login(String username, String password) async {
    final authService = AuthService();
    final result = await authService.login(username, password);
    if (result != LoginResult.success) {
      throw StateError('Login failed for $username: $result');
    }
    return authService.currentUser!;
  }

  Future<int> createProduct(ProductService productService,
      CategoryService categoryService) async {
    final category = Category(name: 'Test Category', createdAt: DateTime.now());
    await categoryService.createCategory(category);
    final categories = await categoryService.getActiveCategories();
    final categoryId = categories.first.id!;

    final product = Product(
      name: 'Test Product',
      price: 50.0,
      stock: 10,
      minStock: 1,
      categoryId: categoryId,
      createdAt: DateTime.now(),
    );
    await productService.createProduct(product);
    final products = await productService.getActiveProducts();
    return products.first.id!;
  }

  group('SalesService GCash flow', () {
    test('creates an immediate GCash sale and deducts stock', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      final productId = await createProduct(productService, categoryService);
      final productBefore = (await productService.getProductById(productId))!;
      expect(productBefore.stock, 10);

      final items = [
        SaleItem(
          productId: productId,
          quantity: 2,
          unitPrice: 50.0,
          totalPrice: 100.0,
        ),
      ];

      final success = await salesService.createSale(
        items: items,
        totalAmount: 100.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-REF-001',
        customerName: 'Test Customer',
      );

      expect(success, isTrue);

      final sales = await salesService.getFilteredSales();
      expect(sales, isNotEmpty);
      final sale = sales.first;
      expect(sale.paymentMethod, 'GCash');
      expect(sale.paymentStatus, 'confirmed');
      expect(sale.referenceNumber, 'GCASH-REF-001');
      expect(sale.customerName, 'Test Customer');

      final productAfter = (await productService.getProductById(productId))!;
      expect(productAfter.stock, 8);
    });

    test('rejects a missing required GCash reference number', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      final productId = await createProduct(productService, categoryService);

      final items = [
        SaleItem(
          productId: productId,
          quantity: 1,
          unitPrice: 50.0,
          totalPrice: 50.0,
        ),
      ];

      expect(
        () => salesService.createSale(
          items: items,
          totalAmount: 50.0,
          paymentMethod: 'GCash',
          referenceNumber: '',
        ),
        throwsA(isA<PaymentValidationException>()),
      );
    });

    test('rejects a duplicate GCash reference number', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      final productId = await createProduct(productService, categoryService);

      final items = [
        SaleItem(
          productId: productId,
          quantity: 1,
          unitPrice: 50.0,
          totalPrice: 50.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 50.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-REF-DUP',
      );

      expect(
        () => salesService.createSale(
          items: items,
          totalAmount: 50.0,
          paymentMethod: 'GCash',
          referenceNumber: 'GCASH-REF-DUP',
        ),
        throwsA(isA<PaymentValidationException>()),
      );
    });

    test('creates a pending GCash sale when verification mode requires it',
        () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);
      final items = [
        SaleItem(
          productId: productId,
          quantity: 1,
          unitPrice: 50.0,
          totalPrice: 50.0,
        ),
      ];

      final success = await salesService.createSale(
        items: items,
        totalAmount: 50.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-PENDING-001',
      );

      expect(success, isTrue);

      final sales = await salesService.getPendingPayments();
      expect(sales, isNotEmpty);
      expect(sales.first.paymentStatus, 'pending');
      expect(sales.first.referenceNumber, 'GCASH-PENDING-001');
    });

    test('owner can confirm a pending GCash sale and deduct stock', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);
      final productBefore = (await productService.getProductById(productId))!;

      final items = [
        SaleItem(
          productId: productId,
          quantity: 3,
          unitPrice: 50.0,
          totalPrice: 150.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 150.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-PENDING-002',
      );

      final sale = (await salesService.getPendingPayments()).first;
      final confirmed = await salesService.confirmGcashPayment(sale.id!);
      expect(confirmed, isTrue);

      final confirmedSale = await salesService.getSaleById(sale.id!);
      expect(confirmedSale!.paymentStatus, 'confirmed');

      final productAfterConfirm =
          (await productService.getProductById(productId))!;
      expect(productAfterConfirm.stock, productBefore.stock - 3);
    });

    test('owner can reject a pending GCash sale and restore stock', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);
      final productBefore = (await productService.getProductById(productId))!;

      final items = [
        SaleItem(
          productId: productId,
          quantity: 3,
          unitPrice: 50.0,
          totalPrice: 150.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 150.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-PENDING-002B',
      );

      final sale = (await salesService.getPendingPayments()).first;
      final rejected = await salesService.rejectGcashPayment(sale.id!);
      expect(rejected, isTrue);

      final rejectedSale = await salesService.getSaleById(sale.id!);
      expect(rejectedSale!.paymentStatus, 'cancelled');

      final productAfterReject =
          (await productService.getProductById(productId))!;
      expect(productAfterReject.stock, productBefore.stock);
    });

    test('receipt view data uses historical product names', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      final productId = await createProduct(productService, categoryService);
      final product = (await productService.getProductById(productId))!;

      final items = [
        SaleItem(
          productId: productId,
          quantity: 2,
          unitPrice: 50.0,
          totalPrice: 100.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 100.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-RECEIPT-001',
      );

      final sale = (await salesService.getSales()).first;
      final receipt = await salesService.getReceiptViewData(sale.id!);

      expect(receipt, isNotNull);
      expect(receipt!.items, hasLength(1));
      expect(receipt.items.first.productName, product.name);
      expect(receipt.items.first.quantity, 2);
      expect(receipt.total, 100.0);
      expect(receipt.paymentMethod, 'GCash');
      expect(receipt.referenceNumber, 'GCASH-RECEIPT-001');
    });

    test('receipt PDF is generated with non-zero bytes', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final receiptService = ReceiptService();

      final productId = await createProduct(productService, categoryService);

      final items = [
        SaleItem(
          productId: productId,
          quantity: 3,
          unitPrice: 50.0,
          totalPrice: 150.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 150.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-PDF-001',
      );

      final sale = (await salesService.getSales()).first;
      final receipt = (await salesService.getReceiptViewData(sale.id!))!;
      final bytes = await receiptService.generateReceiptPdf(receipt);

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));

      final fileName = receiptService.buildFileName(receipt);
      expect(fileName, contains('PinoyPOS_Receipt_'));
      expect(fileName, contains(sale.receiptNumber ?? sale.id.toString()));

      final savedPath = await receiptService.saveReceiptToAppDocuments(
        bytes,
        fileName: fileName,
      );

      expect(savedPath, isNotNull);
      final file = File(savedPath!);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    });

    test('staff cannot confirm or reject pending GCash payments', () async {
      await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);

      // Owner creates a pending sale directly using owner account.
      final items = [
        SaleItem(
          productId: productId,
          quantity: 1,
          unitPrice: 50.0,
          totalPrice: 50.0,
        ),
      ];

      await salesService.createSale(
        items: items,
        totalAmount: 50.0,
        paymentMethod: 'GCash',
        referenceNumber: 'GCASH-PENDING-003',
      );

      final sale = (await salesService.getPendingPayments()).first;

      // Log in as staff.
      SessionManager.resetForTest();
      await login('staff', 'staff123');

      expect(
        () => salesService.confirmGcashPayment(sale.id!),
        throwsA(isA<Exception>()),
      );

      expect(
        () => salesService.rejectGcashPayment(sale.id!),
        throwsA(isA<Exception>()),
      );
    });
  });
}
