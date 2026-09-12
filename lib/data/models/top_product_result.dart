/// A product ranked by total quantity sold and/or revenue.
class TopProductResult {
  final int productId;
  final String productName;
  final int totalQuantity;
  final double revenue;

  /// Display name of the product's category, when it can be resolved.
  final String? categoryName;

  /// Relative path to the product image, when the product still exists and
  /// has one. Null for deleted products or products without an image.
  final String? imageUrl;

  const TopProductResult({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    this.revenue = 0.0,
    this.categoryName,
    this.imageUrl,
  });

  /// Alias for [productName], used by dashboard code that labels the field
  /// as a shorter display name.
  String get name => productName;

  factory TopProductResult.fromMap(Map<String, dynamic> map) {
    return TopProductResult(
      productId: (map['product_id'] as num).toInt(),
      productName: (map['product_name'] as String?) ?? 'Unknown',
      totalQuantity: (map['total_quantity'] as num?)?.toInt() ?? 0,
      revenue: (map['revenue'] as num?)?.toDouble() ?? 0.0,
      categoryName: map['category_name'] as String?,
      imageUrl: map['image_url'] as String?,
    );
  }

  @override
  String toString() {
    return 'TopProductResult(productId: $productId, productName: $productName, '
        'totalQuantity: $totalQuantity, revenue: $revenue)';
  }
}
