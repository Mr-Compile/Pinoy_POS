import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// Semantic roles for every Pinoy POS dialog.
///
/// Each role maps to a fixed icon, a semantic icon container colour, and a
/// default primary-button colour so the entire dialog system stays consistent.
/// The values here are the source of truth for the visual language described
/// in the global semantic dialog foundation.
///
/// Icons are Material designs that match the Lucide names used in the design
/// reference, because the project’s icon system is Material.
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
  delete,
  permanentDelete,
  restore,
  ai,
  payment,
  logout,
  add,
  edit,
}

/// Icon, colour and accessibility metadata for [AppDialogType].
extension AppDialogTypeX on AppDialogType {
  /// The Material icon that best matches the Lucide names used in the design
  /// reference. [loading] returns `null` because it renders a spinner.
  IconData? get icon {
    switch (this) {
      case AppDialogType.success:
        return Icons.check_circle_outline;
      case AppDialogType.restore:
        return Icons.restore;
      case AppDialogType.error:
      case AppDialogType.validation:
        return Icons.cancel_outlined;
      case AppDialogType.warning:
        return Icons.warning_amber_outlined;
      case AppDialogType.info:
        return Icons.info_outline;
      case AppDialogType.restriction:
        return Icons.lock_outline;
      case AppDialogType.offline:
        return Icons.wifi_off;
      case AppDialogType.delete:
        return Icons.delete_outline;
      case AppDialogType.permanentDelete:
        return Icons.delete_forever;
      case AppDialogType.confirmation:
        return Icons.help_outline;
      case AppDialogType.ai:
        return Icons.auto_awesome;
      case AppDialogType.payment:
        return Icons.account_balance_wallet_outlined;
      case AppDialogType.logout:
        return Icons.logout;
      case AppDialogType.add:
        return Icons.add;
      case AppDialogType.edit:
        return Icons.edit_outlined;
      case AppDialogType.loading:
        return null;
    }
  }

  /// Foreground colour for the icon symbol.
  ///
  /// The icon is the semantic colour itself, sitting on a subtle tinted
  /// background. This gives each dialog its meaning while keeping both light
  /// and dark variants readable.
  Color iconColor(Brightness brightness) {
    return switch (this) {
      AppDialogType.success ||
      AppDialogType.restore =>
        AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      AppDialogType.error ||
      AppDialogType.delete ||
      AppDialogType.permanentDelete ||
      AppDialogType.logout =>
        AppSemanticColors.resolve(AppSemanticColors.error, brightness),
      AppDialogType.warning ||
      AppDialogType.offline =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      AppDialogType.validation =>
        AppSemanticColors.resolve(AppSemanticColors.error, brightness),
      AppDialogType.info ||
      AppDialogType.add ||
      AppDialogType.edit =>
        AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      AppDialogType.restriction =>
        AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
      AppDialogType.confirmation ||
      AppDialogType.payment =>
        AppSemanticColors.resolve(AppSemanticColors.primary, brightness),
      AppDialogType.ai =>
        AppSemanticColors.resolve(AppSemanticColors.purple, brightness),
      AppDialogType.loading =>
        AppSemanticColors.resolve(AppSemanticColors.primary, brightness),
    };
  }

  /// Background colour of the circular icon container.
  ///
  /// Uses the theme-aware container colour so the surface is subtly tinted in
  /// light mode and darkly tinted in dark mode.
  Color iconBgColor(Brightness brightness) {
    return switch (this) {
      AppDialogType.success ||
      AppDialogType.restore =>
        AppSemanticColors.resolve(AppSemanticColors.successContainer, brightness),
      AppDialogType.error ||
      AppDialogType.delete ||
      AppDialogType.permanentDelete ||
      AppDialogType.logout =>
        AppSemanticColors.resolve(AppSemanticColors.errorContainer, brightness),
      AppDialogType.warning ||
      AppDialogType.offline =>
        AppSemanticColors.resolve(AppSemanticColors.warningContainer, brightness),
      AppDialogType.validation =>
        AppSemanticColors.resolve(AppSemanticColors.errorContainer, brightness),
      AppDialogType.info ||
      AppDialogType.add ||
      AppDialogType.edit =>
        AppSemanticColors.resolve(AppSemanticColors.infoContainer, brightness),
      AppDialogType.restriction =>
        AppSemanticColors.resolve(AppSemanticColors.neutralContainer, brightness),
      AppDialogType.confirmation ||
      AppDialogType.payment =>
        AppSemanticColors.resolve(AppSemanticColors.infoContainer, brightness),
      AppDialogType.ai =>
        AppSemanticColors.resolve(AppSemanticColors.purpleContainer, brightness),
      AppDialogType.loading =>
        AppSemanticColors.resolve(AppSemanticColors.neutralContainer, brightness),
    };
  }

  /// Colour for the [CircularProgressIndicator] shown in loading dialogs.
  Color spinnerColor(Brightness brightness) {
    return AppSemanticColors.resolve(AppSemanticColors.primary, brightness);
  }

  /// Accessibility label for the dialog as a whole.
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
      case AppDialogType.delete:
        return 'Delete item';
      case AppDialogType.permanentDelete:
        return 'Permanently delete';
      case AppDialogType.restore:
        return 'Restore item';
      case AppDialogType.ai:
        return 'AI Assistant';
      case AppDialogType.payment:
        return 'Payment';
      case AppDialogType.logout:
        return 'Log out';
      case AppDialogType.add:
        return 'Add item';
      case AppDialogType.edit:
        return 'Edit item';
    }
  }

  /// Default button colour for the primary action when no explicit colour is
  /// supplied.
  AppButtonColor get primaryButtonColor {
    switch (this) {
      case AppDialogType.success:
      case AppDialogType.restore:
      case AppDialogType.restriction:
      case AppDialogType.confirmation:
      case AppDialogType.info:
      case AppDialogType.error:
      case AppDialogType.offline:
      case AppDialogType.payment:
      case AppDialogType.add:
      case AppDialogType.edit:
      case AppDialogType.ai:
        return AppButtonColor.primary;
      case AppDialogType.delete:
      case AppDialogType.permanentDelete:
      case AppDialogType.logout:
        return AppButtonColor.error;
      case AppDialogType.warning:
      case AppDialogType.validation:
        return AppButtonColor.warning;
      case AppDialogType.loading:
        return AppButtonColor.primary;
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
  final AppButtonColor? color;

  const AppDialogAction({
    required this.label,
    this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isLoading = false,
    this.color,
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

    // Compact dialogs use slightly tighter padding, while tablet/desktop keep
    // the standard 24 dp.
    final contentPadding = Spacing.xl;

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
                padding: EdgeInsets.all(contentPadding),
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
          const SizedBox(height: Spacing.lg),
          _buildActions(context, isTablet),
        ],
      ],
    );
  }

  Widget _buildFormHeader(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
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

    if (!widget.showClose) return content;

    return Stack(
      alignment: Alignment.center,
      children: [
        content,
        Positioned(
          right: 0,
          top: 0,
          child: _buildCloseButton(context),
        ),
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
        icon: Icon(
          Icons.close,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: widget.type.spinnerColor(brightness),
          ),
        ),
      );
    }

    final iconData = widget.type.icon;
    if (iconData == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: widget.type.iconBgColor(brightness),
          shape: BoxShape.circle,
        ),
        child: Icon(
          iconData,
          size: 20,
          color: widget.type.iconColor(brightness),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool centered) {
    return Text(
      widget.title,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: AppTypography.titleLargeBold(context).copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildMessage(BuildContext context, bool centered) {
    return Text(
      widget.message!,
      softWrap: true,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: AppTypography.bodyMedium(context).copyWith(
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
        style: AppTypography.bodyMedium(context).copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isTablet) {
    Widget buildAction(AppDialogAction action, {required bool fullWidth}) {
      final handler = action.onPressed == null || action.isLoading
          ? null
          : () => action.onPressed!(context);

      final color = action.isPrimary
          ? (action.color ??
              (action.isDestructive
                  ? AppButtonColor.error
                  : widget.type.primaryButtonColor))
          : (action.color ??
              (action.isDestructive ? AppButtonColor.error : AppButtonColor.neutral));

      // The mockup uses filled buttons for primary blue actions and
      // outlined buttons for warning/error actions, even when they are
      // the primary action (e.g. Discard, Delete, Log out).
      final bool isOutlined = !action.isPrimary ||
          color == AppButtonColor.warning ||
          color == AppButtonColor.error;

      if (isOutlined) {
        return AppButton.outlined(
          onPressed: handler,
          label: action.label,
          color: color,
          isLoading: action.isLoading,
          fullWidth: fullWidth,
        );
      }

      return AppButton.filled(
        onPressed: handler,
        label: action.label,
        color: color,
        isLoading: action.isLoading,
        fullWidth: fullWidth,
      );
    }

    if (widget.actions.length > 2) {
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

    // One or two actions always sit side-by-side and share the width,
    // matching the CRUD mockup action bar.
    return Row(
      children: [
        Expanded(
          child: buildAction(widget.actions.first, fullWidth: true),
        ),
        if (widget.actions.length == 2) ...[
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: buildAction(widget.actions.last, fullWidth: true),
          ),
        ],
      ],
    );
  }
}
