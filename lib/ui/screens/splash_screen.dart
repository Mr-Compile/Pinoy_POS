import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/app_shell.dart';
import 'package:pinoy_pos/ui/screens/force_change_password_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/screens/pin_lock_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_logo.dart';

/// Splash screen shown during application initialization.
///
/// Displays the Pinoy POS logo and app identity while the auth state
/// is being restored. Once the auth state is determined (authenticated
/// or not), navigates to the appropriate screen:
///
///   - Authenticated → [AppShell]
///   - Unauthenticated → [LoginScreen]
///
/// The splash is theme-aware (light/dark) and uses the universal
/// Pinoy POS Blue branding. No artificial delays — the splash is
/// visible only while `AuthStateNotifier._init()` runs.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Once auth initialization completes, navigate to the appropriate
    // screen. We use a post-frame callback to avoid triggering
    // navigation during build.
    if (!authState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (authState.phase) {
          case AuthSessionPhase.fullyAuthenticated:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AppShell()),
            );
          case AuthSessionPhase.passwordAuthenticatedPendingPasswordChange:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ForceChangePasswordScreen()),
            );
          case AuthSessionPhase.passwordAuthenticatedPendingPin:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PinLockScreen()),
            );
          case AuthSessionPhase.unauthenticated:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
        }
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo ──
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 120,
                  maxHeight: 150,
                ),
                child: const AppLogo(
                  size: 120,
                  variant: LogoVariant.full,
                ),
              ),
              const SizedBox(height: 24),
              // ── App name ──
              Text(
                AppConstants.appName,
                style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 8),
              // ── Tagline ──
              Text(
                'Simple. Offline. Reliable.',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 40),
              // ── Loading indicator ──
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
