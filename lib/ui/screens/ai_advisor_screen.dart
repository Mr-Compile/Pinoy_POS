import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/ai_role_config.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/ui/widgets/ai_assistant_message.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// Role-aware AI Advisor screen.
class AIAdvisorScreen extends ConsumerStatefulWidget {
  const AIAdvisorScreen({super.key});

  @override
  ConsumerState<AIAdvisorScreen> createState() => _AIAdvisorScreenState();
}

class _AIAdvisorScreenState extends ConsumerState<AIAdvisorScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _configChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConfig();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    await ref.read(aiAdvisorChatProvider.notifier).checkConfig();
    if (mounted) {
      setState(() => _configChecked = true);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendQuery() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    await ref.read(aiAdvisorChatProvider.notifier).sendQuery(text);
    _scrollToBottom();
  }

  Future<void> _sendSuggestion(String query) async {
    await ref.read(aiAdvisorChatProvider.notifier).sendQuery(query);
    _scrollToBottom();
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiAdvisorChatProvider);
    final role = SessionManager().currentUser?.role;
    final roleConfig = role != null ? AIRoleConfig(role) : null;

    _scrollToBottom();

    return Scaffold(
      appBar: AppHeader(
        title: roleConfig?.title ?? 'AI Advisor',
        showBackButton: true,
        actions: [
          _buildStatusChip(context, chatState),
        ],
      ),
      body: Column(
        children: [
          if (_configChecked &&
              chatState.configStatus != AIConfigStatus.active &&
              chatState.configStatus != AIConfigStatus.checking)
            _buildConfigWarning(context, chatState.configStatus),
          _buildQueryLimitBar(context, chatState),
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildWelcomeState(context, chatState)
                : _buildChatList(context, chatState),
          ),
          _buildInputBar(context, chatState),
        ],
      ),
    );
  }

  // -- Status Chip ---------------------------------------------------------

  Widget _buildStatusChip(BuildContext context, AIAdvisorChatState chatState) {
    final cs = Theme.of(context).colorScheme;
    final status = chatState.configStatus;

    final color = switch (status) {
      AIConfigStatus.active =>
        AppSemanticColors.resolve(
            AppSemanticColors.success, Theme.of(context).brightness),
      AIConfigStatus.notConfigured =>
        AppSemanticColors.resolve(
            AppSemanticColors.warning, Theme.of(context).brightness),
      AIConfigStatus.invalid ||
      AIConfigStatus.unavailable =>
        cs.error,
      AIConfigStatus.checking => cs.secondary,
    };

    final label = switch (status) {
      AIConfigStatus.active => 'Connected',
      AIConfigStatus.notConfigured => 'Not Configured',
      AIConfigStatus.invalid => 'Invalid Key',
      AIConfigStatus.unavailable => 'Offline',
      AIConfigStatus.checking => 'Checking...',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Chip(
          avatar: Icon(Icons.circle, size: 10, color: color),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  // -- Config Warning Banner -----------------------------------------------

  Widget _buildConfigWarning(BuildContext context, AIConfigStatus status) {
    final cs = Theme.of(context).colorScheme;
    final isNotConfigured = status == AIConfigStatus.notConfigured;
    final isInvalid = status == AIConfigStatus.invalid;

    final warningColor = isInvalid
        ? cs.error
        : (isNotConfigured
            ? AppSemanticColors.resolve(
                AppSemanticColors.warning, Theme.of(context).brightness)
            : cs.error);
    final icon = isNotConfigured
        ? Icons.key_off
        : (isInvalid ? Icons.error_outline : Icons.wifi_off);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: warningColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon, color: warningColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: warningColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Query Limit Bar -----------------------------------------------------

  Widget _buildQueryLimitBar(
      BuildContext context, AIAdvisorChatState chatState) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final used = chatState.dailyQuota - chatState.remainingQueries;
    final isLimitReached = chatState.remainingQueries <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'AI Queries Today',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: chatState.dailyQuota > 0
                    ? used / chatState.dailyQuota
                    : 0,
                backgroundColor: cs.surfaceContainerHighest,
                color: isLimitReached ? cs.error : cs.primary,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$used / ${chatState.dailyQuota} used',
            style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isLimitReached ? cs.error : cs.onSurface,
                ),
          ),
        ],
      ),
    );
  }

  // -- Welcome State -------------------------------------------------------

  Widget _buildWelcomeState(
      BuildContext context, AIAdvisorChatState chatState) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final role = SessionManager().currentUser?.role;
    final roleConfig = role != null ? AIRoleConfig(role) : null;

    final canChat = chatState.configStatus == AIConfigStatus.active &&
        chatState.remainingQueries > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.auto_awesome, size: 48,
                    color: cs.primary.withValues(alpha: 0.5)),
                const SizedBox(height: Spacing.sm),
                Text(
                  roleConfig?.title ?? 'AI Advisor',
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  roleConfig?.welcomeMessage ??
                      'I can help you with your business data.',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),
          if (canChat && chatState.suggestions.isNotEmpty) ...[
            Text(
              'Suggested Questions',
              style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: chatState.suggestions
                  .map((q) => _buildSuggestionChip(cs, q))
                  .toList(),
            ),
          ] else if (canChat) ...[
            Text(
              'Try asking',
              style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: (roleConfig?.suggestedQuestions ??
                  [
                    'How are my sales today?',
                    'Give me a summary.',
                  ]).map((q) => _buildSuggestionChip(cs, q)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(ColorScheme cs, String label) {
    return ActionChip(
      label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      avatar: Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
      onPressed: () => _sendSuggestion(label),
    );
  }

  // -- Chat List -----------------------------------------------------------

  Widget _buildChatList(BuildContext context, AIAdvisorChatState chatState) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      itemCount: chatState.messages.length + (chatState.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == chatState.messages.length && chatState.isSending) {
          return _buildTypingIndicator(context);
        }
        final msg = chatState.messages[index];
        return _buildMessageBubble(context, msg);
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, AIChatMessage msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isUser = msg.isUser;
    final isError = msg.isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child:
                  Icon(Icons.auto_awesome, color: cs.onPrimary, size: 16),
            ),
            const SizedBox(width: Spacing.xs),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm + 2),
              decoration: BoxDecoration(
                color: isError
                    ? cs.errorContainer
                    : isUser
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: AIAssistantMessage(message: msg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primary,
            child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 16),
          ),
          const SizedBox(width: Spacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm + 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(cs, 0),
                const SizedBox(width: 4),
                _buildDot(cs, 150),
                const SizedBox(width: 4),
                _buildDot(cs, 300),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(ColorScheme cs, int delay) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary,
            ),
          ),
        );
      },
    );
  }

  // -- Input Bar -----------------------------------------------------------

  Widget _buildInputBar(BuildContext context, AIAdvisorChatState chatState) {
    final cs = Theme.of(context).colorScheme;

    final canSend = !chatState.isSending &&
        chatState.configStatus == AIConfigStatus.active &&
        chatState.remainingQueries > 0;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: canSend,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: canSend ? (_) => _sendQuery() : null,
                decoration: InputDecoration(
                  hintText: canSend
                      ? 'Ask about your business...'
                      : 'AI unavailable',
                  hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md, vertical: Spacing.sm + 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: cs.outlineVariant, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            IconButton.filled(
              icon: chatState.isSending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimary,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
              onPressed: canSend ? _sendQuery : null,
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}

