import 'package:flutter/material.dart';

/// Base widget for all dialogs in the app.
///
/// Uses [showGeneralDialog] so the dialog is centered both vertically and
/// horizontally on screen (not bottom-anchored). Includes a fade + scale
/// transition and is responsive (tablet >= 600px width gets a max width of
/// 520dp with 32px horizontal padding; phone gets full width with 16px).
///
/// This file is intentionally self-contained: it only depends on
/// `flutter/material.dart` and uses hardcoded spacing values so it can be
/// dropped into any project without a theme file.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key});

  /// Shows a centered dialog with fade + scale animation.
  ///
  /// Returns the value popped from the dialog (via [Navigator.pop]) or
  /// `null` if the dialog was dismissed without a value.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    IconData? icon,
    Color? iconColor,
    Widget? customIcon,
    List<Widget> actions = const [],
    bool barrierDismissible = true,
    VoidCallback? onDismiss,
  }) {
    if (!context.mounted) return Future.value(null);

    final colorScheme = Theme.of(context).colorScheme;

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
            child: Opacity(
              opacity: curved,
              child: child,
            ),
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
                if (icon != null || customIcon != null) ...[
                  _IconCircle(
                    icon: icon,
                    iconColor: iconColor,
                    customIcon: customIcon,
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
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  if (isTablet)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions
                          .expand((a) => [a, const SizedBox(width: 8)])
                          .toList()
                        ..removeLast(),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: actions
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
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              onDismiss?.call();
            }
          },
          child: Semantics(
            label: 'Dialog: $title',
            namesRoute: true,
            child: content,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    this.icon,
    this.iconColor,
    this.customIcon,
  });

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
