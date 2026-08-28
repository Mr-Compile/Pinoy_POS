import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/sales_service.dart';
import 'package:pinoy_pos/services/stock_service.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/notification_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/receipt_service.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/services/backup_service.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';
import 'package:pinoy_pos/services/cart_service.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/services/trash_service.dart';
import 'package:pinoy_pos/services/announcement_service.dart';
import 'package:pinoy_pos/services/user_service.dart';
import 'package:pinoy_pos/services/image_service.dart';

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService();
});

final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService();
});

final salesServiceProvider = Provider<SalesService>((ref) {
  return SalesService();
});

final cartServiceProvider = Provider<CartService>((ref) {
  return CartService();
});

final stockServiceProvider = Provider<StockService>((ref) {
  return StockService();
});

final activityLogServiceProvider = Provider<ActivityLogService>((ref) {
  return ActivityLogService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService();
});

final receiptServiceProvider = Provider<ReceiptService>((ref) {
  return ReceiptService();
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

final aiUsageServiceProvider = Provider<AIUsageService>((ref) {
  return AIUsageService();
});

final aiAdvisorServiceProvider = Provider<AIAdvisorService>((ref) {
  return AIAdvisorService(
    groqService: ref.watch(groqServiceProvider),
    aiUsageService: ref.watch(aiUsageServiceProvider),
    settingsService: ref.watch(settingsServiceProvider),
  );
});

final groqServiceProvider = Provider<GroqService>((ref) {
  return GroqService();
});

final businessIntelligenceServiceProvider =
    Provider<BusinessIntelligenceService>((ref) {
  return BusinessIntelligenceService();
});

final trashServiceProvider = Provider<TrashService>((ref) {
  return TrashService();
});

final announcementServiceProvider = Provider<AnnouncementService>((ref) {
  return AnnouncementService();
});

final userServiceProvider = Provider<UserService>((ref) {
  return UserService();
});

final imageServiceProvider = Provider<ImageService>((ref) {
  return ImageService();
});
