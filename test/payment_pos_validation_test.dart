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
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Service-level tests for Payment Settings → POS checkout validation.
///
/// These tests verify that the customer name requirement (off / optional /
/// required) configured in Payment Settings is enforced by [SalesService]
/// for every supported payment method, not only GCash.
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

    final authService = AuthService();
    final result = await authService.login('owner', 'owner123');
    expect(result, LoginResult.success);
  });

  tearDown(() async {
    final dbHelper = DatabaseHelper();
    await dbHelper.close();
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 500));
    SessionManager.resetForTest();
  });

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

  Future<void> setCustomerNameRequirement(String value) async {
    final settingsService = SettingsService();
    final current = await settingsService.getSettings();
    await settingsService.updateSettings(
      current.copyWith(gcashCustomerNameRequirement: value),
    );
  }

  Future<void> setPaymentProofRequirement(String value) async {
    final settingsService = SettingsService();
    final current = await settingsService.getSettings();
    await settingsService.updateSettings(
      current.copyWith(gcashPaymentProofRequirement: value),
    );
  }

  Future<bool> createSaleForMethod(
    SalesService salesService,
    int productId,
    String paymentMethod, {
    String? customerName,
    String? referenceNumber,
  }) {
    final items = [
      SaleItem(
        productId: productId,
        quantity: 1,
        unitPrice: 50.0,
        totalPrice: 50.0,
      ),
    ];

    return salesService.createSale(
      items: items,
      totalAmount: 50.0,
      paymentMethod: paymentMethod,
      customerName: customerName,
      referenceNumber: referenceNumber ?? 'REF-${paymentMethod.toUpperCase()}-001',
      cashReceived: paymentMethod == 'Cash' ? 50.0 : null,
    );
  }

  group('SalesService customer name requirement', () {
    test('blocks empty customer name for Cash when required', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('required');
      final productId = await createProduct(productService, categoryService);

      expect(
        () => createSaleForMethod(
          salesService,
          productId,
          'Cash',
          customerName: '',
        ),
        throwsA(
          isA<PaymentValidationException>().having(
            (e) => e.message,
            'message',
            contains('Customer name is required'),
          ),
        ),
      );
    });

    test('blocks whitespace-only customer name for Card when required', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('required');
      final productId = await createProduct(productService, categoryService);

      expect(
        () => createSaleForMethod(
          salesService,
          productId,
          'Card',
          customerName: '   ',
        ),
        throwsA(
          isA<PaymentValidationException>().having(
            (e) => e.message,
            'message',
            contains('Customer name is required'),
          ),
        ),
      );
    });

    test('blocks empty customer name for Other when required', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('required');
      final productId = await createProduct(productService, categoryService);

      expect(
        () => createSaleForMethod(
          salesService,
          productId,
          'Other',
          customerName: null,
        ),
        throwsA(
          isA<PaymentValidationException>().having(
            (e) => e.message,
            'message',
            contains('Customer name is required'),
          ),
        ),
      );
    });

    test('blocks empty customer name for GCash when required', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('required');
      final productId = await createProduct(productService, categoryService);

      expect(
        () => createSaleForMethod(
          salesService,
          productId,
          'GCash',
          customerName: '',
          referenceNumber: 'GCASH-REF-001',
        ),
        throwsA(
          isA<PaymentValidationException>().having(
            (e) => e.message,
            'message',
            contains('Customer name is required'),
          ),
        ),
      );
    });

    test('allows valid customer name for all methods when required', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('required');
      final productId = await createProduct(productService, categoryService);

      for (final method in ['Cash', 'Card', 'Other', 'GCash']) {
        final reference = method == 'GCash'
            ? 'GCASH-REF-VALID-${method.hashCode}'
            : 'REF-${method.toUpperCase()}-VALID';
        final success = await createSaleForMethod(
          salesService,
          productId,
          method,
          customerName: 'Juan Dela Cruz',
          referenceNumber: reference,
        );
        expect(success, isTrue, reason: 'method $method should succeed');
      }
    });

    test('allows empty customer name for all methods when optional', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('optional');
      final productId = await createProduct(productService, categoryService);

      for (final method in ['Cash', 'Card', 'Other', 'GCash']) {
        final reference = method == 'GCash'
            ? 'GCASH-REF-OPT-${method.hashCode}'
            : 'REF-${method.toUpperCase()}-OPT';
        final success = await createSaleForMethod(
          salesService,
          productId,
          method,
          customerName: '',
          referenceNumber: reference,
        );
        expect(success, isTrue, reason: 'method $method should allow empty');
      }
    });

    test('allows empty customer name for all methods when off', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setCustomerNameRequirement('off');
      final productId = await createProduct(productService, categoryService);

      for (final method in ['Cash', 'Card', 'Other', 'GCash']) {
        final reference = method == 'GCash'
            ? 'GCASH-REF-OFF-${method.hashCode}'
            : 'REF-${method.toUpperCase()}-OFF';
        final success = await createSaleForMethod(
          salesService,
          productId,
          method,
          customerName: null,
          referenceNumber: reference,
        );
        expect(success, isTrue, reason: 'method $method should allow off');
      }
    });

    test('persisted setting is read by getPaymentSettings', () async {
      final settingsService = SettingsService();

      await setCustomerNameRequirement('required');
      final paymentSettings = await settingsService.getPaymentSettings();

      expect(paymentSettings.customerNameRequired, isTrue);
      expect(paymentSettings.customerNameVisible, isTrue);

      await setCustomerNameRequirement('off');
      final paymentSettingsOff = await settingsService.getPaymentSettings();
      expect(paymentSettingsOff.customerNameRequired, isFalse);
      expect(paymentSettingsOff.customerNameVisible, isFalse);
    });

    test('payment proof requirement is enforced only for GCash', () async {
      final productService = ProductService();
      final categoryService = CategoryService();
      final salesService = SalesService();

      await setPaymentProofRequirement('required');
      final productId = await createProduct(productService, categoryService);

      // GCash without proof must be rejected.
      expect(
        () => createSaleForMethod(
          salesService,
          productId,
          'GCash',
          customerName: 'Juan Dela Cruz',
          referenceNumber: 'GCASH-REF-NOPROOF',
        ),
        throwsA(
          isA<PaymentValidationException>().having(
            (e) => e.message,
            'message',
            contains('Payment proof is required'),
          ),
        ),
      );

      // Non-GCash methods should not require payment proof.
      for (final method in ['Cash', 'Card', 'Other']) {
        final success = await createSaleForMethod(
          salesService,
          productId,
          method,
          customerName: 'Juan Dela Cruz',
        );
        expect(success, isTrue, reason: '$method should not require proof');
      }
    });
  });
}
