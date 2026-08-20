import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/core/ai_role_config.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';

/// Floating, Messenger-style AI chat panel.
///
/// Opens as an overlay on top of the current screen (not a full route).
/// On mobile it's a bottom-aligned sheet; on tablet/desktop it's a
/// floating panel positioned near the chat head.
///
/// Features:
/// - Modern Material 3 design with dynamic accent color
/// - Clear visual hierarchy: header, conversation, input
/// - User vs AI message bubbles with distinct alignment
/// - Minimize (back to chat head) and close buttons
/// - Config status warning when AI is not ready
/// - Remaining query count badge
/// - Smooth scrolling conversation area
/// - Large touch targets
class AIChatPanel extends ConsumerStatefulWidget {
  final VoidCallback? onMinimize;

  const AIChatPanel({super.key, this.onMinimize});

  @override
  ConsumerState<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends ConsumerState<AIChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiAdvisorChatProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final isTablet = mq.size.width >= 600;

    _scrollToBottom();

    if (isTablet) {
      return _buildFloatingPanel(context, theme, cs, chatState);
    }
    return _buildBottomSheet(context, theme, cs, chatState);
  }

  // ── Tablet/Desktop: floating panel ──────────────────────────────────

  Widget _buildFloatingPanel(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AIAdvisorChatState chatState,
  ) {
    final mq = MediaQuery.of(context);
    final panelWidth = (mq.size.width * 0.35).clamp(320.0, 440.0);
    final panelHeight = (mq.size.height * 0.6).clamp(400.0, 600.0);
    final safePadding = mq.padding;

    return Positioned(
      right: safePadding.right + Spacing.md,
      bottom: safePadding.bottom + Spacing.md,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: cs.surface,
        child: Container(
          width: panelWidth,
          height: panelHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: cs.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildPanelContent(context, theme, cs, chatState),
        ),
      ),
    );
  }

  // ── Mobile: bottom-aligned sheet ────────────────────────────────────

  Widget _buildBottomSheet(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AIAdvisorChatState chatState,
  ) {
    final mq = MediaQuery.of(context);
    final safePadding = mq.padding;
    final panelHeight = mq.size.height * 0.7;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: cs.surface,
        child: Container(
          height: panelHeight,
          padding: EdgeInsets.only(bottom: safePadding.bottom),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            color: cs.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildPanelContent(context, theme, cs, chatState),
        ),
      ),
    );
  }

  // ── Shared panel content ────────────────────────────────────────────

  Widget _buildPanelContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AIAdvisorChatState chatState,
  ) {
    return Column(
      children: [
        _buildHeader(context, cs, chatState),
        if (chatState.configStatus != AIConfigStatus.active &&
            chatState.configStatus != AIConfigStatus.checking)
          _buildConfigWarning(context, cs, chatState.configStatus),
        Expanded(child: _buildConversation(context, theme, cs, chatState)),
        _buildInputBar(context, cs, chatState),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, AIAdvisorChatState chatState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primary,
            child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 20),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI Business Advisor',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                ),
                Text(
                  '${chatState.remainingQueries} of ${AppConstants.maxDailyAIQueries} queries left today',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                ),
              ],
            ),
          ),
          // Minimize button
          IconButton(
            icon: const Icon(Icons.remove),
            iconSize: 20,
            tooltip: 'Minimize',
            onPressed: () {
              ref.read(aiAdvisorChatProvider.notifier).minimizePanel();
              widget.onMinimize?.call();
            },
          ),
          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            tooltip: 'Close',
            onPressed: () {
              ref.read(aiAdvisorChatProvider.notifier).closePanel();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfigWarning(BuildContext context, ColorScheme cs, AIConfigStatus status) {
    final isNotConfigured = status == AIConfigStatus.notConfigured;
    final isInvalid = status == AIConfigStatus.invalid;

    final warningColor = isInvalid ? cs.error : (isNotConfigured ? Colors.orange : cs.error);
    final icon = isNotConfigured ? Icons.key_off : (isInvalid ? Icons.error_outline : Icons.warning_amber);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      color: warningColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon, color: warningColor, size: 20),
          const SizedBox(width: Spacing.sm),
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

  Widget _buildConversation(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AIAdvisorChatState chatState,
  ) {
    if (chatState.messages.isEmpty) {
      return _buildEmptyConversation(context, cs);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      itemCount: chatState.messages.length + (chatState.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == chatState.messages.length && chatState.isSending) {
          return _buildTypingIndicator(cs);
        }
        final msg = chatState.messages[index];
        return _buildMessageBubble(context, theme, cs, msg);
      },
    );
  }

  Widget _buildEmptyConversation(BuildContext context, ColorScheme cs) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final role = user?.role ?? UserRole.staff;
    final roleConfig = AIRoleConfig(role);
    final userName = user?.fullName ?? 'there';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.auto_awesome, size: 40,
                    color: cs.primary.withValues(alpha: 0.5)),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Hello, $userName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'I\'m your Pinoy POS AI Advisor.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  roleConfig.welcomeMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),
          // FAQ section
          Text(
            'Frequently Asked Questions',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: roleConfig.faqQuestions
                .map((q) => _buildSuggestionChip(cs, q, q))
                .toList(),
          ),
          const SizedBox(height: Spacing.lg),
          // Suggested questions section
          Text(
            'Suggested Questions',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: roleConfig.suggestedQuestions
                .map((q) => _buildSuggestionChip(cs, q, q))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(ColorScheme cs, String label, String query) {
    return ActionChip(
      label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      avatar: Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
      onPressed: () {
        ref.read(aiAdvisorChatProvider.notifier).sendQuery(query);
        _scrollToBottom();
      },
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    AIChatMessage msg,
  ) {
    final isUser = msg.isUser;
    final isError = msg.isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primary,
              child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 16),
            ),
            const SizedBox(width: Spacing.xs),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
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
              child: SelectableText(
                msg.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isError
                      ? cs.onErrorContainer
                      : isUser
                          ? cs.onPrimary
                          : cs.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
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
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
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

  Widget _buildInputBar(BuildContext context, ColorScheme cs, AIAdvisorChatState chatState) {
    final canSend = !chatState.isSending &&
        chatState.configStatus == AIConfigStatus.active &&
        chatState.remainingQueries > 0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
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
                  hintText: canSend ? 'Ask about your business...' : 'AI unavailable',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
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
