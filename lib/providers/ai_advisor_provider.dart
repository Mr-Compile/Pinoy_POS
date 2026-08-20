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
class AIAdvisorChatState {
  final List<AIChatMessage> messages;
  final bool isSending;
  final AIConfigStatus configStatus;
  final int remainingQueries;
  final bool isPanelOpen;

  AIAdvisorChatState({
    this.messages = const [],
    this.isSending = false,
    this.configStatus = AIConfigStatus.checking,
    this.remainingQueries = AppConstants.maxDailyAIQueries,
    this.isPanelOpen = false,
  });

  AIAdvisorChatState copyWith({
    List<AIChatMessage>? messages,
    bool? isSending,
    AIConfigStatus? configStatus,
    int? remainingQueries,
    bool? isPanelOpen,
  }) {
    return AIAdvisorChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      configStatus: configStatus ?? this.configStatus,
      remainingQueries: remainingQueries ?? this.remainingQueries,
      isPanelOpen: isPanelOpen ?? this.isPanelOpen,
    );
  }
}

/// StateNotifier that manages the AI Advisor chat experience.
///
/// Responsibilities:
/// - Check AI configuration status before allowing queries.
/// - Enforce the 10/day limit (service is authoritative; this is UX state).
/// - Send queries through [AIAdvisorService] and append responses to the
///   conversation.
/// - Track panel open/close state for the floating chat head.
///
/// RBAC: The underlying [AIAdvisorService] enforces `view_ai_advisor`
/// (Owner-only) at the service layer. This notifier also checks the
/// permission before any operation to fail fast.
class AIAdvisorChatNotifier extends StateNotifier<AIAdvisorChatState> {
  final Ref _ref;

  AIAdvisorChatNotifier(this._ref) : super(AIAdvisorChatState());

  /// Checks the AI configuration status and remaining query count.
  /// Called when the chat panel is opened.
  Future<void> checkConfig() async {
    final authNotifier = _ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_ai_advisor')) {
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
      return;
    }

    state = state.copyWith(configStatus: AIConfigStatus.checking);

    try {
      final settingsService = _ref.read(settingsServiceProvider);
      final aiUsageService = _ref.read(aiUsageServiceProvider);

      final isConfigured = await settingsService.isGroqConfigured();
      final used = await aiUsageService.getTodayUsageCount();

      final remaining =
          (AppConstants.maxDailyAIQueries - used).clamp(0, AppConstants.maxDailyAIQueries);

      if (!isConfigured) {
        state = state.copyWith(
          configStatus: AIConfigStatus.notConfigured,
          remainingQueries: remaining,
        );
      } else {
        state = state.copyWith(
          configStatus: AIConfigStatus.active,
          remainingQueries: remaining,
        );
      }
    } catch (_) {
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
    }
  }

  /// Sends a user query to the AI Advisor and appends the response.
  Future<void> sendQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final authNotifier = _ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_ai_advisor')) {
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

    if (state.remainingQueries <= 0) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          AIChatMessage(
            text:
                'You have used all ${AppConstants.maxDailyAIQueries} AI queries for today. Please try again tomorrow.',
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
      final result = await aiAdvisorService.query(q);

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
              (state.remainingQueries - 1).clamp(0, AppConstants.maxDailyAIQueries),
        );
      } else {
        // Determine config status from result.
        AIConfigStatus newStatus = state.configStatus;
        if (result.isNotConfigured) {
          newStatus = AIConfigStatus.notConfigured;
        } else if (result.isAuthError) {
          newStatus = AIConfigStatus.invalid;
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
    } catch (_) {
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
}

final aiAdvisorChatProvider =
    StateNotifierProvider<AIAdvisorChatNotifier, AIAdvisorChatState>((ref) {
  return AIAdvisorChatNotifier(ref);
});
