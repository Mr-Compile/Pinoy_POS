class Category {
  final int? id;
  final String name;
  final String description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? deletedAt;

  Category({
    this.id,
    required this.name,
    this.description = '',
    this.isActive = true,
    required this.createdAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  Category copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;
}
