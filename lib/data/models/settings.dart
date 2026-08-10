class Settings {
  final int? id;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String currency;
  final String? receiptFooter;
  final String? theme;
  final String? accentColor;
  final DateTime createdAt;
  final DateTime updatedAt;

  Settings({
    this.id,
    required this.storeName,
    this.storeAddress = '',
    this.storePhone = '',
    this.currency = 'PHP',
    this.receiptFooter,
    this.theme,
    this.accentColor,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_name': storeName,
      'store_address': storeAddress,
      'store_phone': storePhone,
      'currency': currency,
      'receipt_footer': receiptFooter,
      'theme': theme,
      'accent_color': accentColor,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      id: map['id'] as int?,
      storeName: map['store_name'] as String,
      storeAddress: map['store_address'] as String? ?? '',
      storePhone: map['store_phone'] as String? ?? '',
      currency: map['currency'] as String? ?? 'PHP',
      receiptFooter: map['receipt_footer'] as String?,
      theme: map['theme'] as String?,
      accentColor: map['accent_color'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Settings copyWith({
    int? id,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? currency,
    String? receiptFooter,
    String? theme,
    String? accentColor,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Settings(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhone: storePhone ?? this.storePhone,
      currency: currency ?? this.currency,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      theme: theme ?? this.theme,
      accentColor: accentColor ?? this.accentColor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
