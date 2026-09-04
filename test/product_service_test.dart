import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';

/// Service-level regression tests for product validation and the
/// category -> product data flow.
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
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    SessionManager.resetForTest();
  });

  group('ProductService', () {
    test('createProduct succeeds with a valid category', () async {
      final categoryService = CategoryService();
      await categoryService.createCategory(
        Category(name: 'Drinks', createdAt: DateTime.now()),
      );
      final categories = await categoryService.getActiveCategories();
      final categoryId = categories.first.id!;

      final product = Product(
        name: 'Coke',
        price: 30.0,
        stock: 100,
        minStock: 10,
        categoryId: categoryId,
        createdAt: DateTime.now(),
      );

      expect(await ProductService().createProduct(product), isTrue);
    });

    test('createProduct rejects a product without a category', () async {
      final product = Product(
        name: 'No Category',
        price: 30.0,
        stock: 100,
        minStock: 10,
        createdAt: DateTime.now(),
      );

      expect(await ProductService().createProduct(product), isFalse);
    });

    test('createProduct rejects a product with a non-existent category', () async {
      final product = Product(
        name: 'Missing Category',
        price: 30.0,
        stock: 100,
        minStock: 10,
        categoryId: 9999,
        createdAt: DateTime.now(),
      );

      expect(await ProductService().createProduct(product), isFalse);
    });

    test('updateProduct rejects a product with a null category', () async {
      final product = Product(
        name: 'Existing',
        price: 30.0,
        stock: 100,
        minStock: 10,
        createdAt: DateTime.now(),
      );

      expect(await ProductService().updateProduct(product), isFalse);
    });

    test('getProductByName returns the matching product', () async {
      final categoryService = CategoryService();
      await categoryService.createCategory(
        Category(name: 'Snacks', createdAt: DateTime.now()),
      );
      final categories = await categoryService.getActiveCategories();
      final categoryId = categories.first.id!;

      await ProductService().createProduct(
        Product(
          name: 'Chips',
          price: 25.0,
          stock: 50,
          categoryId: categoryId,
          createdAt: DateTime.now(),
        ),
      );

      final found = await ProductService().getProductByName('Chips');
      expect(found, isNotNull);
      expect(found!.name, 'Chips');
      expect(found.categoryId, categoryId);
    });

    test('product category relationship is persisted via category_id', () async {
      final categoryService = CategoryService();
      await categoryService.createCategory(
        Category(name: 'Food', createdAt: DateTime.now()),
      );
      final categories = await categoryService.getActiveCategories();
      final categoryId = categories.first.id!;

      final productService = ProductService();
      await productService.createProduct(
        Product(
          name: 'Rice',
          price: 50.0,
          stock: 20,
          categoryId: categoryId,
          createdAt: DateTime.now(),
        ),
      );

      final active = await productService.getActiveProducts();
      final product = active.firstWhere((p) => p.name == 'Rice');
      expect(product.categoryId, categoryId);
    });
  });
}
