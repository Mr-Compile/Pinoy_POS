import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/core/ai_capability_policy.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_response_policy.dart';
import 'package:pinoy_pos/services/ai_usage_service.dart';
import 'package:pinoy_pos/services/business_intelligence_service.dart';
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
  final bool isModelError;
  final bool isRateLimit;
  final bool limitReached;
  final bool isModelUnavailable;

  AIAdvisorResult({
    required this.success,
    this.content,
    this.errorMessage,
    this.isNotConfigured = false,
    this.isNetworkError = false,
    this.isAuthError = false,
    this.isModelError = false,
    this.isRateLimit = false,
    this.limitReached = false,
    this.isModelUnavailable = false,
  });
}

/// Result of model validation.
class ModelValidationResult {
  final bool valid;
  final bool modelExists;
  final String? errorMessage;

  ModelValidationResult({
    required this.valid,
    this.modelExists = false,
    this.errorMessage,
  });
}

/// A single message in the conversation history (for multi-turn context).
class ConversationMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  ConversationMessage({required this.role, required this.content});

  Map<String, String> toGroqMessage() => {'role': role, 'content': content};
}

/// Orchestrates AI Advisor queries with role-aware security and a
/// controlled Business Intelligence layer.
///
/// Architecture:
///   UI → Provider → AIAdvisorService
///     → AICapabilityPolicy (role → allowed intents)
///     → BusinessIntelligenceService → Repository → DAO → SQLite
///     → Aggregated Facts → Context Builder → GroqService → Groq API
///     → Role-Appropriate Explanation
///
/// Security:
/// 1. Check `use_ai_advisor` permission (Owner, Admin, or Staff).
/// 2. Check 10/day usage limit (via [AIUsageService]).
/// 3. Check that a Groq API key is configured.
/// 4. Validate the saved model against available Groq models.
/// 5. Detect the user's analytical intent (role-aware).
/// 6. Enforce [AICapabilityPolicy] — reject intents outside the role's
///    allowed set. The user's message cannot override the role.
/// 7. Gather ONLY the relevant facts via [BusinessIntelligenceService],
///    filtered by role and (for Staff) currentUserId at the SQL level.
/// 8. Build a role-specific system prompt with the facts as context.
/// 9. Send the conversation (system prompt + history + user query) to Groq.
/// 10. Record the query + response via [AIUsageService].
/// 11. Return the result.
///
/// The AI NEVER gets arbitrary SQL execution access. The AI NEVER sees
/// the raw database file. The AI only sees the aggregated facts returned
/// by [BusinessIntelligenceService], scoped to the authenticated role.
class AIAdvisorService {
  final GroqService _groqService;
  final AIUsageService _aiUsageService;
  final SettingsService _settingsService;
  final SessionManager _sessionManager;
  final BusinessIntelligenceService _biService;

  AIAdvisorService({
    GroqService? groqService,
    AIUsageService? aiUsageService,
    SettingsService? settingsService,
    SessionManager? sessionManager,
    BusinessIntelligenceService? biService,
  })  : _groqService = groqService ?? GroqService(),
        _aiUsageService = aiUsageService ?? AIUsageService(),
        _settingsService = settingsService ?? SettingsService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _biService = biService ?? BusinessIntelligenceService();

  /// Sends a user query to the AI Advisor and returns the result.
  ///
  /// [conversationHistory] provides multi-turn context (previous Q&A pairs).
  /// Fresh database data is always fetched for each query — old conversation
  /// never overrides fresh results.
  Future<AIAdvisorResult> query(
    String userQuery, {
    List<ConversationMessage> conversationHistory = const [],
  }) async {
    // 1. Permission check — Owner, Admin, or Staff.
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      throw AuthorizationException('use_ai_advisor');
    }

    // 2. Usage limit check (service-authoritative, before API call).
    if (!await _aiUsageService.canUseAI()) {
      return AIAdvisorResult(
        success: false,
        limitReached: true,
        errorMessage:
            'You have used all 10 AI queries for today. Your limit will reset tomorrow.',
      );
    }

    // 3. Check Groq configuration.
    final apiKey = await _settingsService.getGroqApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return AIAdvisorResult(
        success: false,
        isNotConfigured: true,
        errorMessage:
            'The AI service has not been configured yet. Please ask your administrator to configure the Groq AI integration.',
      );
    }
    final model = await _settingsService.getGroqModel();

    // 4. Validate the saved model against available Groq models.
    final modelValidation = await _validateModel(apiKey, model);
    if (!modelValidation.valid) {
      return AIAdvisorResult(
        success: false,
        isModelUnavailable: true,
        errorMessage: modelValidation.errorMessage ??
            'The configured AI model needs to be updated by an administrator.',
      );
    }

    // 5. Get the authenticated user's role and ID (trusted source —
    //    the user's message can NEVER override this).
    final currentUser = _sessionManager.currentUser;
    final role = currentUser?.role;
    final userId = currentUser?.id;

    // 6. Detect the user's analytical intent (role-aware).
    final detectedIntent = _biService.detectIntent(userQuery, role: role);

    // 7. Enforce AI capability policy — reject intents outside the role's
    //    allowed set. This is the RBAC enforcement point for AI intents.
    //    Even if intent detection maps to a disallowed intent, we fall back
    //    to `general` with a role-appropriate explanation rather than
    //    gathering unauthorized data.
    var effectiveIntent = detectedIntent;
    if (role != null && !AICapabilityPolicy.isAllowed(role, detectedIntent.intent)) {
      _log('Role $role denied intent ${detectedIntent.intent}. '
          'Falling back to general.');
      effectiveIntent = DetectedIntent(
        intent: BusinessIntent.general,
        startDate: detectedIntent.startDate,
        endDate: detectedIntent.endDate,
        periodDescription: detectedIntent.periodDescription,
      );
    }

    // 8. Gather ONLY the relevant facts, scoped by role and userId.
    //    Staff queries are filtered by sales.user_id = currentUserId at
    //    the SQL level inside BusinessIntelligenceService.
    final facts = await _biService.gatherFacts(
      effectiveIntent,
      role: role,
      userId: userId,
    );

    // 9. Build the role-specific system prompt with facts as context.
    final systemPrompt = _buildSystemPrompt(facts, role);

    // 10. Build the conversation messages for Groq.
    final messages = <Map<String, String>>[];
    // Include conversation history (last 6 messages for context).
    final recentHistory = conversationHistory.length > 6
        ? conversationHistory.sublist(conversationHistory.length - 6)
        : conversationHistory;
    for (final msg in recentHistory) {
      messages.add(msg.toGroqMessage());
    }
    // Add the current user query.
    messages.add({'role': 'user', 'content': userQuery});

    // 11. Call Groq.
    final groqResult = await _groqService.chatCompletion(
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
    );

    if (!groqResult.success) {
      return AIAdvisorResult(
        success: false,
        errorMessage: groqResult.errorMessage,
        isNetworkError: groqResult.isNetworkError,
        isAuthError: groqResult.isAuthError,
        isModelError: groqResult.isModelError,
        isRateLimit: groqResult.isRateLimit,
      );
    }

    // 12. Sanitize and validate the model's raw output before storing or
    //     displaying it.  This enforces the humanized response policy at the
    //     application layer even if the model ignores the system prompt.
    final rawContent = groqResult.content ?? '';
    final sanitized = AiResponsePolicy.sanitizeAndValidate(rawContent);
    if (sanitized.isEmpty) {
      return AIAdvisorResult(
        success: false,
        errorMessage:
            'The AI returned an empty or unsupported response. Please try again.',
      );
    }

    // 13. Record usage (only after a successful API response).
    final recorded =
        await _aiUsageService.recordQuery(userQuery, sanitized);

    if (!recorded) {
      // The limit was reached between our check and the recording (concurrent
      // request bypassed). The API call already succeeded, so we return the
      // content but warn about the limit.
      return AIAdvisorResult(
        success: true,
        content: sanitized,
      );
    }

    return AIAdvisorResult(success: true, content: sanitized);
  }

  /// Validates that the saved model exists in the current Groq model list.
  ///
  /// This prevents 404 errors from deprecated/removed models. Fetches the
  /// available models from Groq and checks if the saved model ID is present
  /// and active.
  Future<ModelValidationResult> _validateModel(
      String apiKey, String model) async {
    try {
      final modelsResult = await _groqService.listModels(apiKey: apiKey);
      if (!modelsResult.success) {
        if (modelsResult.isNetworkError) {
          // Network error — can't validate, but let the chat request
          // proceed and surface the network error there.
          return ModelValidationResult(valid: true, modelExists: true);
        }
        if (modelsResult.isAuthError) {
          // Auth error — the key is invalid. Let the chat request surface
          // this error.
          return ModelValidationResult(valid: true, modelExists: true);
        }
        // Other error — can't validate. Proceed and let the chat request
        // surface any model error.
        return ModelValidationResult(valid: true, modelExists: true);
      }

      final modelExists = modelsResult.models.any(
        (m) => m.id == model && m.active,
      );

      if (!modelExists) {
        _log('Model "$model" not found in available models. '
            'Available: ${modelsResult.models.map((m) => m.id).join(", ")}');
        return ModelValidationResult(
          valid: false,
          modelExists: false,
          errorMessage:
              'The configured AI model is no longer available. Please ask an administrator to select a different model in AI Configuration.',
        );
      }

      return ModelValidationResult(valid: true, modelExists: true);
    } catch (e) {
      _log('Model validation failed: $e');
      // Can't validate — proceed and let the chat request surface errors.
      return ModelValidationResult(valid: true, modelExists: true);
    }
  }

  /// Builds the centralized system prompt with role-specific context.
  ///
  /// The system prompt enforces:
  /// - Role-aware identity (Business Advisor / System Assistant / Work Assistant)
  /// - Facts vs Insights vs Recommendations structure
  /// - Never inventing numbers
  /// - Philippine peso formatting
  /// - No exposure of sensitive data
  /// - Clear distinction between database facts and general advice
  /// - Role-appropriate scope enforcement
  String _buildSystemPrompt(BusinessFacts facts, UserRole? role) {
    final roleIntro = switch (role) {
      UserRole.owner => '''You are the Pinoy POS AI Business Advisor.

You help the business owner understand their sales, products, inventory, and business performance.

YOUR ROLE:
- Analyze the supplied business data (sales, products, inventory, categories)
- Explain what happened and why it matters
- Give practical, actionable business recommendations
- Communicate in a clear, direct, business-focused tone''',
      UserRole.admin => '''You are the Pinoy POS AI System Assistant.

You help the system administrator understand user accounts, system activity, backups, and system health.

YOUR ROLE:
- Analyze the supplied system administration data (users, activity logs, backups, exports)
- Explain what happened and why it matters
- Give practical, actionable administrative recommendations
- Communicate in a clear, direct, system-focused tone

IMPORTANT SCOPE LIMITS:
- You do NOT have access to business sales, products, or inventory analytics.
- If the user asks about business sales, products, or inventory, explain that those topics are outside your scope and suggest they ask the business owner.
- Focus only on system administration: users, activity, backups, exports, and system status.''',
      UserRole.staff => '''You are the Pinoy POS AI Work Assistant.

You help staff members understand their own sales, products they can view, and daily operations.

YOUR ROLE:
- Analyze the supplied work data (your own sales, low-stock alerts, products, your activity)
- Explain what happened and why it matters
- Give practical, actionable operational recommendations
- Communicate in a clear, simple, helpful tone

IMPORTANT SCOPE LIMITS:
- You can only discuss the user's OWN sales and activity — never other users' data or total business sales.
- If the user asks about total business sales, other users' sales, user management, backups, or system configuration, explain that those topics are outside your scope.
- All sales data provided to you has already been filtered to this user's own transactions.''',
      null => '''You are the Pinoy POS AI Assistant.

You help the user understand their business data and operations.''',
    };

    final capabilityDesc = role != null
        ? AICapabilityPolicy.capabilityDescription(role)
        : '';

    final storeName = facts.context.contains('---')
        ? facts.context.split('\n').firstWhere(
            (line) => line.toLowerCase().contains('store:'),
            orElse: () => 'Pinoy POS',
          ).replaceFirst(RegExp(r'.*store:', caseSensitive: false), '').trim()
        : 'Pinoy POS';

    return '''$roleIntro

CURRENT ROLE: ${role?.displayName ?? 'Unknown'}
CURRENT STORE: $storeName
CAPABILITIES: $capabilityDesc

PERSONALITY AND TONE:
You are "Turing", the Pinoy POS AI assistant. Be warm, respectful, and approachable. Greet the user once in a while when the conversation starts, and close with a brief, helpful sign-off when it feels natural. Use clear, plain language. Avoid robotic or overly technical phrasing. A light Filipino touch in greetings (e.g., "Magandang araw po") is welcome, but keep the rest of the response in English unless the user writes in Filipino.

CRITICAL RULES:
1. Use ONLY the supplied Pinoy POS database analysis as the source for numerical facts.
2. Never invent sales totals, product quantities, stock levels, user counts, activity counts, dates, or trends.
3. If the supplied data is insufficient or empty, say what information is missing. Do not pretend to have data you were not given.
4. Clearly distinguish between:
   - FACTS: numbers and statements derived directly from the database data provided
   - INSIGHTS: your interpretation of those facts
   - RECOMMENDATIONS: your suggestions for what to do next
5. Do not claim to have direct unrestricted access to the database.
6. Do not expose passwords, PINs, API keys, or sensitive configuration.
7. Use Philippine peso (PHP) formatting for all monetary values.
8. When comparing periods, clearly state which periods you are comparing.
9. Be concise and practical. Do not overload the user with unnecessary technical SQL details.
10. If the user asks something outside the scope of the supplied data or outside your role's capabilities, explain the limitation clearly. You may provide general advice but must state that it is general and not based on current data.
11. Do not claim to calculate profit, profit margin, expenses, or customer demographics unless those data points are explicitly provided in the context.
12. Never claim access to data that was not supplied to you in the context below.

FINANCIAL SAFETY:
You are a business assistant, not a licensed financial or investment advisor. Do not tell the user to borrow money, invest in specific financial products, or make high-risk business decisions. Frame all monetary advice as practical operational suggestions (e.g., "consider reviewing slow-moving stock") rather than guarantees of profit.

${AiResponsePolicy.instruction}

AUTHORIZED CONTEXT:
${facts.context}

Generate a helpful, role-aware, humanized answer based ONLY on the information above.''';
  }

  /// Returns contextual suggested questions based on real database
  /// conditions. Delegates to [BusinessIntelligenceService].
  Future<List<String>> getContextualSuggestions() async {
    if (!_sessionManager.hasPermission('use_ai_advisor')) {
      return [];
    }
    return await _biService.generateContextualSuggestions();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[AIAdvisorService] $message');
    }
  }
}

