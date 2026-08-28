import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/cart_service.dart';

/// A single entry in the POS cart.
///
/// The cart is intentionally kept as UI/session state, not persisted to
/// SQLite, because a cart is transient.  It is stored in a Riverpod
/// StateNotifier so any widget that watches it rebuilds immediately when
/// quantities change — including the mobile checkout bottom sheet, which
/// is a separate route from the POS screen.
class CartItem {
  final Product product;
  final int quantity;

  const CartItem({
    required this.product,
    required this.quantity,
  });

  double get lineTotal => product.price * quantity;

  CartItem copyWith({
    Product? product,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  String toString() =>
      'CartItem(productId=${product.id}, qty=$quantity)';
}

/// Immutable cart state.
class CartState {
  final List<CartItem> items;
  final bool isProcessing;

  const CartState({
    this.items = const [],
    this.isProcessing = false,
  });

  CartState copyWith({
    List<CartItem>? items,
    bool? isProcessing,
  }) {
    return CartState(
      items: items ?? this.items,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get total => subtotal;

  int? quantityFor(int productId) {
    for (final item in items) {
      if (item.product.id == productId) return item.quantity;
    }
    return null;
  }

  CartItem? itemFor(int productId) {
    for (final item in items) {
      if (item.product.id == productId) return item;
    }
    return null;
  }
}

/// Centralized cart state for the POS screen.
///
/// This follows the required architecture:
///   UI → CartNotifier → CartService → ProductRepository → ProductDao → SQLite
///
/// The cart is not persisted; it is validated against live product stock
/// each time an item is added or its quantity is changed.
class CartNotifier extends StateNotifier<CartState> {
  final Ref _ref;
  CartService? _cartService;

  CartNotifier(this._ref) : super(const CartState());

  CartService get _service {
    _cartService ??= _ref.read(cartServiceProvider);
    return _cartService!;
  }

  /// Adds a product to the cart or increments its quantity by 1.
  ///
  /// Returns an error message if the operation could not be performed, or
  /// null on success.  Stock is validated by the cart service.
  Future<String?> addProduct(Product product) async {
    final currentItem = state.itemFor(product.id!);
    final currentQty = currentItem?.quantity ?? 0;

    final validationError =
        _service.validateQuantity(product, 1, currentQty);
    if (validationError != null) return validationError;

    final newQty = currentQty + 1;
    final newItem = CartItem(product: product, quantity: newQty);

    state = state.copyWith(
      items: _replaceOrAppend(product.id!, newItem),
    );
    return null;
  }

  /// Increments the quantity of an existing cart item by 1.
  ///
  /// Returns an error message or null on success.
  Future<String?> increment(int productId) async {
    final item = state.itemFor(productId);
    if (item == null) return 'Product not in cart.';

    final validationError =
        _service.validateQuantity(item.product, 1, item.quantity);
    if (validationError != null) return validationError;

    final newItem = item.copyWith(quantity: item.quantity + 1);
    state = state.copyWith(
      items: _replace(productId, newItem),
    );
    return null;
  }

  /// Decrements the quantity of an existing cart item by 1.
  ///
  /// If the quantity reaches 0 the item is removed.  Quantity never becomes
  /// negative.
  void decrement(int productId) {
    final item = state.itemFor(productId);
    if (item == null) return;

    if (item.quantity <= 1) {
      remove(productId);
      return;
    }

    final newItem = item.copyWith(quantity: item.quantity - 1);
    state = state.copyWith(
      items: _replace(productId, newItem),
    );
  }

  /// Removes a product from the cart entirely.
  void remove(int productId) {
    state = state.copyWith(
      items: state.items.where((i) => i.product.id != productId).toList(),
    );
  }

  /// Clears the cart.
  ///
  /// This is safe to call only after a sale has been successfully persisted.
  void clear() {
    state = const CartState();
  }

  /// Updates a product's details (e.g. after a sale changes stock) in the
  /// cart without changing quantities.  Used after checkout to refresh
  /// product data.
  void refreshProduct(Product product) {
    if (product.id == null) return;
    final item = state.itemFor(product.id!);
    if (item == null) return;

    // If stock is now lower than the cart quantity, clamp it.
    final clampedQty = item.quantity > product.stock && product.stock >= 0
        ? product.stock
        : item.quantity;

    final newItem = item.copyWith(product: product, quantity: clampedQty);
    state = state.copyWith(
      items: _replace(product.id!, newItem),
    );
  }

  /// Replaces the entire product list backing the cart, keeping quantities
  /// where possible.  Called when the POS screen reloads products.
  void refreshProducts(List<Product> products) {
    final newItems = <CartItem>[];
    for (final existing in state.items) {
      final updated = products.firstWhere(
        (p) => p.id == existing.product.id,
        orElse: () => existing.product,
      );
      final clampedQty = existing.quantity > updated.stock && updated.stock >= 0
          ? updated.stock
          : existing.quantity;
      if (clampedQty > 0) {
        newItems.add(CartItem(product: updated, quantity: clampedQty));
      }
    }
    state = state.copyWith(items: newItems);
  }

  /// Sets the processing flag (e.g. while checking out).
  void setProcessing(bool processing) {
    state = state.copyWith(isProcessing: processing);
  }

  /// Builds the list of [SaleItem]s to pass to [SalesService.createSale].
  List<SaleItem> toSaleItems() {
    return state.items.map((item) {
      return SaleItem(
        saleId: 0,
        productId: item.product.id!,
        quantity: item.quantity,
        unitPrice: item.product.price,
        totalPrice: item.lineTotal,
      );
    }).toList();
  }

  List<CartItem> _replaceOrAppend(int productId, CartItem newItem) {
    var found = false;
    final result = state.items.map((item) {
      if (item.product.id == productId) {
        found = true;
        return newItem;
      }
      return item;
    }).toList();
    if (!found) result.add(newItem);
    return result;
  }

  List<CartItem> _replace(int productId, CartItem newItem) {
    return state.items
        .map((item) => item.product.id == productId ? newItem : item)
        .toList();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier(ref);
});
