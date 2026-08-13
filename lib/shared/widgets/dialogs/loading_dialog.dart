import 'package:flutter/material.dart';

/// Controller used to dismiss a [LoadingDialog].
///
/// Obtain an instance from [LoadingDialog.show] and call [dismiss] once your
/// async operation completes.
class LoadingDialogController {
  LoadingDialogController._(this._dismiss);

  /// Returns a controller whose [dismiss] is a no-op. Useful as a safe
  /// default when the dialog could not be shown (e.g. context not mounted).
  factory LoadingDialogController.noop() => LoadingDialogController._(() {});

  final VoidCallback _dismiss;

  /// Dismisses the loading dialog.
  void dismiss() => _dismiss();
}

/// A loading dialog showing a spinner with an optional message.
///
/// This dialog does NOT use [AppDialog] because it shows a spinner instead of
/// an icon. It has its own [showGeneralDialog] call with the same fade + scale
/// animation as [AppDialog].
///
/// Example:
/// ```dart
/// final controller = LoadingDialog.show(
///   context: context,
///   message: 'Saving your data...',
/// );
/// try {
///   await saveData();
/// } finally {
///   controller.dismiss();
/// }
/// ```
class LoadingDialog extends StatelessWidget {
  const LoadingDialog({super.key});

  /// Shows a loading dialog and returns a [LoadingDialogController] that can
  /// be used to dismiss it.
  static LoadingDialogController show({
    required BuildContext context,
    String? message,
    bool barrierDismissible = false,
  }) {
    if (!context.mounted) return LoadingDialogController.noop();

    final colorScheme = Theme.of(context).colorScheme;

    showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Loading...',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
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
            24,
          ),
          content: ConstrainedBox(
            constraints: isTablet
                ? const BoxConstraints(maxWidth: 520)
                : const BoxConstraints(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(),
                ),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
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
          canPop: false,
          child: Semantics(
            label: 'Loading...',
            namesRoute: true,
            child: content,
          ),
        );
      },
    );

    return LoadingDialogController._(() {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
