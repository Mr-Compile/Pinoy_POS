import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/cart_service.dart';

/// A fake [CartService] for unit tests that does not touch the database.
class _FakeCartService extends CartService {
  @override
  String? validateQuantity(Product product, int quantity, int currentCartQty) {
    final total = currentCartQty + quantity;
    if (product.id == null) return 'Invalid product.';
    if (product.stock <= 0) return '${product.name} is out of stock.';
    if (total > product.stock) {
      final available = product.stock - currentCartQty;
      if (available <= 0) {
        return 'Only ${product.stock} units of ${product.name} are available.';
      }
      return 'You can add up to $available more units of ${product.name}.';
    }
    if (quantity <= 0) return 'Quantity must be at least 1.';
    return null;
  }
}

/// Unit tests for the POS cart provider.
///
/// These tests verify the Riverpod cart state: adding, incrementing,
/// decrementing, removing, stock clamping, and conversion to sale items.
void main() {
  group('CartNotifier', () {
    late ProviderContainer container;
    late CartNotifier cart;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          cartServiceProvider.overrideWith((ref) => _FakeCartService()),
        ],
      );
      cart = container.read(cartProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    final product = Product(
      id: 1,
      name: 'Test Product',
      price: 25.0,
      stock: 5,
      minStock: 1,
      createdAt: DateTime.now(),
    );

    final product2 = Product(
      id: 2,
      name: 'Second Product',
      price: 50.0,
      stock: 2,
      minStock: 1,
      createdAt: DateTime.now(),
    );

    test('adds product and reflects quantity', () async {
      final error = await cart.addProduct(product);
      expect(error, isNull);
      expect(cart.state.itemCount, 1);
      expect(cart.state.quantityFor(1), 1);
      expect(cart.state.subtotal, 25.0);
    });

    test('prevents adding out-of-stock product', () async {
      final outOfStock = product.copyWith(stock: 0);
      final error = await cart.addProduct(outOfStock);
      expect(error, isNotNull);
      expect(cart.state.isEmpty, isTrue);
    });

    test('prevents exceeding stock when incrementing', () async {
      await cart.addProduct(product);
      await cart.increment(1);
      await cart.increment(1);
      await cart.increment(1);
      await cart.increment(1);
      final error = await cart.increment(1);

      expect(cart.state.quantityFor(1), 5);
      expect(error, isNotNull);
    });

    test('decrement removes item when reaching zero', () async {
      await cart.addProduct(product);
      cart.decrement(1);
      expect(cart.state.quantityFor(1), isNull);
      expect(cart.state.isEmpty, isTrue);
    });

    test('removes product entirely', () async {
      await cart.addProduct(product);
      await cart.increment(1);
      cart.remove(1);
      expect(cart.state.quantityFor(1), isNull);
      expect(cart.state.isEmpty, isTrue);
    });

    test('clears cart', () async {
      await cart.addProduct(product);
      await cart.addProduct(product2);
      cart.clear();
      expect(cart.state.isEmpty, isTrue);
    });

    test('totals multiple products', () async {
      await cart.addProduct(product);
      await cart.increment(1);
      await cart.addProduct(product2);

      expect(cart.state.itemCount, 3); // 2 + 1
      expect(cart.state.subtotal, 100.0); // 2*25 + 1*50
    });

    test('refreshProduct clamps quantity to new stock', () async {
      await cart.addProduct(product);
      await cart.increment(1); // qty 2

      final lowerStock = product.copyWith(stock: 1);
      cart.refreshProduct(lowerStock);

      expect(cart.state.quantityFor(1), 1);
    });

    test('refreshProducts drops items that fall to zero stock', () async {
      await cart.addProduct(product);
      await cart.addProduct(product2);

      final updated = [
        product.copyWith(stock: 0),
        product2.copyWith(stock: 5),
      ];
      cart.refreshProducts(updated);

      expect(cart.state.quantityFor(1), isNull);
      expect(cart.state.quantityFor(2), 1);
    });

    test('toSaleItems builds correct SaleItem list', () async {
      await cart.addProduct(product);
      await cart.increment(1);
      await cart.addProduct(product2);

      final saleItems = cart.toSaleItems();
      expect(saleItems.length, 2);

      final first = saleItems.firstWhere((s) => s.productId == 1);
      expect(first.quantity, 2);
      expect(first.unitPrice, 25.0);
      expect(first.totalPrice, 50.0);

      final second = saleItems.firstWhere((s) => s.productId == 2);
      expect(second.quantity, 1);
      expect(second.unitPrice, 50.0);
      expect(second.totalPrice, 50.0);
    });
  });
}
