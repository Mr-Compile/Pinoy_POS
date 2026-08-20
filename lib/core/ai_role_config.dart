import 'package:pinoy_pos/data/models/user.dart';

/// Centralized role-aware AI Advisor configuration.
///
/// The AI Business Advisor is available ONLY to the Owner. Admin manages
/// AI configuration (API key, model) but does not use business analysis.
/// Staff has no AI access at all.
///
/// This config provides suggested questions and contextual recommendations
/// for the Owner's Business Advisor.
class AIRoleConfig {
  final UserRole role;

  AIRoleConfig(this.role);

  /// Returns the welcome message for the AI chat screen.
  String get welcomeMessage {
    switch (role) {
      case UserRole.owner:
        return 'I can help you with business performance, sales analysis, '
            'inventory recommendations, restock priorities, product '
            'performance, category performance, trends, and business insights.';
      case UserRole.admin:
        return 'AI configuration is managed in Settings → AI Integration. '
            'The Business Advisor is available to the Owner only.';
      case UserRole.staff:
        return 'The AI Business Advisor is not available for your role.';
    }
  }

  /// Returns the list of suggested questions for the Owner.
  /// These are fallback suggestions; the actual suggestions shown in the
  /// UI are generated dynamically by [BusinessIntelligenceService] based
  /// on real database conditions.
  List<String> get suggestedQuestions {
    switch (role) {
      case UserRole.owner:
        return [
          'How are my sales today?',
          'What products are selling the most?',
          'Which products are low in stock?',
          'Give me a summary of my business performance.',
          'What should I restock soon?',
          'Compare my recent sales trends.',
          'What can I improve in my business today?',
          'Show me important business insights.',
        ];
      case UserRole.admin:
        return [];
      case UserRole.staff:
        return [];
    }
  }

  /// Returns the list of FAQ questions for the Owner.
  List<String> get faqQuestions {
    switch (role) {
      case UserRole.owner:
        return [
          'What can the AI Advisor help me with?',
          'How accurate is the business data?',
          'Can the AI restock products for me?',
        ];
      case UserRole.admin:
        return [];
      case UserRole.staff:
        return [];
    }
  }

  /// Returns a contextual recommendation based on the current screen
  /// and the user's role. Returns null if no recommendation is available.
  static String? getContextualRecommendation(UserRole role, String screenLabel) {
    if (role != UserRole.owner) return null;

    final key = screenLabel.toLowerCase();
    if (key.contains('dashboard')) {
      return 'Want a quick summary of today\'s business performance?';
    }
    if (key.contains('stock') || key.contains('inventory')) {
      return 'I can help identify low-stock products and restock priorities.';
    }
    if (key.contains('sales')) {
      return 'I can analyze your sales trends and patterns.';
    }
    if (key.contains('product')) {
      return 'I can help with product performance insights.';
    }
    if (key.contains('report')) {
      return 'I can help interpret your business reports.';
    }
    return null;
  }
}
