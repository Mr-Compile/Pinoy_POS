import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';

/// Service that validates cart operations against the database.
///
/// The cart itself is transient UI state managed by [CartNotifier].  This
/// service exists to keep the architecture consistent
/// (Provider/Controller → Service → Repository → DAO → SQLite) when the
/// POS screen needs to validate stock or look up product details.
class CartService {
  final ProductRepository _productRepository = ProductRepository();

  /// Returns the active product with the given [productId], or null if it
  /// does not exist or is inactive/deleted.
  Future<Product?> getProduct(int productId) async {
    return _productRepository.getById(productId);
  }

  /// Returns all active products for the catalog.
  Future<List<Product>> getActiveProducts() async {
    return _productRepository.getActiveProducts();
  }

  /// Checks whether the requested [quantity] of [product] can be added to
  /// the cart.  Returns an error message or null if the addition is valid.
  String? validateQuantity(Product product, int quantity, int currentCartQty) {
    if (product.id == null) return 'Invalid product.';
    if (product.stock <= 0) return '${product.name} is out of stock.';

    final totalQty = currentCartQty + quantity;
    if (totalQty > product.stock) {
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
