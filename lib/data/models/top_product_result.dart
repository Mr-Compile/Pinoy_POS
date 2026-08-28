/// A product ranked by total quantity sold.
class TopProductResult {
  final int productId;
  final String productName;
  final int totalQuantity;

  const TopProductResult({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
  });

  /// Alias for [productName], used by dashboard code that labels the field
  /// as a shorter display name.
  String get name => productName;

  @override
  String toString() {
    return 'TopProductResult(productId: $productId, productName: $productName, '
        'totalQuantity: $totalQuantity)';
  }
}
