import 'package:flutter/material.dart';

/// A single self-contained file that combines ALL dialog types
/// (success, error, warning, info, confirm, no internet, loading, custom)
/// into one widget with NO external dialog imports — only
/// `flutter/material.dart`.
///
/// ## Dialog type presets
///
/// | DialogType    | Icon                          | Color            | Default actions           |
/// |---------------|-------------------------------|------------------|---------------------------|
/// | success       | `check_circle_rounded`        | `0xFF059669`     | OK (elevated)             |
/// | error         | `error_outline_rounded`       | `0xFFDC2626`     | Try Again / Close         |
/// | warning       | `warning_amber_rounded`       | `0xFFD97706`     | Confirm / Cancel          |
/// | info          | `info_outline_rounded`        | `0xFF2563EB`     | Got It (elevated)         |
/// | confirm       | `help_outline_rounded`        | `colorScheme.primary` | Confirm / Cancel     |
/// | noInternet    | `wifi_off_rounded`            | `0xFFD97706`     | Retry / Close             |
/// | loading       | `CircularProgressIndicator`   | (theme)          | (none)                    |
/// | custom        | (caller-supplied)             | (caller-supplied)| (caller-supplied)         |
///
/// ## One-liner usage
///
/// ```dart
/// await UniversalDialog.success(context, message: 'Saved!');
/// final ok = await UniversalDialog.confirm(
///   context,
///   message: 'Delete this item?',
///   isDestructive: true,
/// );
/// ```
///
/// ## Full custom usage
///
/// ```dart
/// await UniversalDialog.show(
///   context: context,
///   title: 'Custom',
///   message: 'Pick an option',
///   type: DialogType.custom,
///   icon: Icons.star,
///   iconColor: Colors.amber,
///   actions: [
///     DialogAction.outlined('Later', onTap: () {}),
///     DialogAction.elevated('Now', onTap: () {}),
///   ],
/// );
/// ```
enum DialogType {
  success,
  error,
  warning,
  info,
  confirm,
  noInternet,
  loading,
  custom,
}

/// Visual style of a [DialogAction] button.
enum DialogActionStyle {
  elevated,
  outlined,
  text,
  destructive,
}

/// A button action shown inside a [UniversalDialog].
class DialogAction {
  const DialogAction({
    required this.label,
    required this.style,
    this.onTap,
  });

  final String label;
  final DialogActionStyle style;
  final VoidCallback? onTap;

  factory DialogAction.elevated(String label, {VoidCallback? onTap}) =>
      DialogAction(label: label, style: DialogActionStyle.elevated, onTap: onTap);

  factory DialogAction.outlined(String label, {VoidCallback? onTap}) =>
      DialogAction(label: label, style: DialogActionStyle.outlined, onTap: onTap);

  factory DialogAction.text(String label, {VoidCallback? onTap}) =>
      DialogAction(label: label, style: DialogActionStyle.text, onTap: onTap);

  factory DialogAction.destructive(String label, {VoidCallback? onTap}) =>
      DialogAction(
          label: label, style: DialogActionStyle.destructive, onTap: onTap);
}

class _DialogPreset {
  const _DialogPreset({this.icon, this.iconColor, this.customIcon});

  final IconData? icon;
  final Color? iconColor;
  final Widget? customIcon;

  static _DialogPreset forType(DialogType type, ColorScheme colorScheme) {
    switch (type) {
      case DialogType.success:
        return const _DialogPreset(
          icon: Icons.check_circle_rounded,
          iconColor: Color(0xFF059669),
        );
      case DialogType.error:
        return const _DialogPreset(
          icon: Icons.error_outline_rounded,
          iconColor: Color(0xFFDC2626),
        );
      case DialogType.warning:
        return const _DialogPreset(
          icon: Icons.warning_amber_rounded,
          iconColor: Color(0xFFD97706),
        );
      case DialogType.info:
        return const _DialogPreset(
          icon: Icons.info_outline_rounded,
          iconColor: Color(0xFF2563EB),
        );
      case DialogType.confirm:
        return _DialogPreset(
          icon: Icons.help_outline_rounded,
          iconColor: colorScheme.primary,
        );
      case DialogType.noInternet:
        return const _DialogPreset(
          icon: Icons.wifi_off_rounded,
          iconColor: Color(0xFFD97706),
        );
      case DialogType.loading:
        return _DialogPreset(
          customIcon: const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(),
          ),
        );
      case DialogType.custom:
        return const _DialogPreset();
    }
  }
}

/// A universal dialog widget supporting all standard dialog types plus
/// fully custom configurations.
class UniversalDialog extends StatelessWidget {
  const UniversalDialog({super.key});

  /// Shows a dialog of the given [type] with fade + scale animation.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    DialogType type = DialogType.custom,
    IconData? icon,
    Color? iconColor,
    Widget? customIcon,
    List<DialogAction>? actions,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) return Future.value(null);

    final colorScheme = Theme.of(context).colorScheme;
    final preset = _DialogPreset.forType(type, colorScheme);

    final effectiveIcon = icon ?? preset.icon;
    final effectiveIconColor = iconColor ?? preset.iconColor;
    final effectiveCustomIcon = customIcon ?? preset.customIcon;

    final builtActions = actions?.map((a) => _buildButton(context, a)).toList();

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dialog: $title',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: Opacity(opacity: curved, child: child),
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(context);
        final isTablet = mediaQuery.size.width >= 600;
        final horizontalPadding = isTablet ? 32.0 : 16.0;

        Widget content = AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          contentPadding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            16,
          ),
          content: ConstrainedBox(
            constraints: isTablet
                ? const BoxConstraints(maxWidth: 520)
                : const BoxConstraints(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (effectiveIcon != null || effectiveCustomIcon != null) ...[
                  _IconCircle(
                    icon: effectiveIcon,
                    iconColor: effectiveIconColor,
                    customIcon: effectiveCustomIcon,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 24.0 : 18.0,
                      ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                  ),
                ],
                if (builtActions != null && builtActions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  if (isTablet)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: builtActions
                          .expand((a) => [a, const SizedBox(width: 8)])
                          .toList()
                        ..removeLast(),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: builtActions
                          .expand((a) => [a, const SizedBox(height: 8)])
                          .toList()
                        ..removeLast(),
                    ),
                ],
              ],
            ),
          ),
        );

        if (isTablet) {
          content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: content,
            ),
          );
        }

        return PopScope(
          canPop: barrierDismissible,
          child: Semantics(
            label: 'Dialog: $title',
            namesRoute: true,
            child: content,
          ),
        );
      },
    );
  }

  static Widget _buildButton(BuildContext context, DialogAction action) {
    final colorScheme = Theme.of(context).colorScheme;
    void popAndTap() {
      final popValue = action.style == DialogActionStyle.elevated ||
          action.style == DialogActionStyle.destructive;
      Navigator.of(context).pop(popValue);
      action.onTap?.call();
    }

    switch (action.style) {
      case DialogActionStyle.elevated:
        return ElevatedButton(
          onPressed: popAndTap,
          child: Text(action.label),
        );
      case DialogActionStyle.outlined:
        return OutlinedButton(
          onPressed: popAndTap,
          child: Text(action.label),
        );
      case DialogActionStyle.text:
        return TextButton(
          onPressed: popAndTap,
          child: Text(action.label),
        );
      case DialogActionStyle.destructive:
        return ElevatedButton(
          onPressed: popAndTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: Text(action.label),
        );
    }
  }

  // ---- One-liner helpers -------------------------------------------------

  /// Shows a success dialog. Resolves when dismissed.
  static Future<void> success(
    BuildContext context, {
    String title = 'Success',
    required String message,
    String okLabel = 'OK',
    VoidCallback? onOk,
  }) {
    return show(
      context: context,
      title: title,
      message: message,
      type: DialogType.success,
      barrierDismissible: true,
      actions: [
        DialogAction.elevated(okLabel, onTap: onOk),
      ],
    );
  }

  /// Shows an error dialog. Resolves `true` if retry tapped, `false` otherwise.
  static Future<bool> error(
    BuildContext context, {
    String title = 'Error',
    required String message,
    String retryLabel = 'Try Again',
    String closeLabel = 'Close',
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      message: message,
      type: DialogType.error,
      barrierDismissible: true,
      actions: [
        DialogAction.outlined(closeLabel, onTap: onClose),
        DialogAction.elevated(retryLabel, onTap: onRetry),
      ],
    );
    return result ?? false;
  }

  /// Shows an info dialog. Resolves when dismissed.
  static Future<void> info(
    BuildContext context, {
    String title = 'Info',
    required String message,
    String okLabel = 'Got It',
    VoidCallback? onOk,
  }) {
    return show(
      context: context,
      title: title,
      message: message,
      type: DialogType.info,
      barrierDismissible: true,
      actions: [
        DialogAction.elevated(okLabel, onTap: onOk),
      ],
    );
  }

  /// Shows a warning dialog. Resolves `true` if confirmed, `false` otherwise.
  static Future<bool> warning(
    BuildContext context, {
    String title = 'Warning',
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      message: message,
      type: DialogType.warning,
      barrierDismissible: true,
      actions: [
        DialogAction.outlined(cancelLabel, onTap: onCancel),
        DialogAction.elevated(confirmLabel, onTap: onConfirm),
      ],
    );
    return result ?? false;
  }

  /// Shows a confirmation dialog. Resolves `true` if confirmed, `false` otherwise.
  static Future<bool> confirm(
    BuildContext context, {
    String title = 'Confirm',
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      message: message,
      type: DialogType.confirm,
      barrierDismissible: true,
      actions: [
        DialogAction.outlined(cancelLabel, onTap: onCancel),
        isDestructive
            ? DialogAction.destructive(confirmLabel, onTap: onConfirm)
            : DialogAction.elevated(confirmLabel, onTap: onConfirm),
      ],
    );
    return result ?? false;
  }

  /// Shows a no-internet dialog (not dismissible by barrier).
  /// Resolves `true` if retry tapped, `false` otherwise.
  static Future<bool> noInternet(
    BuildContext context, {
    String title = 'No Internet Connection',
    String message =
        'This feature requires an internet connection. Please connect to Wi-Fi or mobile data and try again.',
    String retryLabel = 'Retry',
    String closeLabel = 'Close',
    VoidCallback? onRetry,
    VoidCallback? onClose,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      message: message,
      type: DialogType.noInternet,
      barrierDismissible: false,
      actions: [
        DialogAction.outlined(closeLabel, onTap: onClose),
        DialogAction.elevated(retryLabel, onTap: onRetry),
      ],
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({this.icon, this.iconColor, this.customIcon});

  final IconData? icon;
  final Color? iconColor;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (iconColor ?? Theme.of(context).colorScheme.primary)
            .withValues(alpha: 0.1),
      ),
      alignment: Alignment.center,
      child: customIcon ??
          Icon(
            icon,
            size: 32,
            color: iconColor,
          ),
    );
  }
}
