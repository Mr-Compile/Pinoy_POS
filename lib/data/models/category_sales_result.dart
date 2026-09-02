/// Sales totals for a single product category.
class CategorySalesResult {
  final int? categoryId;
  final String categoryName;
  final double totalSales;
  final int transactionCount;
  final int itemsSold;

  const CategorySalesResult({
    this.categoryId,
    required this.categoryName,
    required this.totalSales,
    required this.transactionCount,
    required this.itemsSold,
  });

  factory CategorySalesResult.fromMap(Map<String, dynamic> map) {
    return CategorySalesResult(
      categoryId: map['category_id'] as int?,
      categoryName: (map['category_name'] as String?) ?? 'Uncategorized',
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
      itemsSold: (map['items_sold'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'CategorySalesResult($categoryName: $totalSales, $itemsSold items)';
  }
}
