import 'package:pinoy_pos/data/models/user.dart';

/// Centralized role-aware AI Advisor configuration.
///
/// The AI Advisor is available to ALL THREE roles (Owner, Admin, Staff),
/// but each role gets a different assistant identity, suggested questions,
/// and contextual recommendations based on their permissions:
///
/// - **Owner** → AI Business Advisor: business-wide sales, products,
///   inventory, trends, and recommendations.
/// - **Admin** → AI System Assistant: user accounts, activity logs,
///   backups, exports, and system status.
/// - **Staff** → AI Work Assistant: own sales, low-stock alerts,
///   products, and own activity.
///
/// The actual data each role can access is enforced by [AICapabilityPolicy]
/// and [BusinessIntelligenceService] at the service and database layers.
/// This class only controls the UI presentation.
class AIRoleConfig {
  final UserRole role;

  AIRoleConfig(this.role);

  /// The display title for the AI chat screen header.
  String get title {
    switch (role) {
      case UserRole.owner:
        return 'AI Business Advisor';
      case UserRole.admin:
        return 'AI System Assistant';
      case UserRole.staff:
        return 'AI Work Assistant';
    }
  }

  /// The subtitle/description shown under the title.
  String get subtitle {
    switch (role) {
      case UserRole.owner:
        return 'Understand your sales, inventory, and business performance.';
      case UserRole.admin:
        return 'Get insights about users, system activity, backups, and administration.';
      case UserRole.staff:
        return 'Get help understanding your sales, products, and daily operations.';
    }
  }

  /// Returns the welcome message for the AI chat screen.
  String get welcomeMessage {
    switch (role) {
      case UserRole.owner:
        return 'I can help you with business performance, sales analysis, '
            'inventory recommendations, restock priorities, product '
            'performance, category performance, trends, and business insights.';
      case UserRole.admin:
        return 'I can help you with user account summaries, system activity, '
            'backup history, export history, and system status. Ask me '
            'about active users, recent activity, or the latest backup.';
      case UserRole.staff:
        return 'I can help you understand your own sales, low-stock alerts, '
            'product information, and your daily work activity. Ask me '
            'about your sales today or what products are low in stock.';
    }
  }

  /// Returns the list of suggested questions for the role.
  /// These are fallback suggestions; the actual suggestions shown in the
  /// UI are generated dynamically by [BusinessIntelligenceService] based
  /// on real database conditions and the user's role.
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
        return [
          'How many active users do we have?',
          'Show recent system activity.',
          'When was the latest backup?',
          'Give me a system summary.',
          'Are there any unusual failed activities?',
          'Summarize today\'s administrative activity.',
        ];
      case UserRole.staff:
        return [
          'How much did I sell today?',
          'Show my recent sales.',
          'What products are low in stock?',
          'Which products sell best in my transactions?',
          'Give me a summary of my work today.',
        ];
    }
  }

  /// Returns the list of FAQ questions for the role.
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
          'What can the AI System Assistant help me with?',
          'Can the AI create backups for me?',
          'Can the AI manage user accounts?',
        ];
      case UserRole.staff:
        return [
          'What can the AI Work Assistant help me with?',
          'Can the AI see other staff members\' sales?',
          'Can the AI help me restock products?',
        ];
    }
  }

  /// Returns a contextual recommendation based on the current screen
  /// and the user's role. Returns null if no recommendation is available.
  static String? getContextualRecommendation(UserRole role, String screenLabel) {
    final key = screenLabel.toLowerCase();

    if (role == UserRole.owner) {
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
    }

    if (role == UserRole.admin) {
      if (key.contains('dashboard')) {
        return 'Want a quick system status summary?';
      }
      if (key.contains('user') || key.contains('account')) {
        return 'I can summarize active users and their status.';
      }
      if (key.contains('activity') || key.contains('log')) {
        return 'I can analyze recent system activity for you.';
      }
      if (key.contains('backup')) {
        return 'I can show you the latest backup details.';
      }
    }

    if (role == UserRole.staff) {
      if (key.contains('dashboard')) {
        return 'Want a summary of your sales today?';
      }
      if (key.contains('stock') || key.contains('inventory')) {
        return 'I can show you which products are low in stock.';
      }
      if (key.contains('sales')) {
        return 'I can analyze your recent sales.';
      }
      if (key.contains('product')) {
        return 'I can help you find product information.';
      }
    }

    return null;
  }
}
