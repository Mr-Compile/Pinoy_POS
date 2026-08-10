class Product {
  final int? id;
  final String name;
  final String? description;
  final double price;
  final int stock;
  final int minStock;
  final String? barcode;
  final String? imageUrl;
  final int? categoryId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? deletedAt;

  Product({
    this.id,
    required this.name,
    this.description,
    required this.price,
    required this.stock,
    this.minStock = 10,
    this.barcode,
    this.imageUrl,
    this.categoryId,
    this.isActive = true,
    required this.createdAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'stock': stock,
      'min_stock': minStock,
      'barcode': barcode,
      'image_url': imageUrl,
      'category_id': categoryId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      stock: map['stock'] as int,
      minStock: map['min_stock'] as int? ?? 10,
      barcode: map['barcode'] as String?,
      imageUrl: map['image_url'] as String?,
      categoryId: map['category_id'] as int?,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Product copyWith({
    int? id,
    String? name,
    String? description,
    double? price,
    int? stock,
    int? minStock,
    String? barcode,
    String? imageUrl,
    int? categoryId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      barcode: barcode ?? this.barcode,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryId: categoryId ?? this.categoryId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;
  bool get isLowStock => stock <= minStock;
}
