import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/services/ai_navigation_resolver.dart';

/// Renders the content of an assistant [AIChatMessage].
///
/// Plain text is shown as [SelectableText]. When the message carries a
/// structured [AIResponse], this widget renders the message, numbered
/// instructions, clickable navigation actions, and follow-up suggestions.
class AIAssistantMessage extends ConsumerWidget {
  final AIChatMessage message;

  const AIAssistantMessage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isError = message.isError;
    final isUser = message.isUser;
    final textColor = isError
        ? cs.onErrorContainer
        : isUser
            ? cs.onPrimary
            : cs.onSurface;

    if (!message.isStructured) {
      return SelectableText(
        message.text,
        style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      );
    }

    final response = message.response!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          response.message,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
        ),
        if (response.instructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InstructionsList(instructions: response.instructions),
        ],
        if (response.actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ActionList(actions: response.actions),
        ],
        if (response.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SuggestionChips(suggestions: response.suggestions),
        ],
      ],
    );
  }
}

class _InstructionsList extends StatelessWidget {
  final List<AIInstruction> instructions;

  const _InstructionsList({required this.instructions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: instructions.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final step = entry.value;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: AppTypography.labelMedium(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ActionList extends ConsumerWidget {
  final List<AIAction> actions;

  const _ActionList({required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);
    final role = SessionManager().currentUser?.role;
    final currentDestinationId = ref.read(currentRouteProvider);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((action) {
        final allowed = AINavigationResolver.canExecute(
          action: action,
          role: role,
          hasPermission: authNotifier.hasPermission,
          currentDestinationId: currentDestinationId,
        );

        final isExternal = action.type == AIActionType.externalLink;
        final icon = isExternal ? Icons.open_in_new : Icons.arrow_forward;

        return ActionChip.elevated(
          avatar: Icon(icon, size: 18, color: cs.onPrimaryContainer),
          label: Text(action.label),
          backgroundColor: isExternal ? cs.surfaceContainerHighest : cs.primaryContainer,
          side: isExternal ? BorderSide(color: cs.outline) : BorderSide.none,
          onPressed: allowed
              ? () => _onActionTap(context, ref, action)
              : null,
        );
      }).toList(),
    );
  }

  Future<void> _onActionTap(BuildContext context, WidgetRef ref, AIAction action) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    final role = SessionManager().currentUser?.role;
    final currentDestinationId = ref.read(currentRouteProvider);

    await AINavigationResolver.execute(
      context,
      action: action,
      role: role,
      hasPermission: authNotifier.hasPermission,
      currentDestinationId: currentDestinationId,
    );
  }
}

class _SuggestionChips extends ConsumerWidget {
  final List<String> suggestions;

  const _SuggestionChips({required this.suggestions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: suggestions.map((suggestion) {
        return ActionChip(
          avatar: Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
          label: Text(suggestion),
          onPressed: () {
            ref.read(aiAdvisorChatProvider.notifier).sendQuery(suggestion);
          },
        );
      }).toList(),
    );
  }
}
