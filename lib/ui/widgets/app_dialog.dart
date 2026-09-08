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

class AppDialog extends StatefulWidget {
  final AppDialogType type;
  final String title;
  final String? message;
  final String? details;
  final List<AppDialogAction> actions;
  final bool dismissible;
  final bool showIcon;
  final Widget? child;
  final bool showClose;
  final void Function(BuildContext dialogContext)? onClosePressed;

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
    this.showClose = false,
    this.onClosePressed,
  });

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls the dialog body so the currently focused field stays visible when
  /// the keyboard appears or the user moves focus.
  void _onFocusChanged() {
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focusedContext == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final scrollable = Scrollable.maybeOf(focusedContext);
      if (scrollable == null || scrollable.widget.controller != _scrollController) {
        return;
      }

      Scrollable.ensureVisible(
        focusedContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final layout = layoutClassFor(screenWidth);
    final isTablet = layout.isAtLeastMedium;

    final horizontalInset = switch (layout) {
      LayoutClass.compact => 16.0,
      LayoutClass.medium => 24.0,
      LayoutClass.expanded => 24.0,
    };

    const verticalInset = 24.0;

    // Responsive max width. The actual width is further clamped by the
    // available child area reported by the inner [LayoutBuilder].
    final maxDialogWidth = switch (layout) {
      LayoutClass.compact => min(360.0, max(120.0, screenWidth - 32.0)),
      LayoutClass.medium => min(480.0, max(120.0, screenWidth - 48.0)),
      LayoutClass.expanded => min(560.0, max(120.0, screenWidth - 48.0)),
    };

    return Semantics(
      label: widget.type.semanticLabel,
      container: true,
      child: Dialog(
        alignment: Alignment.center,
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(maxDialogWidth, constraints.maxWidth),
                maxHeight: constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xxl),
                child: _buildContent(context, isTablet),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isTablet) {
    final isForm = widget.child != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isForm) ...[
          _buildFormHeader(context),
          const SizedBox(height: Spacing.md),
        ],
        Flexible(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            child: isForm ? widget.child! : _buildAlertContent(context),
          ),
        ),
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: Spacing.xxl),
          _buildActions(context, isTablet),
        ],
      ],
    );
  }

  Widget _buildFormHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showIcon) ...[
                    Center(child: _buildIcon(context, false)),
                    const SizedBox(height: Spacing.lg),
                  ],
                  Text(
                    widget.title,
                    style: AppTypography.headlineSmallSemibold(context),
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
            if (widget.showClose) _buildCloseButton(context),
          ],
        ),
        if (widget.message != null) ...[
          const SizedBox(height: Spacing.sm),
          _buildMessage(context, false),
        ],
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    final onPressed = widget.onClosePressed ??
        (dialogContext) =>
            Navigator.of(dialogContext, rootNavigator: true).pop();

    return Padding(
      padding: const EdgeInsets.only(left: Spacing.sm),
      child: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close',
        visualDensity: VisualDensity.compact,
        onPressed: () => onPressed(context),
      ),
    );
  }

  /// Body content for alert-style dialogs. It lives inside the scrollable
  /// region so long messages and details can scroll while the action buttons
  /// remain fixed at the bottom.
  Widget _buildAlertContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showIcon) ...[
          _buildIcon(context, true),
          const SizedBox(height: Spacing.lg),
        ],
        _buildTitle(context, true),
        if (widget.message != null) ...[
          const SizedBox(height: Spacing.sm),
          _buildMessage(context, true),
        ],
        if (widget.details != null) ...[
          const SizedBox(height: Spacing.sm),
          _buildDetails(context),
        ],
      ],
    );
  }

  Widget _buildIcon(BuildContext context, bool centered) {
    final brightness = Theme.of(context).brightness;
    if (widget.type == AppDialogType.loading) {
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
      alignment: centered ? Alignment.center : Alignment.center,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: widget.type.iconBgColor(brightness),
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.type.icon,
          size: 32,
          color: widget.type.iconColor(brightness),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool centered) {
    return Text(
      widget.title,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: AppTypography.headlineSmallSemibold(context),
    );
  }

  Widget _buildMessage(BuildContext context, bool centered) {
    return Text(
      widget.message!,
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
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        widget.details!,
        softWrap: true,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isTablet) {
    final stackVertically = widget.actions.length > 2 || !isTablet;

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
        children: widget.actions.asMap().entries.map((entry) {
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: widget.actions.asMap().entries.map((entry) {
        final i = entry.key;
        final action = entry.value;
        final isFirst = i == 0;
        final isLast = i == widget.actions.length - 1;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: isFirst ? 0 : Spacing.sm,
              right: isLast ? 0 : Spacing.sm,
            ),
            child: buildAction(action, fullWidth: true),
          ),
        );
      }).toList(),
    );
  }
}
