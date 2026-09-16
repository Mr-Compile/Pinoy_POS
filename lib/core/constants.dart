/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Database
  static const String databaseName = 'pinoy_pos.db';
  static const int databaseVersion = 27;

  // App Info
  static const String appName = 'Pinoy POS';
  static const String appVersion = '1.0.0';

  // Pagination
  static const int defaultPageSize = 10;

  // AI
  static const int maxDailyAIQueries =
      10; // Legacy fallback; prefer aiDailyQuota from Settings.
  static const int defaultDailyAIQuota = 10;
  static const int maxDailyAIQuota = 1000;

  // Security
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int pinLength = 4;
  static const String defaultTemporaryPassword = '@Password123';

  // Store
  static const String defaultReceiptFooter = 'Thank you for your purchase!';

  // GCash
  /// Minimum length accepted for a GCash reference number. Also the
  /// default stored in settings and the floor of the Payment Settings
  /// editor — a real GCash reference is 13 digits.
  static const int minGcashReferenceLength = 13;

  // Stock
  static const int defaultLowStockThreshold = 10;

  // Images
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5 MB
}
