import 'package:pinoy_pos/data/models/user.dart';

/// Centralized role-aware AI Advisor configuration.
///
/// Provides suggested questions, FAQ entries, and contextual recommendations
/// based on the current user's role. This ensures suggestions never lead
/// users toward unauthorized features.
class AIRoleConfig {
  final UserRole role;

  AIRoleConfig(this.role);

  /// Returns the welcome message for the AI chat panel.
  String get welcomeMessage {
    switch (role) {
      case UserRole.owner:
        return 'I can help you with business performance, sales analysis, '
            'inventory recommendations, reports, and business insights.';
      case UserRole.admin:
        return 'I can help you with user management, backup and restore, '
            'system settings, and system activity logs.';
      case UserRole.staff:
        return 'I can help you with POS guidance, product information, '
            'your own sales, and operational tips.';
    }
  }

  /// Returns the list of suggested questions for the current role.
  List<String> get suggestedQuestions {
    switch (role) {
      case UserRole.owner:
        return [
          'How are my sales performing today?',
          'What products are selling the most?',
          'Which products are low in stock?',
          'Give me a summary of my business performance.',
          'What should I restock soon?',
          'Compare my recent sales trends.',
          'What can I improve in my business today?',
          'Show me important business insights.',
        ];
      case UserRole.admin:
        return [
          'How do I manage user accounts?',
          'Which users are currently inactive?',
          'How do I create a backup?',
          'How do I restore a backup safely?',
          'Explain the recent system activity.',
          'How can I manage deleted records?',
          'Help me review system settings.',
          'Show me what I can manage in my role.',
        ];
      case UserRole.staff:
        return [
          'How do I process a sale?',
          'How do I add stock?',
          'Show me how to check my sales.',
          'How do I find a product quickly?',
          'How do I manage my profile?',
          'What does this notification mean?',
          'Help me understand my authorized reports.',
          'How can I use the POS faster?',
        ];
    }
  }

  /// Returns the list of FAQ questions for the current role.
  List<String> get faqQuestions {
    switch (role) {
      case UserRole.owner:
        return [
          'What can the AI Advisor help me with?',
          'How accurate is the business data?',
          'Can the AI restock products for me?',
        ];
      case UserRole.admin:
        return [
          'What can the AI Advisor help me with?',
          'Can the AI manage users for me?',
          'How do I check backup status?',
        ];
      case UserRole.staff:
        return [
          'What can the AI Advisor help me with?',
          'Can the AI see other people\'s sales?',
          'How do I check my own sales?',
        ];
    }
  }

  /// Returns a contextual recommendation based on the current screen
  /// and the user's role. Returns null if no recommendation is available.
  static String? getContextualRecommendation(UserRole role, String screenLabel) {
    final key = screenLabel.toLowerCase();
    switch (role) {
      case UserRole.owner:
        if (key.contains('dashboard')) {
          return 'Want a quick summary of today\'s business performance?';
        }
        if (key.contains('stock') || key.contains('inventory')) {
          return 'I can help identify low-stock products.';
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
      case UserRole.admin:
        if (key.contains('user')) {
          return 'Need help managing user accounts?';
        }
        if (key.contains('backup') || key.contains('restore')) {
          return 'I can guide you through creating or restoring a backup.';
        }
        if (key.contains('setting')) {
          return 'I can help you review system settings.';
        }
        if (key.contains('trash')) {
          return 'I can help with trash management guidance.';
        }
        return null;
      case UserRole.staff:
        if (key.contains('pos')) {
          return 'Need help processing a sale?';
        }
        if (key.contains('sale') && key.contains('my')) {
          return 'I can help explain your own sales summary.';
        }
        if (key.contains('notification')) {
          return 'I can help explain this notification.';
        }
        if (key.contains('product')) {
          return 'I can help you find product information quickly.';
        }
        if (key.contains('stock')) {
          return 'I can guide you through adding stock.';
        }
        return null;
    }
  }
}
