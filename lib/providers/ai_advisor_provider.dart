import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';
import 'package:pinoy_pos/services/ai_navigation_service.dart';

/// A single message in the AI Advisor conversation.
///
/// Messages can either be plain text ([text]) for conversational AI
/// responses, or a structured [AIResponse] that the app renders with
/// instructions, navigation actions, and follow-up suggestions.
class AIChatMessage {
  final String text;
  final AIResponse? response;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  AIChatMessage({
    required this.text,
    this.response,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });

  /// True when this message should be rendered as a structured card.
  bool get isStructured => response != null;
}

/// State for the AI Advisor chat experience.
class AIAdvisorChatState {
  final List<AIChatMessage> messages;
  final bool isSending;
  final AIConfigStatus configStatus;
  final int remainingQueries;
  final int dailyQuota;
  final bool isPanelOpen;
  final List<String> suggestions;
  final String? modelName;

  AIAdvisorChatState({
    this.messages = const [],
    this.isSending = false,
    this.configStatus = AIConfigStatus.checking,
    this.remainingQueries = 0,
    this.dailyQuota = 0,
    this.isPanelOpen = false,
    this.suggestions = const [],
    this.modelName,
  });

  AIAdvisorChatState copyWith({
    List<AIChatMessage>? messages,
    bool? isSending,
    AIConfigStatus? configStatus,
    int? remainingQueries,
    int? dailyQuota,
    bool? isPanelOpen,
    List<String>? suggestions,
    String? modelName,
  }) {
    return AIAdvisorChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      configStatus: configStatus ?? this.configStatus,
      remainingQueries: remainingQueries ?? this.remainingQueries,
      dailyQuota: dailyQuota ?? this.dailyQuota,
      isPanelOpen: isPanelOpen ?? this.isPanelOpen,
      suggestions: suggestions ?? this.suggestions,
      modelName: modelName ?? this.modelName,
    );
  }
}

class AIAdvisorChatNotifier extends StateNotifier<AIAdvisorChatState> {
  final Ref _ref;

  AIAdvisorChatNotifier(this._ref) : super(AIAdvisorChatState());

  Future<void> checkConfig() async {
    final authNotifier = _ref.read(authStateProvider.notifier);

    if (!authNotifier.hasPermission('use_ai_advisor') &&
        !authNotifier.hasPermission('manage_ai_config')) {
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
      return;
    }

    state = state.copyWith(configStatus: AIConfigStatus.checking);

    try {
      final settingsService = _ref.read(settingsServiceProvider);
      final aiUsageService = _ref.read(aiUsageServiceProvider);

      final isConfigured = await settingsService.isGroqConfigured();
      final remaining = await aiUsageService.getRemainingQueries();
      final dailyQuota = await aiUsageService.getDailyQuota();
      final model = await settingsService.getGroqModel();

      if (!isConfigured) {
        state = state.copyWith(
          configStatus: AIConfigStatus.notConfigured,
          remainingQueries: remaining,
          dailyQuota: dailyQuota,
          modelName: model,
        );
      } else {
        state = state.copyWith(
          configStatus: AIConfigStatus.active,
          remainingQueries: remaining,
          dailyQuota: dailyQuota,
          modelName: model,
        );
        _loadSuggestions();
      }
    } catch (e, st) {
      _log('checkConfig failed', e, st);
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final aiAdvisorService = _ref.read(aiAdvisorServiceProvider);
      final suggestions = await aiAdvisorService.getContextualSuggestions();
      if (mounted) {
        state = state.copyWith(suggestions: suggestions);
      }
    } catch (e, st) {
      _log('loadSuggestions failed', e, st);
    }
  }

  Future<void> sendQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    if (state.isSending) return;

    final authNotifier = _ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('use_ai_advisor')) {
      _addBotMessage(
        text: 'You do not have permission to use the AI Advisor.',
        isError: true,
      );
      return;
    }

    // First, try to satisfy navigation and how-to queries locally so the
    // assistant works even when offline or when the AI service is not
    // configured. The application always validates permissions.
    final currentDestinationId = _ref.read(currentRouteProvider);
    final navigationResponse = await AINavigationService.resolveNavigationResponse(
      q,
      role: SessionManager().currentUser?.role,
      hasPermission: authNotifier.hasPermission,
      currentDestinationId: currentDestinationId,
    );

    if (navigationResponse != null) {
      _addUserMessage(q);
      _addBotMessage(
        text: navigationResponse.message,
        response: navigationResponse,
      );
      return;
    }

    if (state.configStatus != AIConfigStatus.active) {
      await checkConfig();
      if (state.configStatus != AIConfigStatus.active) {
        _addBotMessage(
          text: state.configStatus.label,
          isError: true,
        );
        return;
      }
    }

    if (state.remainingQueries <= 0) {
      _addBotMessage(
        text:
            'You have used all ${state.dailyQuota} AI queries for today. Your limit will reset tomorrow.',
        isError: true,
      );
      return;
    }

    _addUserMessage(q);
    state = state.copyWith(isSending: true);

    try {
      final aiAdvisorService = _ref.read(aiAdvisorServiceProvider);

      final history = <ConversationMessage>[];
      final recentMessages = state.messages.length > 6
          ? state.messages.sublist(state.messages.length - 6)
          : state.messages;
      for (final msg in recentMessages) {
        if (!msg.isError && !msg.isStructured) {
          history.add(ConversationMessage(
            role: msg.isUser ? 'user' : 'assistant',
            content: msg.text,
          ));
        }
      }
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
              (state.remainingQueries - 1).clamp(0, AppConstants.maxDailyAIQuota),
        );
      } else {
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
        _addBotMessage(
          text:
              'The advisor could not complete the analysis. Please try again.',
          isError: true,
        );
      }
    }
  }

  void _addUserMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        AIChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  void _addBotMessage({
    required String text,
    AIResponse? response,
    bool isError = false,
  }) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        AIChatMessage(
          text: text,
          response: response,
          isUser: false,
          timestamp: DateTime.now(),
          isError: isError,
        ),
      ],
      isSending: false,
    );
  }

  void openPanel() {
    state = state.copyWith(isPanelOpen: true);
    checkConfig();
  }

  void minimizePanel() {
    state = state.copyWith(isPanelOpen: false);
  }

  void closePanel() {
    state = state.copyWith(isPanelOpen: false);
  }

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

