import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';

/// Result of an AI Advisor query.
class AIAdvisorResult {
  final bool success;
  final String? content;
  final String? errorMessage;
  final bool isNotConfigured;
  final bool isNetworkError;
  final bool isAuthError;
  final bool limitReached;

  AIAdvisorResult({
    required this.success,
    this.content,
    this.errorMessage,
    this.isNotConfigured = false,
    this.isNetworkError = false,
    this.isAuthError = false,
    this.limitReached = false,
  });
}

/// Orchestrates AI Advisor queries: permission check → usage limit check →
/// gather real business data → build prompt → call Groq → record usage.
///
/// The service is authoritative for both permission and the 10/day limit.
/// The UI cannot bypass either check.
class AIAdvisorService {
  final GroqService _groqService = GroqService();
  final AIUsageService _aiUsageService = AIUsageService();
  final SettingsService _settingsService = SettingsService();
  final SessionManager _sessionManager = SessionManager();
  final SaleRepository _saleRepository = SaleRepository();
  final ProductRepository _productRepository = ProductRepository();

  /// Submits a query to the AI Advisor.
  ///
  /// Steps:
  /// 1. Check `view_ai_advisor` permission.
  /// 2. Check 10/day usage limit (via [AIUsageService]).
  /// 3. Check that a Groq API key is configured.
  /// 4. Gather real business data from SQLite.
  /// 5. Build a system prompt with the data context.
  /// 6. Call Groq.
  /// 7. Record the query + response via [AIUsageService].
  /// 8. Return the result.
  Future<AIAdvisorResult> query(String userQuery) async {
    // 1. Permission check.
    if (!_sessionManager.hasPermission('view_ai_advisor')) {
      throw AuthorizationException('view_ai_advisor');
    }

    // 2. Usage limit check (service-authoritative).
    if (!await _aiUsageService.canUseAI()) {
      return AIAdvisorResult(
        success: false,
        limitReached: true,
        errorMessage:
            'You have used all 10 AI queries for today. Please try again tomorrow.',
      );
    }

    // 3. Check Groq configuration.
    final apiKey = await _settingsService.getGroqApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return AIAdvisorResult(
        success: false,
        isNotConfigured: true,
        errorMessage:
            'AI Advisor is not configured. Please ask an administrator to configure the Groq AI API key.',
      );
    }
    final model = await _settingsService.getGroqModel();

    // 4. Gather real business data.
    final dataContext = await _buildDataContext();

    // 5. Build prompt.
    final systemPrompt = _buildSystemPrompt(dataContext);

    // 6. Call Groq.
    final groqResult = await _groqService.chatCompletion(
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userMessage: userQuery,
    );

    if (!groqResult.success) {
      return AIAdvisorResult(
        success: false,
        errorMessage: groqResult.errorMessage,
        isNetworkError: groqResult.isNetworkError,
        isAuthError: groqResult.isAuthError,
      );
    }

    // 7. Record usage.
    final recorded =
        await _aiUsageService.recordQuery(userQuery, groqResult.content);

    if (!recorded) {
      // Race condition: limit was hit between check and record.
      return AIAdvisorResult(
        success: false,
        limitReached: true,
        errorMessage:
            'You have used all 10 AI queries for today. Please try again tomorrow.',
      );
    }

    // 8. Return result.
    return AIAdvisorResult(success: true, content: groqResult.content);
  }

  /// Gathers real business data from SQLite to include in the AI prompt.
  /// No mock data, no hardcoded statistics.
  Future<String> _buildDataContext() async {
    final buffer = StringBuffer();
    buffer.writeln('--- BUSINESS DATA (real, from SQLite) ---');

    // Sales data.
    final List<Sale> recentSales;
    if (_sessionManager.currentUser?.role.toString() == 'UserRole.staff') {
      recentSales = await _saleRepository
          .getByUserId(_sessionManager.currentUser!.id!);
    } else {
      recentSales = await _saleRepository.getAllActive(limit: 50);
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todaySales = recentSales
        .where((s) =>
            s.createdAt.isAfter(todayStart) && s.createdAt.isBefore(todayEnd))
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final monthSales = recentSales
        .where((s) => s.createdAt.isAfter(monthStart))
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final totalRevenue =
        recentSales.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final avgSale =
        recentSales.isEmpty ? 0.0 : totalRevenue / recentSales.length;

    buffer.writeln('Sales:');
    buffer.writeln('  - Total recorded sales: ${recentSales.length}');
    buffer.writeln('  - Today\'s sales: PHP ${todaySales.toStringAsFixed(2)}');
    buffer
        .writeln('  - This month\'s sales: PHP ${monthSales.toStringAsFixed(2)}');
    buffer.writeln(
        '  - Total revenue (all records): PHP ${totalRevenue.toStringAsFixed(2)}');
    buffer.writeln(
        '  - Average sale value: PHP ${avgSale.toStringAsFixed(2)}');

    // Product / inventory data.
    final products = await _productRepository.getActiveProducts();
    final lowStock = products.where((p) => p.isLowStock).toList();

    buffer.writeln('Inventory:');
    buffer.writeln('  - Active products: ${products.length}');
    buffer.writeln('  - Low stock items: ${lowStock.length}');
    if (lowStock.isNotEmpty) {
      buffer.writeln('  - Low stock details:');
      for (final p in lowStock.take(10)) {
        buffer
            .writeln('    * ${p.name}: ${p.stock} units (min: ${p.minStock})');
      }
    }

    buffer.writeln('--- END BUSINESS DATA ---');
    return buffer.toString();
  }

  String _buildSystemPrompt(String dataContext) {
    return '''You are a business advisor for a Philippine point-of-sale (POS) system called Pinoy POS. You analyze real store data and provide actionable business insights.

Always:
- Use the provided real business data to ground your analysis.
- Be concise and practical.
- Use PHP (Philippine Peso) as the currency.
- Focus on sales analysis, inventory recommendations, and business insights.
- If data is sparse, acknowledge it and give general advice.

$dataContext''';
  }
}
