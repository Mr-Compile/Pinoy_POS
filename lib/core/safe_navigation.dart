import 'package:flutter/material.dart';

/// Lightweight helpers that wrap common navigation patterns to avoid
/// duplicate `MaterialPageRoute` builders and accidental double-pushes.
class SafeNavigator {
  SafeNavigator._();

  /// Pushes [screen] only if it is not already the top route.
  ///
  /// The route is given a [RouteSettings.name] based on the screen's
  /// runtime type so repeated taps on the same menu item do not stack
  /// multiple copies of the same screen.
  ///
  /// [onComplete] is called after the pushed route is popped, or
  /// immediately when the screen is already on top.
  static Future<T?>? pushUnique<T>(
    BuildContext context,
    Widget screen, {
    bool useRootNavigator = false,
    VoidCallback? onComplete,
    String? routeName,
  }) {
    if (!context.mounted) return null;

    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    return _pushUniqueToNavigator<T>(
      navigator,
      screen,
      onComplete,
      routeName,
    );
  }

  /// Pushes [screen] on the root [Navigator] accessed through [key].
  ///
  /// Use this when the caller lives above the [Navigator] (for example
  /// inside [MaterialApp.builder]) and cannot use [Navigator.of] from its
  /// own [BuildContext].
  static Future<T?>? pushUniqueWithKey<T>(
    GlobalKey<NavigatorState> key,
    Widget screen, {
    VoidCallback? onComplete,
    String? routeName,
  }) {
    final navigator = key.currentState;
    if (navigator == null || !navigator.mounted) return null;

    return _pushUniqueToNavigator<T>(
      navigator,
      screen,
      onComplete,
      routeName,
    );
  }

  static Future<T?>? _pushUniqueToNavigator<T>(
    NavigatorState navigator,
    Widget screen,
    VoidCallback? onComplete,
    String? routeName,
  ) {
    final screenName = routeName ?? screen.runtimeType.toString();
    var isAlreadyOnScreen = false;

    navigator.popUntil((route) {
      if (route.settings.name == screenName) {
        isAlreadyOnScreen = true;
      }
      return true;
    });

    if (isAlreadyOnScreen) {
      onComplete?.call();
      return null;
    }

    final future = navigator.push<T>(
      MaterialPageRoute(
        builder: (_) => screen,
        settings: RouteSettings(name: screenName),
      ),
    );

    if (onComplete != null) {
      future.whenComplete(onComplete);
    }

    return future;
  }
}
