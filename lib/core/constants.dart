/// Application-wide constants
class AppConstants {
  AppConstants._();

  // Database
  static const String databaseName = 'pinoy_pos.db';
  static const int databaseVersion = 1;

  // App Info
  static const String appName = 'Pinoy POS';
  static const String appVersion = '1.0.0';

  // Pagination
  static const int defaultPageSize = 20;

  // AI
  static const int maxDailyAIQueries = 10;

  // Security
  static const int minPasswordLength = 8;
  static const int pinLength = 4;

  // Stock
  static const int defaultLowStockThreshold = 10;
}
