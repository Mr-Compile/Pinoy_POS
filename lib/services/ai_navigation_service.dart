import 'package:pinoy_pos/core/ai_navigation_registry.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/external_link_validator.dart';
import 'package:pinoy_pos/services/sales_service.dart';

/// Local, offline-first navigation assistant. It maps natural-language
/// navigation or how-to queries to registered destinations and produces a
/// structured [AIResponse] that the chat UI can render.
///
/// The AI model is *not* trusted to decide whether the user can navigate.
/// This service constructs candidate actions from the destination registry,
/// then the caller (or the chat UI) filters them through the real permission
/// system before any navigation occurs.
class AINavigationService {
  AINavigationService._();

  static SalesService _salesService = SalesService();

  /// Allows tests to inject a fake [SalesService] without relying on the
  /// production database.
  static set salesService(SalesService service) => _salesService = service;

  /// A loose keyword map from user queries to destination IDs. It is used
  /// only for local intent detection; the registry is still the source of
  /// truth for whether a destination exists and is allowed.
  static final Map<List<String>, String> _intentMap = {
    ['dashboard', 'overview', 'home', 'main', 'today']: 'dashboard',
    ['pos', 'point of sale', 'checkout', 'cart', 'sell']: 'pos',
    ['products', 'product', 'item', 'items', 'inventory']: 'products',
    ['categories', 'category']: 'categories',
    ['stock', 'inventory', 'low stock', 'out of stock']: 'stock',
    ['sales', 'sale', 'transactions', 'orders', 'receipts']: 'sales',
    ['sale detail', 'transaction detail', 'order detail']: 'sale_details',
    ['receipt', 'receipts']: 'receipt',
    ['reports', 'report', 'analytics', 'summary', 'export']: 'reports',
    ['users', 'user', 'staff', 'employees', 'manage users']: 'users',
    ['settings', 'configuration', 'preferences']: 'settings',
    ['ai config', 'ai configuration', 'groq', 'ai settings']: 'ai_settings',
    ['ai quota', 'quota', 'daily limit']: 'ai_quota',
    ['backup', 'restore', 'backup restore', 'back up']: 'backup_restore',
    ['activity logs', 'logs', 'history']: 'activity_logs',
    ['trash', 'trash bin', 'deleted']: 'trash',
    ['profile', 'my account', 'account']: 'profile',
    ['notifications', 'alerts', 'messages']: 'notifications',
    ['announcements', 'announcement', 'notices']: 'announcements',
    ['more', 'extras', 'other']: 'more',
    ['help', 'support', 'documentation', 'docs']: 'support_page',
  };

  /// Detects whether [query] is asking for navigation or instructions.
  ///
  /// Returns the best-matching destination ID, or null when the query is not
  /// a recognized navigation request.
  ///
  /// The detection is intentionally conservative. Analytics questions such as
  /// "what is my top product?" must be handled by the conversational AI, not
  /// routed to the Products screen.
  static String? detectNavigationIntent(String query) {
    final lower = query.toLowerCase().trim();

    // Specific deep-link patterns first: sale/receipt by ID and external help.
    // Receipt checks must precede sale checks so "receipt for sale #1024"
    // resolves to the receipt destination, not sale details.
    final receiptSaleId = _extractReceiptSaleId(lower);
    if (receiptSaleId != null) return 'receipt';

    final saleDetail = _extractSaleId(lower);
    if (saleDetail != null) return 'sale_details';

    if (_matchesLatestSale(lower)) return 'sale_details';

    if (_matchesExternalLink(lower)) return _resolveExternalLink(lower);

    // Direct navigational phrases.
    final navigationalPrefixes = [
      'open ',
      'go to ',
      'take me to ',
      'take me ',
      'show me ',
      'show ',
      'navigate to ',
      'navigate ',
      'where is ',
      'where are ',
      'where are my ',
      'where can i find ',
      'where can i see ',
      'where can i ',
      'how do i get to ',
      'how do i open ',
      'how do i go to ',
      'how to open ',
      'how to go to ',
      'how to access ',
      'how can i open ',
      'how can i access ',
      'i want to see ',
      'i need to see ',
      'view ',
    ];

    for (final prefix in navigationalPrefixes) {
      if (lower.startsWith(prefix)) {
        final intentPart = lower.substring(prefix.length).trim();
        final match = _findDestination(intentPart);
        if (match != null) return match;
      }
    }

    // General how-to patterns such as "how do I add a product?".
    if (lower.startsWith('how do i ') ||
        lower.startsWith('how to ') ||
        lower.startsWith('how can i ')) {
      final match = _findDestination(lower);
      if (match != null) return match;
    }

    // Very short, direct requests like "products", "sales", "settings".
    // Avoid longer analytics questions that happen to contain a keyword.
    final wordCount =
        lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount <= 3) {
      return _findDestination(lower);
    }

    return null;
  }

  static String? _findDestination(String normalizedQuery) {
    String? bestMatch;
    int bestLength = 0;

    for (final entry in _intentMap.entries) {
      for (final phrase in entry.key) {
        if (normalizedQuery.contains(phrase)) {
          // Prefer longer, more specific matches.
          if (phrase.length > bestLength) {
            bestLength = phrase.length;
            bestMatch = entry.value;
          }
        }
      }
    }

    return bestMatch;
  }

  /// Produces a structured [AIResponse] for a navigation or how-to query.
  ///
  /// [currentDestinationId] is the screen the user is already on, so we can
  /// avoid suggesting redundant navigation. [role] and [hasPermission] are
  /// used to filter out destinations the user cannot access.
  ///
  /// Returns null when the query is not a recognized navigation request.
  static Future<AIResponse?> resolveNavigationResponse(
    String query, {
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
  }) async {
    final lower = query.toLowerCase().trim();

    // Deep-link: receipt by explicit ID.
    final receiptSaleId = _extractReceiptSaleId(lower);
    if (receiptSaleId != null) {
      return _buildDetailResponse(
        destinationId: 'receipt',
        saleId: receiptSaleId,
        role: role,
        hasPermission: hasPermission,
        currentDestinationId: currentDestinationId,
        defaultLabel: 'Open Receipt',
      );
    }

    // Deep-link: sale detail by explicit ID.
    final saleId = _extractSaleId(lower);
    if (saleId != null) {
      return _buildDetailResponse(
        destinationId: 'sale_details',
        saleId: saleId,
        role: role,
        hasPermission: hasPermission,
        currentDestinationId: currentDestinationId,
        defaultLabel: 'View Sale',
      );
    }

    // Deep-link: latest sale.
    if (_matchesLatestSale(lower)) {
      final latest = await _findLatestSale(hasPermission);
      if (latest != null) {
        return _buildDetailResponse(
          destinationId: 'sale_details',
          saleId: latest.id!,
          role: role,
          hasPermission: hasPermission,
          currentDestinationId: currentDestinationId,
          defaultLabel: 'View Sale',
          prefixMessage:
              'Your latest sale is #${latest.receiptNumber ?? latest.id}.',
        );
      }
      if (!hasPermission('view_sales')) {
        return _unauthorizedResponse('Sale Details');
      }
      return AIResponse(
        message: 'No sales were found in the system.',
        instructions: const [],
        actions: const [],
        suggestions: const ['Show my dashboard'],
      );
    }

    // External link requests.
    final externalId = _resolveExternalLink(lower);
    if (externalId != null) {
      return _buildExternalResponse(externalId, hasPermission);
    }

    final destinationId = detectNavigationIntent(query);
    if (destinationId == null) return null;

    final destination = AINavigationRegistry.get(destinationId);
    if (destination == null) return null;

    final isAuthorized = _isDestinationAllowed(destination, role, hasPermission);

    // Instructional text.
    final message = _buildMessage(
      destination: destination,
      isAuthorized: isAuthorized,
      isAlreadyOnScreen: destinationId == currentDestinationId,
    );

    // Main action, only if the user can access it and is not already there.
    final actions = <AIAction>[];
    if (isAuthorized && destinationId != currentDestinationId) {
      actions.add(
        AIAction(
          type: AIActionType.navigate,
          destination: destination.id,
          label: 'Open ${destination.displayName}',
        ),
      );
    }

    // Instructions based on the registry.
    final instructions = destination.howToSteps
        .map((step) => AIInstruction(text: step))
        .toList();

    // Suggestions from related destinations that the user can access.
    final suggestions = _buildSuggestions(
      destination: destination,
      role: role,
      hasPermission: hasPermission,
      currentDestinationId: currentDestinationId,
    );

    return AIResponse(
      message: message,
      instructions: instructions,
      actions: actions,
      suggestions: suggestions,
    );
  }

  /// Returns a plain-language response explaining why the user cannot access
  /// a requested destination.
  static AIResponse unauthorizedResponse(String requestedDestinationName) {
    return _unauthorizedResponse(requestedDestinationName);
  }

  static AIResponse _unauthorizedResponse(String requestedDestinationName) {
    return AIResponse(
      message:
          "$requestedDestinationName isn't available for your current account "
          "permissions. You can still manage the features available to you.",
      instructions: const [],
      actions: const [],
      suggestions: const [
        'What can I access?',
        'Show my dashboard',
      ],
    );
  }

  static bool _isDestinationAllowed(
    AIDestination destination,
    UserRole? role,
    bool Function(String) hasPermission,
  ) {
    if (destination.allowedRoles.isNotEmpty &&
        !destination.allowedRoles.contains(role)) {
      return false;
    }
    return hasPermission(destination.requiredPermission);
  }

  static String _buildMessage({
    required AIDestination destination,
    required bool isAuthorized,
    required bool isAlreadyOnScreen,
  }) {
    if (!isAuthorized) {
      return "${destination.displayName} isn't available for your current "
          "account permissions.";
    }

    if (isAlreadyOnScreen) {
      return "You're already in ${destination.displayName}.\n\n"
          "Here's how to use it:";
    }

    return "You can ${destination.description.toLowerCase()} from "
        "${destination.displayName}.";
  }

  static List<String> _buildSuggestions({
    required AIDestination destination,
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
  }) {
    final result = <String>[];

    for (final relatedId in destination.relatedDestinations) {
      if (relatedId == currentDestinationId) continue;
      final related = AINavigationRegistry.get(relatedId);
      if (related == null) continue;
      if (!_isDestinationAllowed(related, role, hasPermission)) continue;

      result.add(related.description);
    }

    return result.take(4).toList();
  }

  // ── Deep-link helpers ─────────────────────────────────────────────────

  static final _saleIdPattern = RegExp(
    r'(?:sale|transaction|order)(?:\s*(?:#|number|num|no\.?|id))?\s*[:\s-]*(\d+)',
    caseSensitive: false,
  );

  static final _receiptIdPattern = RegExp(
    r'(?:receipt)(?:\s+(?:for\s+)?(?:sale\s*)?)?\s*(?:#|number|num|no\.?|id)?\s*[:\s-]*(\d+)',
    caseSensitive: false,
  );

  static int? _extractSaleId(String query) {
    final match = _saleIdPattern.firstMatch(query);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static int? _extractReceiptSaleId(String query) {
    final match = _receiptIdPattern.firstMatch(query);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static final _latestSalePattern = RegExp(
    r'(?:latest|last|most recent)(?:\s+(?:sale|transaction|order))',
    caseSensitive: false,
  );

  static bool _matchesLatestSale(String query) => _latestSalePattern.hasMatch(query);

  static Future<Sale?> _findLatestSale(bool Function(String) hasPermission) async {
    if (!hasPermission('view_sales')) return null;
    try {
      return _salesService.getLatestSale();
    } catch (_) {
      return null;
    }
  }

  static AIResponse _buildDetailResponse({
    required String destinationId,
    required int saleId,
    required UserRole? role,
    required bool Function(String) hasPermission,
    String? currentDestinationId,
    required String defaultLabel,
    String? prefixMessage,
  }) {
    final destination = AINavigationRegistry.get(destinationId);
    if (destination == null) return _unknownResponse();

    final isAuthorized = _isDestinationAllowed(destination, role, hasPermission);
    if (!isAuthorized) {
      return _unauthorizedResponse(destination.displayName);
    }

    final isAlreadyOnScreen = currentDestinationId == destinationId;
    final message = prefixMessage ??
        (isAlreadyOnScreen
            ? "You're already viewing this record."
            : "You can view the ${destination.description.toLowerCase()} for sale #$saleId.");

    final actions = <AIAction>[];
    if (!isAlreadyOnScreen) {
      actions.add(
        AIAction(
          type: AIActionType.openDetail,
          destination: destination.id,
          label: '$defaultLabel #$saleId',
          parameters: {'saleId': saleId},
        ),
      );
    }

    return AIResponse(
      message: message,
      instructions: destination.howToSteps
          .map((step) => AIInstruction(text: step))
          .toList(),
      actions: actions,
      suggestions: _buildSuggestions(
        destination: destination,
        role: role,
        hasPermission: hasPermission,
        currentDestinationId: currentDestinationId,
      ),
    );
  }

  static final _externalLinkPatterns = {
    'groq_documentation': ['groq docs', 'groq documentation'],
    'support_page': ['support', 'help center', 'help'],
    'official_documentation': ['documentation', 'manual'],
    'privacy_policy': ['privacy policy', 'privacy'],
    'terms': ['terms of service', 'terms', 'tos'],
  };

  static bool _matchesExternalLink(String query) {
    return _resolveExternalLink(query) != null;
  }

  static String? _resolveExternalLink(String query) {
    final lower = query;
    for (final entry in _externalLinkPatterns.entries) {
      for (final phrase in entry.value) {
        if (lower.contains(phrase)) return entry.key;
      }
    }
    return null;
  }

  static AIResponse _buildExternalResponse(
    String externalId,
    bool Function(String) hasPermission,
  ) {
    final destination = ExternalDestinationRegistry.get(externalId);
    if (destination == null) return _unknownResponse();

    if (!ExternalDestinationRegistry.canAccess(externalId,
        hasPermission: hasPermission)) {
      return _unauthorizedResponse(destination.label);
    }

    return AIResponse(
      message: 'Need more information? You can open ${destination.label}.',
      instructions: const [],
      actions: [
        AIAction(
          type: AIActionType.externalLink,
          destination: destination.id,
          label: 'Open ${destination.label}',
        ),
      ],
      suggestions: const [],
    );
  }

  static AIResponse _unknownResponse() {
    return const AIResponse(
      message: "I'm not sure how to help with that navigation request.",
      instructions: [],
      actions: [],
      suggestions: ['Show my dashboard'],
    );
  }
}