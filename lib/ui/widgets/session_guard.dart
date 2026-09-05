import 'dart:async';

import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/session_settings_service.dart';
import 'package:pinoy_pos/services/session_timeout_service.dart';

/// Root-level widget that watches user input and app lifecycle to enforce
/// inactivity and absolute session expiry.
///
/// It is placed inside `MaterialApp.builder` so it exists for the lifetime of
/// the app and can drive the root navigator via [navigatorKey].
class SessionGuard extends ConsumerStatefulWidget {
  const SessionGuard({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends ConsumerState<SessionGuard>
    with WidgetsBindingObserver {
  late final SessionTimeoutService _sessionTimeoutService;
  late final ProviderSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachInputListeners();

    _sessionTimeoutService = SessionTimeoutService(
      authService: ref.read(authServiceProvider),
      sessionSettingsService: SessionSettingsService(),
      onInactivityTimeout: _handleInactivityTimeout,
      onSessionExpired: _handleSessionExpired,
    );

    _authSubscription = ref.listenManual(
      authStateProvider,
      _handleAuthStateChanged,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachInputListeners();
    _authSubscription.close();
    unawaited(_sessionTimeoutService.endSession());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_sessionTimeoutService.handleAppLifecycle(state));
  }

  void _attachInputListeners() {
    // Capture all pointer events globally.  This is more reliable than a
    // `Listener` because it does not depend on hit testing inside dialogs,
    // overlays, or deep routes.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);

    // Capture physical keyboard events.  This is required on desktop and
    // mobile (external keyboards) so typing counts as activity.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  void _detachInputListeners() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerEvent);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
  }

  void _onPointerEvent(PointerEvent event) {
    _recordActivity();
  }

  bool _onKeyEvent(KeyEvent event) {
    _recordActivity();
    return false;
  }

  void _recordActivity() {
    final state = ref.read(authStateProvider);
    if (state.user == null || state.phase == AuthSessionPhase.unauthenticated) {
      return;
    }
    _sessionTimeoutService.userDidInteract();
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    if (next.isLoading) return;

    if (next.user == null) {
      unawaited(_sessionTimeoutService.endSession());
      return;
    }

    if (previous != null &&
        previous.user == next.user &&
        previous.phase == next.phase) {
      return;
    }

    unawaited(
      _sessionTimeoutService.startSession(
        next.user!,
        resetActivity: next.phase != AuthSessionPhase.fullyAuthenticated,
      ),
    );
  }

  void _handleInactivityTimeout() {
    final state = ref.read(authStateProvider);
    if (state.user == null) return;

    if (state.phase == AuthSessionPhase.fullyAuthenticated) {
      // Short inactivity: re-lock to PIN when the user has one, otherwise
      // perform a full logout.
      if (state.user!.hasPin) {
        _pushAuthPhaseAndUpdate(
          AuthSessionPhase.passwordAuthenticatedPendingPin,
          () {
            ref.read(authStateProvider.notifier).lockSession();
          },
        );
      } else {
        _pushAuthPhaseAndUpdate(
          AuthSessionPhase.unauthenticated,
          () {
            ref.read(authStateProvider.notifier).logout();
          },
        );
      }
      return;
    }

    // Already on a PIN or forced-change screen; treat as full logout.
    _pushAuthPhaseAndUpdate(
      AuthSessionPhase.unauthenticated,
      () {
        ref.read(authStateProvider.notifier).logout();
      },
    );
  }

  void _handleSessionExpired() {
    _pushAuthPhaseAndUpdate(
      AuthSessionPhase.unauthenticated,
      () {
        ref.read(authStateProvider.notifier).logout();
      },
    );
  }

  /// Pushes the target auth phase route before updating `AuthState`.
  ///
  /// This order prevents the existing `AppShell`/`SplashScreen` redirect logic
  /// from racing with the session timeout.
  void _pushAuthPhaseAndUpdate(
    AuthSessionPhase phase,
    void Function() updateState,
  ) {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) {
      updateState();
      return;
    }

    navigator.pushAndRemoveUntil(
      AuthPhaseNavigator.routeForPhase(phase),
      (_) => false,
    );
    updateState();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
