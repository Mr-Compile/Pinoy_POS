import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
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
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Prevents multiple post-frame callbacks from triggering duplicate
  /// `pushReplacement` calls. Duplicate navigations can cause the
  /// Flutter framework to remove the same element from the inactive
  /// list twice, which throws the `_elements.contains(element)`
  /// assertion seen on app launch.
  bool _hasNavigated = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Once auth initialization completes, navigate to the appropriate
    // screen. We use a post-frame callback to avoid triggering
    // navigation during build, and a [_hasNavigated] guard to ensure
    // only one navigation is ever attempted.
    if (!authState.isLoading && !_hasNavigated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hasNavigated || !mounted) return;

        final current = ref.read(authStateProvider);
        if (current.isLoading) return;

        _hasNavigated = true;
        AuthPhaseNavigator.pushReplacement(context, current.phase);
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
