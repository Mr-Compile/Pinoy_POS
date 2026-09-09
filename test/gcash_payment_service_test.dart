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
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/receipt_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Integration tests for the GCash payment flow.
///
/// - Owner creates a product and category, logs in, and sets payment rules.
/// - Staff creates a GCash sale and it is held as `pending` when the
///   verification policy is enabled; the Owner's own sales are confirmed
///   immediately.
/// - Owner confirms or rejects pending GCash payments from the sales screen.
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

    /// Inserts a legacy-style pending GCash sale directly (with its items)
    /// and deducts stock to simulate a held sale. Used to cover the
    /// confirm/reject flow for rows created before at-till verification.
    Future<int> seedPendingSale({
      required int productId,
      required int quantity,
      required double unitPrice,
      required int operatorUserId,
      required String reference,
    }) async {
      final productRepository = ProductRepository();
      final product = (await productRepository.getById(productId))!;
      await productRepository.updateStock(
          productId, product.stock - quantity);

      final saleId = await SaleRepository().insert(Sale(
        totalAmount: unitPrice * quantity,
        cashReceived: unitPrice * quantity,
        change: 0,
        paymentMethod: 'GCash',
        paymentStatus: 'pending',
        referenceNumber: reference,
        userId: operatorUserId,
        createdAt: DateTime.now(),
        receiptNumber: 'RCP-TEST-$reference',
      ));

      await SaleItemRepository().insert(SaleItem(
        saleId: saleId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: unitPrice * quantity,
      ));

      return saleId;
    }

    test('owner GCash sale is confirmed immediately even when verification '
        'is enabled', () async {
      final owner = await login('owner', 'owner123');
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
        referenceNumber: 'GCASH-OWNER-001',
      );

      expect(success, isTrue);

      final sale = (await salesService.getSales()).first;
      // The Owner is the operator: confirmed immediately and verified by self.
      expect(sale.paymentStatus, 'confirmed');
      expect(sale.verifiedBy, owner.id);
      expect(sale.verifiedAt, isNotNull);
      expect(sale.userId, owner.id);
      expect(await salesService.getPendingPayments(), isEmpty);
    });

    test('staff GCash sale is held as pending when verification is enabled',
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
      final productBefore =
          (await productService.getProductById(productId))!;

      SessionManager.resetForTest();
      final staff = await login('staff', 'staff123');

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
        referenceNumber: 'GCASH-STAFF-PENDING',
      );

      expect(success, isTrue);

      final sale = (await salesService.getSales()).first;
      expect(sale.paymentStatus, 'pending');
      expect(sale.verifiedBy, isNull);
      expect(sale.verifiedAt, isNull);
      expect(sale.userId, staff.id);

      final productAfter =
          (await productService.getProductById(productId))!;
      expect(productAfter.stock, productBefore.stock - 1);
    });

    test('staff GCash pending sale can be confirmed later by owner', () async {
      final owner = await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);
      final productBefore =
          (await productService.getProductById(productId))!;

      SessionManager.resetForTest();
      final staff = await login('staff', 'staff123');

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
        referenceNumber: 'GCASH-STAFF-PENDING-CONFIRM',
      );

      expect(success, isTrue);

      final pendingSale = (await salesService.getSales()).first;
      expect(pendingSale.paymentStatus, 'pending');
      expect(pendingSale.userId, staff.id);

      // Stock was deducted at the till.
      final productAfterCreate =
          (await productService.getProductById(productId))!;
      expect(productAfterCreate.stock, productBefore.stock - 2);

      // Owner confirms from the sales screen.
      SessionManager.resetForTest();
      await login('owner', 'owner123');

      final confirmed = await salesService.confirmGcashPayment(pendingSale.id!);
      expect(confirmed, isTrue);

      final confirmedSale =
          await salesService.getSaleById(pendingSale.id!);
      expect(confirmedSale!.paymentStatus, 'confirmed');
      expect(confirmedSale.verifiedBy, owner.id);
      expect(confirmedSale.verifiedAt, isNotNull);

      // Confirmation must not deduct stock again.
      final productAfterConfirm =
          (await productService.getProductById(productId))!;
      expect(productAfterConfirm.stock, productBefore.stock - 2);
    });

    test('owner can confirm a pending GCash sale', () async {
      final owner = await login('owner', 'owner123');
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

      final saleId = await seedPendingSale(
        productId: productId,
        quantity: 3,
        unitPrice: 50.0,
        operatorUserId: owner.id!,
        reference: 'GCASH-PENDING-002',
      );

      final sale = (await salesService.getPendingPayments()).first;
      expect(sale.id, saleId);
      final confirmed = await salesService.confirmGcashPayment(saleId);
      expect(confirmed, isTrue);

      final confirmedSale = await salesService.getSaleById(saleId);
      expect(confirmedSale!.paymentStatus, 'confirmed');

      // Stock was already deducted when the pending sale was seeded; a
      // confirmation must not deduct again.
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

      final ownerUser =
          (await UserRepository().getByUsername('owner'))!;
      final saleId = await seedPendingSale(
        productId: productId,
        quantity: 3,
        unitPrice: 50.0,
        operatorUserId: ownerUser.id!,
        reference: 'GCASH-PENDING-002B',
      );

      final rejected = await salesService.rejectGcashPayment(saleId);
      expect(rejected, isTrue);

      final rejectedSale = await salesService.getSaleById(saleId);
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
      final owner = await login('owner', 'owner123');
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();
      final settingsService = SettingsService();

      final currentSettings = await settingsService.getSettings();
      await settingsService.updateSettings(
        currentSettings.copyWith(gcashVerificationMode: 'owner_admin'),
      );

      final productId = await createProduct(productService, categoryService);

      // Seed a legacy pending sale directly.
      final saleId = await seedPendingSale(
        productId: productId,
        quantity: 1,
        unitPrice: 50.0,
        operatorUserId: owner.id!,
        reference: 'GCASH-PENDING-003',
      );

      final sale = (await salesService.getPendingPayments()).first;
      expect(sale.id, saleId);

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
