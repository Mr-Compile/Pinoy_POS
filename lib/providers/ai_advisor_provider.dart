import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';

/// A single message in the AI Advisor conversation.
class AIChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  AIChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

/// State for the AI Advisor chat experience.
///
/// State is separated into independent concerns so one failing operation
/// never blocks the rest of the UI:
/// - [configStatus]: AI configuration state (active/notConfigured/invalid/...)
/// - [remainingQueries]: daily limit tracking
/// - [messages]: conversation history
/// - [isSending]: request processing state
/// - [isPanelOpen]: panel visibility
/// - [suggestions]: contextual suggested questions
class AIAdvisorChatState {
  final List<AIChatMessage> messages;
  final bool isSending;
  final AIConfigStatus configStatus;
  final int remainingQueries;
  final bool isPanelOpen;
  final List<String> suggestions;
  final String? modelName;

  AIAdvisorChatState({
    this.messages = const [],
    this.isSending = false,
    this.configStatus = AIConfigStatus.checking,
    this.remainingQueries = AppConstants.maxDailyAIQueries,
    this.isPanelOpen = false,
    this.suggestions = const [],
    this.modelName,
  });

  AIAdvisorChatState copyWith({
    List<AIChatMessage>? messages,
    bool? isSending,
    AIConfigStatus? configStatus,
    int? remainingQueries,
    bool? isPanelOpen,
    List<String>? suggestions,
    String? modelName,
  }) {
    return AIAdvisorChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      configStatus: configStatus ?? this.configStatus,
      remainingQueries: remainingQueries ?? this.remainingQueries,
      isPanelOpen: isPanelOpen ?? this.isPanelOpen,
      suggestions: suggestions ?? this.suggestions,
      modelName: modelName ?? this.modelName,
    );
  }
}

/// StateNotifier that manages the AI Advisor chat experience.
///
/// RBAC: The underlying [AIAdvisorService] enforces `use_ai_advisor`
/// (Owner only) at the service layer. This notifier also checks the
/// permission before any operation to fail fast.
///
/// Duplicate request prevention: [isSending] is checked before sending.
/// The notifier does not allow concurrent send operations.
///
/// No API calls from build(): All async operations are triggered by
/// explicit user actions (openPanel, sendQuery) or lifecycle hooks
/// (initState in the screen), never during provider construction or
/// widget build.
class AIAdvisorChatNotifier extends StateNotifier<AIAdvisorChatState> {
  final Ref _ref;

  AIAdvisorChatNotifier(this._ref) : super(AIAdvisorChatState());

  /// Checks the AI configuration status, remaining query count, and
  /// loads contextual suggestions. Called when the chat screen/panel opens.
  Future<void> checkConfig() async {
    final authNotifier = _ref.read(authStateProvider.notifier);

    // Owner-only check. Admin and Staff don't have use_ai_advisor.
    if (!authNotifier.hasPermission('use_ai_advisor')) {
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
      return;
    }

    state = state.copyWith(configStatus: AIConfigStatus.checking);

    try {
      final settingsService = _ref.read(settingsServiceProvider);
      final aiUsageService = _ref.read(aiUsageServiceProvider);

      final isConfigured = await settingsService.isGroqConfigured();
      final used = await aiUsageService.getTodayUsageCount();
      final model = await settingsService.getGroqModel();

      final remaining =
          (AppConstants.maxDailyAIQueries - used)
              .clamp(0, AppConstants.maxDailyAIQueries);

      if (!isConfigured) {
        state = state.copyWith(
          configStatus: AIConfigStatus.notConfigured,
          remainingQueries: remaining,
          modelName: model,
        );
      } else {
        state = state.copyWith(
          configStatus: AIConfigStatus.active,
          remainingQueries: remaining,
          modelName: model,
        );
        // Load contextual suggestions in the background.
        _loadSuggestions();
      }
    } catch (e, st) {
      _log('checkConfig failed', e, st);
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
    }
  }

  /// Loads contextual suggestions based on real database conditions.
  Future<void> _loadSuggestions() async {
    try {
      final aiAdvisorService = _ref.read(aiAdvisorServiceProvider);
      final suggestions =
          await aiAdvisorService.getContextualSuggestions();
      if (mounted) {
        state = state.copyWith(suggestions: suggestions);
      }
    } catch (e, st) {
      _log('loadSuggestions failed', e, st);
    }
  }

  /// Sends a user query to the AI Advisor and appends the response.
  ///
  /// Duplicate request prevention: if [isSending] is already true, the
  /// call is ignored. This prevents concurrent API requests from
  /// bypassing the daily limit or creating duplicate messages.
  Future<void> sendQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    // Prevent duplicate/concurrent send requests.
    if (state.isSending) return;

    final authNotifier = _ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('use_ai_advisor')) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          AIChatMessage(
            text: 'You do not have permission to use the AI Advisor.',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ),
        ],
      );
      return;
    }

    // Check config status.
    if (state.configStatus != AIConfigStatus.active) {
      await checkConfig();
      if (state.configStatus != AIConfigStatus.active) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AIChatMessage(
              text: state.configStatus.label,
              isUser: false,
              timestamp: DateTime.now(),
              isError: true,
            ),
          ],
        );
        return;
      }
    }

    // Check daily limit.
    if (state.remainingQueries <= 0) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          AIChatMessage(
            text:
                'You have used all ${AppConstants.maxDailyAIQueries} AI queries for today. Your limit will reset tomorrow.',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ),
        ],
      );
      return;
    }

    // Append user message and set sending state.
    state = state.copyWith(
      messages: [
        ...state.messages,
        AIChatMessage(text: q, isUser: true, timestamp: DateTime.now()),
      ],
      isSending: true,
    );

    try {
      final aiAdvisorService = _ref.read(aiAdvisorServiceProvider);

      // Build conversation history from existing messages (last 6).
      final history = <ConversationMessage>[];
      final recentMessages = state.messages.length > 6
          ? state.messages.sublist(state.messages.length - 6)
          : state.messages;
      for (final msg in recentMessages) {
        if (!msg.isError) {
          history.add(ConversationMessage(
            role: msg.isUser ? 'user' : 'assistant',
            content: msg.text,
          ));
        }
      }
      // Remove the last entry (it's the current query, which is passed
      // separately to the service).
      if (history.isNotEmpty) history.removeLast();

      final result = await aiAdvisorService.query(q, conversationHistory: history);

      if (!mounted) return;

      if (result.success) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AIChatMessage(
              text: result.content ?? 'No response from the advisor.',
              isUser: false,
              timestamp: DateTime.now(),
            ),
          ],
          isSending: false,
          remainingQueries:
              (state.remainingQueries - 1)
                  .clamp(0, AppConstants.maxDailyAIQueries),
        );
      } else {
        // Determine config status from result.
        AIConfigStatus newStatus = state.configStatus;
        if (result.isNotConfigured) {
          newStatus = AIConfigStatus.notConfigured;
        } else if (result.isAuthError) {
          newStatus = AIConfigStatus.invalid;
        } else if (result.isModelUnavailable || result.isModelError) {
          newStatus = AIConfigStatus.unavailable;
        }

        state = state.copyWith(
          messages: [
            ...state.messages,
            AIChatMessage(
              text: result.errorMessage ??
                  'The advisor could not complete the analysis.',
              isUser: false,
              timestamp: DateTime.now(),
              isError: true,
            ),
          ],
          isSending: false,
          configStatus: newStatus,
        );
      }
    } catch (e, st) {
      _log('sendQuery failed', e, st);
      if (mounted) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            AIChatMessage(
              text:
                  'The advisor could not complete the analysis. Please try again.',
              isUser: false,
              timestamp: DateTime.now(),
              isError: true,
            ),
          ],
          isSending: false,
        );
      }
    }
  }

  /// Opens the chat panel and triggers config check.
  void openPanel() {
    state = state.copyWith(isPanelOpen: true);
    checkConfig();
  }

  /// Minimizes the chat panel back to the floating chat head.
  void minimizePanel() {
    state = state.copyWith(isPanelOpen: false);
  }

  /// Closes the chat panel (does not destroy the feature).
  void closePanel() {
    state = state.copyWith(isPanelOpen: false);
  }

  /// Clears the conversation history.
  void clearConversation() {
    state = state.copyWith(messages: []);
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[AIAdvisorChatNotifier] $message: $error\n$stackTrace');
    }
  }
}

final aiAdvisorChatProvider =
    StateNotifierProvider<AIAdvisorChatNotifier, AIAdvisorChatState>((ref) {
  return AIAdvisorChatNotifier(ref);
});
