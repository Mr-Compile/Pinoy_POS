class Settings {
  static const Object _sentinel = Object();

  final int? id;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String currency;
  final String? receiptFooter;
  final String? theme;
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
      'groq_api_key': null, // Stored in secure storage, never in the settings table
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
    String? stringOrNull(String key) {
      final value = map[key];
      return value is String ? value : null;
    }

    int? intOrNull(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    bool boolFromInt(String key) {
      final value = map[key];
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) return value == '1';
      return false;
    }

    DateTime parseDateTime(String key) {
      final value = map[key];
      if (value is DateTime) return value;
      if (value is! String) {
        throw FormatException(
          'Settings row field "$key" must be a date string, got $value.',
        );
      }
      try {
        return DateTime.parse(value);
      } catch (e) {
        throw FormatException(
          'Settings row field "$key" has invalid date "$value".',
        );
      }
    }

    return Settings(
      id: intOrNull('id'),
      storeName: stringOrNull('store_name') ?? '',
      storeAddress: stringOrNull('store_address') ?? '',
      storePhone: stringOrNull('store_phone') ?? '',
      currency: stringOrNull('currency') ?? 'PHP',
      receiptFooter: stringOrNull('receipt_footer'),
      theme: stringOrNull('theme'),
      groqApiKey: null, // Stored in flutter_secure_storage, never in memory from the DB
      groqModel: stringOrNull('groq_model'),
      gcashEnabled: boolFromInt('gcash_enabled'),
      gcashReferenceRequired: boolFromInt('gcash_reference_required'),
      gcashCustomerNameRequirement:
          stringOrNull('gcash_customer_name_requirement') ?? 'optional',
      gcashPaymentProofRequirement:
          stringOrNull('gcash_payment_proof_requirement') ?? 'optional',
      gcashVerificationMode:
          stringOrNull('gcash_verification_mode') ?? 'immediate',
      gcashReferenceMinLength: intOrNull('gcash_reference_min_length') ?? 6,
      aiDailyQuota: intOrNull('ai_daily_quota') ?? 20,
      createdAt: parseDateTime('created_at'),
      updatedAt: parseDateTime('updated_at'),
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
    Object? groqApiKey = _sentinel,
    Object? groqModel = _sentinel,
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
      groqApiKey:
          groqApiKey == _sentinel ? this.groqApiKey : groqApiKey as String?,
      groqModel:
          groqModel == _sentinel ? this.groqModel : groqModel as String?,
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
