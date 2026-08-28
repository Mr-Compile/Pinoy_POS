class Settings {
  final int? id;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String currency;
  final String? receiptFooter;
  final String? theme;
  final String? accentColor;
  final String? groqApiKey;
  final String? groqModel;
  final bool gcashEnabled;
  final bool gcashReferenceRequired;
  final String gcashCustomerNameRequirement;
  final String gcashPaymentProofRequirement;
  final String gcashVerificationMode;
  final int gcashReferenceMinLength;
  final int aiDailyQuota;
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
    this.groqApiKey,
    this.groqModel,
    this.gcashEnabled = true,
    this.gcashReferenceRequired = true,
    this.gcashCustomerNameRequirement = 'optional',
    this.gcashPaymentProofRequirement = 'optional',
    this.gcashVerificationMode = 'immediate',
    this.gcashReferenceMinLength = 6,
    this.aiDailyQuota = 20,
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
      'groq_api_key': groqApiKey,
      'groq_model': groqModel,
      'gcash_enabled': gcashEnabled ? 1 : 0,
      'gcash_reference_required': gcashReferenceRequired ? 1 : 0,
      'gcash_customer_name_requirement': gcashCustomerNameRequirement,
      'gcash_payment_proof_requirement': gcashPaymentProofRequirement,
      'gcash_verification_mode': gcashVerificationMode,
      'gcash_reference_min_length': gcashReferenceMinLength,
      'ai_daily_quota': aiDailyQuota,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      id: map['id'] as int?,
      storeName: map['store_name'] as String,
      storeAddress: (map['store_address'] as String?) ?? '',
      storePhone: (map['store_phone'] as String?) ?? '',
      currency: (map['currency'] as String?) ?? 'PHP',
      receiptFooter: map['receipt_footer'] as String?,
      theme: map['theme'] as String?,
      accentColor: map['accent_color'] as String?,
      groqApiKey: map['groq_api_key'] as String?,
      groqModel: map['groq_model'] as String?,
      gcashEnabled: (map['gcash_enabled'] as int?) == 1,
      gcashReferenceRequired: (map['gcash_reference_required'] as int?) == 1,
      gcashCustomerNameRequirement:
          (map['gcash_customer_name_requirement'] as String?) ?? 'optional',
      gcashPaymentProofRequirement:
          (map['gcash_payment_proof_requirement'] as String?) ?? 'optional',
      gcashVerificationMode:
          (map['gcash_verification_mode'] as String?) ?? 'immediate',
      gcashReferenceMinLength: (map['gcash_reference_min_length'] as int?) ?? 6,
      aiDailyQuota: (map['ai_daily_quota'] as int?) ?? 20,
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
    String? groqApiKey,
    String? groqModel,
    bool? gcashEnabled,
    bool? gcashReferenceRequired,
    String? gcashCustomerNameRequirement,
    String? gcashPaymentProofRequirement,
    String? gcashVerificationMode,
    int? gcashReferenceMinLength,
    int? aiDailyQuota,
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
      groqApiKey: groqApiKey ?? this.groqApiKey,
      groqModel: groqModel ?? this.groqModel,
      gcashEnabled: gcashEnabled ?? this.gcashEnabled,
      gcashReferenceRequired: gcashReferenceRequired ?? this.gcashReferenceRequired,
      gcashCustomerNameRequirement:
          gcashCustomerNameRequirement ?? this.gcashCustomerNameRequirement,
      gcashPaymentProofRequirement:
          gcashPaymentProofRequirement ?? this.gcashPaymentProofRequirement,
      gcashVerificationMode: gcashVerificationMode ?? this.gcashVerificationMode,
      gcashReferenceMinLength: gcashReferenceMinLength ?? this.gcashReferenceMinLength,
      aiDailyQuota: aiDailyQuota ?? this.aiDailyQuota,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isGcashEnabled => gcashEnabled;
}
