import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

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

  Color iconColor(Brightness brightness) {
    switch (this) {
      case AppDialogType.success:
        return AppSemanticColors.resolve(AppSemanticColors.success, brightness);
      case AppDialogType.error:
        return AppSemanticColors.resolve(AppSemanticColors.error, brightness);
      case AppDialogType.warning:
        return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
      case AppDialogType.info:
        return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
      case AppDialogType.restriction:
        return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
      case AppDialogType.confirmation:
        return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
      case AppDialogType.offline:
        return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
      case AppDialogType.loading:
        return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
      case AppDialogType.validation:
        return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    }
  }

  Color iconBgColor(Brightness brightness) {
    switch (this) {
      case AppDialogType.success:
        return AppSemanticColors.resolve(
            AppSemanticColors.successContainer, brightness);
      case AppDialogType.error:
        return AppSemanticColors.resolve(
            AppSemanticColors.errorContainer, brightness);
      case AppDialogType.warning:
        return AppSemanticColors.resolve(
            AppSemanticColors.warningContainer, brightness);
      case AppDialogType.info:
        return AppSemanticColors.resolve(
            AppSemanticColors.infoContainer, brightness);
      case AppDialogType.restriction:
        return AppSemanticColors.resolve(
            AppSemanticColors.warningContainer, brightness);
      case AppDialogType.confirmation:
        return AppSemanticColors.resolve(
            AppSemanticColors.infoContainer, brightness);
      case AppDialogType.offline:
        return AppSemanticColors.resolve(
            AppSemanticColors.infoContainer, brightness);
      case AppDialogType.loading:
        return AppSemanticColors.resolve(
            AppSemanticColors.infoContainer, brightness);
      case AppDialogType.validation:
        return AppSemanticColors.resolve(
            AppSemanticColors.warningContainer, brightness);
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
  final bool isLoading;

  const AppDialogAction({
    required this.label,
    this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isLoading = false,
  });
}

class AppDialog extends StatelessWidget {
  final AppDialogType type;
  final String title;
  final String? message;
  final String? details;
  final List<AppDialogAction> actions;
  final bool dismissible;
  final bool showIcon;
  final Widget? child;

  const AppDialog({
    super.key,
    required this.type,
    required this.title,
    this.message,
    this.details,
    this.actions = const [],
    this.dismissible = true,
    this.showIcon = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = child == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutClassFor(constraints.maxWidth);
        final (horizontalInset, maxDialogWidth) = switch (layout) {
          LayoutClass.compact => (32.0, min(360.0, constraints.maxWidth - 64.0)),
          LayoutClass.medium => (24.0, min(480.0, constraints.maxWidth - 48.0)),
          LayoutClass.expanded => (24.0, min(560.0, constraints.maxWidth - 48.0)),
        };
        // Never let the max fall below the min width to keep BoxConstraints
        // valid, even on very small/foldable windows.
        final effectiveMax = max(280.0, maxDialogWidth);

        return Semantics(
          label: type.semanticLabel,
          container: true,
          child: Dialog(
            alignment: Alignment.center,
            insetPadding: EdgeInsets.symmetric(
              horizontal: horizontalInset,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 280,
                maxWidth: effectiveMax,
              ),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xxl),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showIcon) ...[
                        _buildIcon(context, isAlert),
                        const SizedBox(height: Spacing.lg),
                      ],
                      _buildTitle(context, isAlert),
                      if (message != null) ...[
                        const SizedBox(height: Spacing.sm),
                        _buildMessage(context, isAlert),
                      ],
                      if (details != null) ...[
                        const SizedBox(height: Spacing.sm),
                        _buildDetails(context),
                      ],
                      if (child != null) ...[
                        const SizedBox(height: Spacing.md),
                        child!,
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xxl),
                        _buildActions(context, layout.isAtLeastMedium),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(BuildContext context, bool centered) {
    final brightness = Theme.of(context).brightness;
    if (type == AppDialogType.loading) {
      return Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppSemanticColors.resolve(AppSemanticColors.info, brightness),
          ),
        ),
      );
    }

    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: type.iconBgColor(brightness),
          shape: BoxShape.circle,
        ),
        child: Icon(
          type.icon,
          size: 32,
          color: type.iconColor(brightness),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool centered) {
    return Text(
      title,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: AppTypography.headlineSmallSemibold(context),
    );
  }

  Widget _buildMessage(BuildContext context, bool centered) {
    return Text(
      message!,
      softWrap: true,
      textAlign: centered ? TextAlign.center : TextAlign.start,
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
        softWrap: true,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isTablet) {
    final stackVertically = actions.length > 2 || !isTablet;

    Widget buildAction(AppDialogAction action, {required bool fullWidth}) {
      final handler = action.onPressed == null || action.isLoading
          ? null
          : () => action.onPressed!(context);

      if (action.isDestructive) {
        return AppButton.destructive(
          onPressed: handler,
          label: action.label,
          isLoading: action.isLoading,
          fullWidth: fullWidth,
        );
      }

      if (action.isPrimary) {
        return AppButton.filled(
          onPressed: handler,
          label: action.label,
          isLoading: action.isLoading,
          fullWidth: fullWidth,
        );
      }

      return AppButton.outlined(
        onPressed: handler,
        label: action.label,
        color: AppButtonColor.neutral,
        isLoading: action.isLoading,
        fullWidth: fullWidth,
      );
    }

    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: actions.asMap().entries.map((entry) {
          final i = entry.key;
          final action = entry.value;
          final isFirst = i == 0;

          return Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : Spacing.sm),
            child: buildAction(action, fullWidth: true),
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
          padding: EdgeInsets.only(right: isLast ? 0 : Spacing.sm),
          child: buildAction(action, fullWidth: false),
        );
      }).toList(),
    );
  }
}
