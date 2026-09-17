import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_chat_message.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';
import 'package:pinoy_pos/services/ai_navigation_service.dart';
import 'package:pinoy_pos/services/ai_product_action_service.dart';

// AIChatMessage now lives in the data layer so it can be persisted.
// Re-exported here because several widgets historically imported it
// from this provider file.
export 'package:pinoy_pos/data/models/ai_chat_message.dart';

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

  /// The user whose conversation is currently held in [state.messages],
  /// and whether the persisted history has already been restored for
  /// that user. Guarded so a user switch can never show the previous
  /// user's conversation.
  int? _historyUserId;
  bool _historyLoaded = false;

  Future<void> checkConfig() async {
    final authNotifier = _ref.read(authStateProvider.notifier);

    if (!authNotifier.hasPermission('use_ai_advisor') &&
        !authNotifier.hasPermission('manage_ai_config')) {
      _historyUserId = null;
      _historyLoaded = false;
      state = state.copyWith(
        configStatus: AIConfigStatus.unavailable,
        messages: const [],
      );
      return;
    }

    state = state.copyWith(configStatus: AIConfigStatus.checking);

    try {
      // Restore the persisted conversation before anything else so the
      // panel opens with the previous chat visible — history is kept
      // until the user explicitly starts a new conversation.
      await _syncConversationHistory();
      if (!mounted) return;

      final settingsService = _ref.read(settingsServiceProvider);
      final aiUsageService = _ref.read(aiUsageServiceProvider);

      final isConfigured = await settingsService.isGroqConfigured();
      final remaining = await aiUsageService.getRemainingQueries();
      final dailyQuota = await aiUsageService.getDailyQuota();
      final model = await settingsService.getGroqModel();
      if (!mounted) return;

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
      if (!mounted) return;
      state = state.copyWith(configStatus: AIConfigStatus.unavailable);
    }
  }

  /// Loads the stored conversation for the current authenticated user.
  ///
  /// No-ops once the history for this user has been synced; a different
  /// authenticated user id triggers a reload so conversations are
  /// always isolated per account.
  Future<void> _syncConversationHistory() async {
    final userId = SessionManager().currentUser?.id;
    if (userId == null) return;
    if (_historyLoaded && _historyUserId == userId) return;

    try {
      final history =
          await _ref.read(aiChatHistoryServiceProvider).loadConversation();
      if (!mounted) return;
      _historyUserId = userId;
      _historyLoaded = true;
      state = state.copyWith(messages: history);
    } catch (e, st) {
      _log('loadConversation failed', e, st);
    }
  }

  /// Persists a message that was just appended to the conversation.
  /// Fire-and-forget: a persistence failure must never block the chat.
  void _persistMessage(AIChatMessage message) {
    if (!_historyLoaded) return;
    _ref
        .read(aiChatHistoryServiceProvider)
        .appendMessage(message)
        .catchError((Object e, StackTrace st) {
      _log('persistMessage failed', e, st);
    });
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

    // Make sure the stored conversation is loaded before appending —
    // locally-resolved answers (product actions, navigation) must be
    // persisted too, and they cannot be written safely until the
    // existing history is in memory.
    await _syncConversationHistory();
    if (!mounted) return;

    // Product-creation commands resolve locally — no API call, no quota.
    // This runs before navigation so "add product" phrasing is not routed
    // to the Products destination.
    final productResponse = await AIProductActionService.resolveCommand(
      q,
      hasPermission: authNotifier.hasPermission,
    );
    if (productResponse != null) {
      if (!mounted) return;
      _addUserMessage(q);
      _addBotMessage(
        text: productResponse.message,
        response: productResponse,
        followUps: productResponse.suggestions.isEmpty
            ? _buildFollowUps(q)
            : const [],
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
      if (!mounted) return;
      _addUserMessage(q);
      _addBotMessage(
        text: navigationResponse.message,
        response: navigationResponse,
        followUps: navigationResponse.suggestions.isEmpty
            ? _buildFollowUps(q)
            : const [],
      );
      return;
    }

    if (state.configStatus != AIConfigStatus.active) {
      await checkConfig();
      if (!mounted) return;
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
        final action = result.action;
        final content = result.content ?? 'No response from the advisor.';
        final message = AIChatMessage(
          text: content,
          isUser: false,
          timestamp: DateTime.now(),
          response: action == null
              ? null
              : AIResponse(message: content, actions: [action]),
          followUps: action == null ? _buildFollowUps(q) : const [],
        );
        _persistMessage(message);
        state = state.copyWith(
          messages: [...state.messages, message],
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

        final message = AIChatMessage(
          text: result.errorMessage ??
              'The advisor could not complete the analysis.',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        );
        _persistMessage(message);
        state = state.copyWith(
          messages: [...state.messages, message],
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
    final message = AIChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    _persistMessage(message);
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Builds adaptive follow-up suggestions for the user query [query].
  ///
  /// Excludes every question the user has already asked in this
  /// conversation so the chips keep evolving instead of repeating.
  List<String> _buildFollowUps(String query) {
    try {
      final asked = <String>{
        for (final m in state.messages)
          if (m.isUser) m.text,
      };
      return _ref
          .read(aiAdvisorServiceProvider)
          .getFollowUpSuggestions(query, exclude: asked);
    } catch (e, st) {
      _log('buildFollowUps failed', e, st);
      return const [];
    }
  }

  void _addBotMessage({
    required String text,
    AIResponse? response,
    bool isError = false,
    List<String> followUps = const [],
  }) {
    final message = AIChatMessage(
      text: text,
      response: response,
      isUser: false,
      timestamp: DateTime.now(),
      isError: isError,
      followUps: followUps,
    );
    _persistMessage(message);
    state = state.copyWith(
      messages: [...state.messages, message],
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

  /// Starts a new conversation: clears the in-memory messages AND the
  /// persisted history for the current user. This is the only way a
  /// conversation is removed — app restarts, panel close, and route
  /// changes all preserve it.
  Future<void> startNewConversation() async {
    try {
      await _ref.read(aiChatHistoryServiceProvider).clearConversation();
    } catch (e, st) {
      _log('clearConversation failed', e, st);
    }
    if (!mounted) return;
    state = state.copyWith(messages: []);
    _loadSuggestions();
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

