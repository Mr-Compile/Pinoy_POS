import 'package:flutter/material.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/app_shell.dart';
import 'package:pinoy_pos/ui/screens/force_change_password_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/screens/pin_lock_screen.dart';

/// Centralized auth-phase navigation.
///
/// Maps [AuthSessionPhase] values to the correct top-level screen and
/// provides one-shot helpers that reduce the copy-pasted
/// `MaterialPageRoute` / `pushAndRemoveUntil` blocks found in
/// [SplashScreen], [LoginScreen], [ForceChangePasswordScreen],
/// [PinLockScreen] and [AppShell].
///
/// Every auth-phase transition clears the entire back stack via
/// [pushAndRemoveUntil]. This keeps the navigation convergent: if two
/// transitions race (e.g. the `AppShell` redirect and `SessionGuard`
/// timeout firing in the same frame), each call pushes the target screen
/// and removes everything below it, so the stack always collapses to the
/// single correct phase screen. Partial stack replacement (e.g.
/// `pushReplacement`) is intentionally not offered here because it can
/// leave a stale `LoginScreen` or authenticated screen reachable through
/// the system back button.
class AuthPhaseNavigator {
  AuthPhaseNavigator._();

  /// Returns the screen that should be shown for the given [phase].
  static Widget screenForPhase(AuthSessionPhase phase) {
    return switch (phase) {
      AuthSessionPhase.fullyAuthenticated => const AppShell(),
      AuthSessionPhase.passwordAuthenticatedPendingPasswordChange =>
          const ForceChangePasswordScreen(),
      AuthSessionPhase.passwordAuthenticatedPendingPin =>
          const PinLockScreen(),
      AuthSessionPhase.unauthenticated => const LoginScreen(),
    };
  }

  /// Builds a [MaterialPageRoute] for [phase].
  static Route<void> routeForPhase(AuthSessionPhase phase) {
    return MaterialPageRoute(builder: (_) => screenForPhase(phase));
  }

  /// Pushes the screen for [phase] and removes all previous routes.
  ///
  /// The default [predicate] removes the entire back stack. Pass a custom
  /// predicate when you need to keep one or more routes.
  static Future<void> pushAndRemoveUntil(
    BuildContext context,
    AuthSessionPhase phase, {
    bool Function(Route<dynamic>)? predicate,
  }) {
    return Navigator.of(context).pushAndRemoveUntil(
      routeForPhase(phase),
      predicate ?? (_) => false,
    );
  }
}
