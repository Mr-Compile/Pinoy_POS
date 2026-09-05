/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Database
  static const String databaseName = 'pinoy_pos.db';
  static const int databaseVersion = 21;

  // App Info
  static const String appName = 'Pinoy POS';
  static const String appVersion = '1.0.0';

  // Pagination
  static const int defaultPageSize = 20;

  // AI
  static const int maxDailyAIQueries = 10; // Legacy fallback; prefer aiDailyQuota from Settings.
  static const int defaultDailyAIQuota = 20;
  static const int maxDailyAIQuota = 1000;

  // Security
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int pinLength = 4;
  static const String defaultTemporaryPassword = '@Password123';

  // Stock
  static const int defaultLowStockThreshold = 10;

  // Images
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5 MB
}
