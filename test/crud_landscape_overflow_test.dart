import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';

class _FakeProductService extends ProductService {
  final List<Product> products;

  _FakeProductService(this.products);

  @override
  Future<List<Product>> getActiveProducts() async => products;

  @override
  Future<List<Product>> searchProducts(String query) async => products
      .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
      .toList();

  @override
  Future<({int total, int lowStock, int outOfStock})> getStockSummary() async =>
      (total: products.length, lowStock: 0, outOfStock: 0);
}

class _FakeCategoryService extends CategoryService {
  @override
  Future<List<Category>> getActiveCategories() async => [
        Category(id: 1, name: 'Meals', createdAt: DateTime(2026, 1, 1)),
      ];
}

class _FakeTrashService extends TrashService {
  final List<TrashItem> items;

  _FakeTrashService(this.items);

  @override
  Future<int> backfillSoftDeletedToTrash() async => 0;

  @override
  Future<int> processExpiredTrash() async => 0;

  @override
  Future<List<TrashItem>> getAllTrash() async => items;
}

void main() {
  final owner = User(
    id: 1,
    username: 'owner',
    passwordHash: 'hash',
    role: UserRole.owner,
    fullName: 'Owner User',
    createdAt: DateTime(2026, 1, 1),
  );

  final admin = User(
    id: 2,
    username: 'admin',
    passwordHash: 'hash',
    role: UserRole.admin,
    fullName: 'Admin User',
    createdAt: DateTime(2026, 1, 1),
  );

  final product = Product(
    id: 1,
    name: 'Chicken Adobo',
    price: 85.0,
    stock: 12,
    minStock: 5,
    categoryId: 1,
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    SessionManager.resetForTest();
    SessionManager().setCurrentUser(owner);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    SessionManager.resetForTest();
  });

  Widget app(Widget child, List<Product> products) {
    return ProviderScope(
      overrides: [
        productServiceProvider.overrideWith(
          (ref) => _FakeProductService(products),
        ),
        categoryServiceProvider.overrideWith((ref) => _FakeCategoryService()),
      ],
      child: MaterialApp(home: child),
    );
  }

  Widget trashApp(List<TrashItem> items) {
    return ProviderScope(
      overrides: [
        trashServiceProvider.overrideWith((ref) => _FakeTrashService(items)),
      ],
      child: const MaterialApp(home: TrashScreen()),
    );
  }

  // Compact phone landscape: short viewport where the fixed stats strip and
  // toolbar consume most of the height.
  void useLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('ProductsScreen does not overflow in landscape', (tester) async {
    useLandscape(tester);
    await tester.pumpWidget(app(const ProductsScreen(), [product]));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Adobo'), findsOneWidget);
  });

  testWidgets('ProductsScreen empty state does not overflow in landscape',
      (tester) async {
    useLandscape(tester);
    await tester.pumpWidget(app(const ProductsScreen(), [product]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No Products Yet'), findsOneWidget);
  });

  testWidgets('StockScreen does not overflow in landscape', (tester) async {
    useLandscape(tester);
    await tester.pumpWidget(app(const StockScreen(), [product]));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Adobo'), findsOneWidget);
  });

  testWidgets('StockScreen empty state does not overflow in landscape',
      (tester) async {
    useLandscape(tester);
    await tester.pumpWidget(app(const StockScreen(), [product]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No Products Found'), findsOneWidget);
  });

  testWidgets('TrashScreen does not overflow in landscape for admin',
      (tester) async {
    SessionManager().setCurrentUser(admin);
    useLandscape(tester);
    await tester.pumpWidget(
      trashApp([
        TrashItem(
          id: 1,
          entityType: 'user',
          entityId: 9,
          entityName: 'Old Cashier',
          deletedAt: DateTime(2026, 9, 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old Cashier'), findsOneWidget);
  });

  testWidgets('TrashScreen scrolls with keyboard insets for admin',
      (tester) async {
    SessionManager().setCurrentUser(admin);
    useLandscape(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpWidget(
      trashApp([
        TrashItem(
          id: 1,
          entityType: 'user',
          entityId: 9,
          entityName: 'Old Cashier',
          deletedAt: DateTime(2026, 9, 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // Item is below the keyboard-shrunken viewport; scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Old Cashier'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Old Cashier'), findsOneWidget);
  });

  testWidgets('TrashScreen empty state does not overflow for admin',
      (tester) async {
    SessionManager().setCurrentUser(admin);
    useLandscape(tester);
    await tester.pumpWidget(trashApp([]));
    await tester.pumpAndSettle();
    expect(find.text('Trash is empty.'), findsOneWidget);
  });
}
