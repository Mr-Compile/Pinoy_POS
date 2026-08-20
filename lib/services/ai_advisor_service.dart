import 'package:flutter/foundation.dart';
import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
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
///     → BusinessIntelligenceService → Repository → DAO → SQLite
///     → Aggregated Facts → Context Builder → GroqService → Groq API
///     → Business Explanation
///
/// Security:
/// 1. Check `use_ai_advisor` permission (Owner only).
/// 2. Check 10/day usage limit (via [AIUsageService]).
/// 3. Check that a Groq API key is configured.
/// 4. Validate the saved model against available Groq models.
/// 5. Detect the user's analytical intent.
/// 6. Gather ONLY the relevant business facts via [BusinessIntelligenceService].
/// 7. Build a role-specific system prompt with the facts as context.
/// 8. Send the conversation (system prompt + history + user query) to Groq.
/// 9. Record the query + response via [AIUsageService].
/// 10. Return the result.
///
/// The AI NEVER gets arbitrary SQL execution access. The AI NEVER sees
/// the raw database file. The AI only sees the aggregated facts returned
/// by [BusinessIntelligenceService].
class AIAdvisorService {
  final GroqService _groqService = GroqService();
  final AIUsageService _aiUsageService = AIUsageService();
  final SettingsService _settingsService = SettingsService();
  final SessionManager _sessionManager = SessionManager();
  final BusinessIntelligenceService _biService = BusinessIntelligenceService();

  /// Sends a user query to the AI Advisor and returns the result.
  ///
  /// [conversationHistory] provides multi-turn context (previous Q&A pairs).
  /// Fresh database data is always fetched for each query — old conversation
  /// never overrides fresh results.
  Future<AIAdvisorResult> query(
    String userQuery, {
    List<ConversationMessage> conversationHistory = const [],
  }) async {
    // 1. Permission check — Owner only.
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

    // 5. Detect the user's analytical intent.
    final detectedIntent = _biService.detectIntent(userQuery);

    // 6. Gather ONLY the relevant business facts.
    final facts = await _biService.gatherFacts(detectedIntent);

    // 7. Build the system prompt with facts as context.
    final systemPrompt = _buildSystemPrompt(facts);

    // 8. Build the conversation messages for Groq.
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

    // 9. Call Groq.
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

    // 10. Record usage (only after a successful API response).
    final recorded =
        await _aiUsageService.recordQuery(userQuery, groqResult.content);

    if (!recorded) {
      // The limit was reached between our check and the recording (concurrent
      // request bypassed). The API call already succeeded, so we return the
      // content but warn about the limit.
      return AIAdvisorResult(
        success: true,
        content: groqResult.content,
      );
    }

    return AIAdvisorResult(success: true, content: groqResult.content);
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

  /// Builds the centralized system prompt with business facts as context.
  ///
  /// The system prompt enforces:
  /// - Facts vs Insights vs Recommendations structure
  /// - Never inventing numbers
  /// - Philippine peso formatting
  /// - No exposure of sensitive data
  /// - Clear distinction between database facts and general advice
  String _buildSystemPrompt(BusinessFacts facts) {
    return '''You are the Pinoy POS AI Business Advisor.

You help the business owner understand their sales, products, inventory, and business performance.

YOUR ROLE:
- Analyze the supplied business data
- Explain what happened and why it matters
- Give practical, actionable recommendations
- Communicate in a clear, direct, business-focused tone

CRITICAL RULES:
1. Use ONLY the supplied Pinoy POS database analysis as the source for numerical business facts.
2. Never invent sales totals, product quantities, stock levels, dates, or trends.
3. If the supplied data is insufficient or empty, say what information is missing. Do not pretend to have data you were not given.
4. Clearly distinguish between:
   - FACTS: numbers and statements derived directly from the database data provided
   - INSIGHTS: your interpretation of those facts
   - RECOMMENDATIONS: your suggestions for what to do next
5. Do not claim to have direct unrestricted access to the database.
6. Do not expose passwords, PINs, API keys, or sensitive configuration.
7. Use Philippine peso (PHP) formatting for all monetary values.
8. When comparing periods, clearly state which periods you are comparing.
9. Be concise and practical. Do not overload the owner with unnecessary technical SQL details.
10. If the user asks something outside the scope of the supplied data, you may provide general advice but must clearly state that the advice is general and not based on current business data.
11. Do not claim to calculate profit, profit margin, expenses, or customer demographics unless those data points are explicitly provided in the context.

RESPONSE FORMAT:
Structure your response with clear sections:

BUSINESS INSIGHT
A one or two sentence summary of the most important finding.

WHAT I FOUND
Bullet points of the key facts from the database.

RECOMMENDATION
One or two practical suggestions based on the facts above.

Use only the sections that are relevant to the question. If the data is empty, explain what that means.

AUTHORIZED BUSINESS CONTEXT:
${facts.context}

Generate a helpful answer based ONLY on the information above.''';
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
