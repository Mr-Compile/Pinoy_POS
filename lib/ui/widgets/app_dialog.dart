import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

enum AppDialogType {
  success,
  error,
  warning,
  info,
  restriction,
  confirmation,
  offline,
  loading,
  validation,
}

extension AppDialogTypeX on AppDialogType {
  IconData get icon {
    switch (this) {
      case AppDialogType.success:
        return Icons.check_circle;
      case AppDialogType.error:
        return Icons.error;
      case AppDialogType.warning:
        return Icons.warning;
      case AppDialogType.info:
        return Icons.info;
      case AppDialogType.restriction:
        return Icons.lock;
      case AppDialogType.confirmation:
        return Icons.help;
      case AppDialogType.offline:
        return Icons.cloud_off;
      case AppDialogType.loading:
        return Icons.hourglass_empty;
      case AppDialogType.validation:
        return Icons.task_alt;
    }
  }

  Color iconColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (this) {
      case AppDialogType.success:
        return cs.tertiary;
      case AppDialogType.error:
        return cs.error;
      case AppDialogType.warning:
        return cs.secondary;
      case AppDialogType.info:
        return cs.primary;
      case AppDialogType.restriction:
        return cs.secondary;
      case AppDialogType.confirmation:
        return cs.secondary;
      case AppDialogType.offline:
        return cs.primary;
      case AppDialogType.loading:
        return cs.primary;
      case AppDialogType.validation:
        return cs.tertiary;
    }
  }

  Color iconBgColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (this) {
      case AppDialogType.success:
        return cs.tertiaryContainer;
      case AppDialogType.error:
        return cs.errorContainer;
      case AppDialogType.warning:
        return cs.secondaryContainer;
      case AppDialogType.info:
        return cs.primaryContainer;
      case AppDialogType.restriction:
        return cs.secondaryContainer;
      case AppDialogType.confirmation:
        return cs.secondaryContainer;
      case AppDialogType.offline:
        return cs.primaryContainer;
      case AppDialogType.loading:
        return cs.primaryContainer;
      case AppDialogType.validation:
        return cs.tertiaryContainer;
    }
  }

  String get semanticLabel {
    switch (this) {
      case AppDialogType.success:
        return 'Success';
      case AppDialogType.error:
        return 'Error';
      case AppDialogType.warning:
        return 'Warning';
      case AppDialogType.info:
        return 'Information';
      case AppDialogType.restriction:
        return 'Access restricted';
      case AppDialogType.confirmation:
        return 'Confirmation required';
      case AppDialogType.offline:
        return 'No internet connection';
      case AppDialogType.loading:
        return 'Loading';
      case AppDialogType.validation:
        return 'Validation error';
    }
  }
}

/// Action displayed inside an [AppDialog].
///
/// The [onPressed] callback receives the dialog's own [BuildContext] so
/// dismissal can always target the same [Navigator] that owns the dialog,
/// regardless of which caller opened it.
class AppDialogAction {
  final String label;
  final void Function(BuildContext dialogContext)? onPressed;
  final bool isPrimary;
  final bool isDestructive;

  const AppDialogAction({
    required this.label,
    this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
  });
}

class AppDialog extends StatelessWidget {
  final AppDialogType type;
  final String title;
  final String? message;
  final String? details;
  final List<AppDialogAction> actions;
  final bool dismissible;

  const AppDialog({
    super.key,
    required this.type,
    required this.title,
    this.message,
    this.details,
    this.actions = const [],
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final maxDialogWidth = isTablet ? 480.0 : double.infinity;

    return Semantics(
      label: type.semanticLabel,
      container: true,
      child: Dialog(
        backgroundColor: cs.surface,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxDialogWidth),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xxl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildIcon(context),
                  const SizedBox(height: Spacing.lg),
                  _buildTitle(context),
                  if (message != null) ...[
                    const SizedBox(height: Spacing.sm),
                    _buildMessage(context),
                  ],
                  if (details != null) ...[
                    const SizedBox(height: Spacing.sm),
                    _buildDetails(context),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: Spacing.xxl),
                    _buildActions(context, isTablet),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    if (type == AppDialogType.loading) {
      return Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: type.iconBgColor(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          type.icon,
          size: 32,
          color: type.iconColor(context),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      title,
      style: AppTypography.headlineSmallSemibold(context),
    );
  }

  Widget _buildMessage(BuildContext context) {
    return Text(
      message!,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        details!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isTablet) {
    final cs = Theme.of(context).colorScheme;

    Widget buildAction(AppDialogAction action) {
      final handler = action.onPressed == null
          ? null
          : () => action.onPressed!(context);

      return action.isPrimary
          ? FilledButton(
              onPressed: handler,
              style: action.isDestructive
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                      minimumSize: const Size(88, 48),
                    )
                  : FilledButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
              child: Text(action.label),
            )
          : TextButton(
              onPressed: handler,
              style: action.isDestructive
                  ? TextButton.styleFrom(
                      foregroundColor: cs.error,
                      minimumSize: const Size(88, 48),
                    )
                  : TextButton.styleFrom(
                      minimumSize: const Size(88, 48),
                    ),
              child: Text(action.label),
            );
    }

    if (actions.length > 2 || !isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: actions.asMap().entries.map((entry) {
          final i = entry.key;
          final action = entry.value;
          final isFirst = i == 0;

          return Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : Spacing.sm),
            child: buildAction(action),
          );
        }).toList(),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions.asMap().entries.map((entry) {
        final i = entry.key;
        final action = entry.value;
        final isLast = i == actions.length - 1;

        return Padding(
          padding: EdgeInsets.only(left: isLast ? 0 : Spacing.sm),
          child: buildAction(action),
        );
      }).toList(),
    );
  }
}
