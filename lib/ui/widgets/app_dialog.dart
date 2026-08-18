import 'package:flutter/material.dart';
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
    }
  }

  Color iconColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (this) {
      case AppDialogType.success:
        return Colors.green;
      case AppDialogType.error:
        return cs.error;
      case AppDialogType.warning:
        return Colors.orange;
      case AppDialogType.info:
        return cs.primary;
      case AppDialogType.restriction:
        return Colors.orange;
      case AppDialogType.confirmation:
        return Colors.orange;
      case AppDialogType.offline:
        return cs.primary;
      case AppDialogType.loading:
        return cs.primary;
    }
  }
}

class AppDialogAction {
  final String label;
  final VoidCallback? onPressed;
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

    return Dialog(
      backgroundColor: cs.surface,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxDialogWidth),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
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
                _buildActions(context),
              ],
            ],
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
      child: Icon(
        type.icon,
        size: 48,
        color: type.iconColor(context),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
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

  Widget _buildActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions.asMap().entries.map((entry) {
        final i = entry.key;
        final action = entry.value;
        final isLast = i == actions.length - 1;

        return Padding(
          padding: EdgeInsets.only(left: isLast ? 0 : Spacing.sm),
          child: action.isPrimary
              ? FilledButton(
                  onPressed: action.onPressed,
                  style: action.isDestructive
                      ? FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        )
                      : null,
                  child: Text(action.label),
                )
              : TextButton(
                  onPressed: action.onPressed,
                  style: action.isDestructive
                      ? TextButton.styleFrom(foregroundColor: cs.error)
                      : null,
                  child: Text(action.label),
                ),
        );
      }).toList(),
    );
  }
}
