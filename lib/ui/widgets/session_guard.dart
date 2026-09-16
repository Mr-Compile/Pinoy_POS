import 'dart:async';

import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/services/session_settings_service.dart';
import 'package:pinoy_pos/services/session_timeout_service.dart';
import 'package:pinoy_pos/ui/dialogs/session_expiring_dialog.dart';
import 'package:pinoy_pos/ui/screens/activation_screen.dart';
import 'package:pinoy_pos/ui/screens/license_locked_screen.dart';

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
  late final ProviderSubscription<LicenseStatus> _licenseSubscription;
  Timer? _licenseTimer;
  bool _licenseLockEnforced = false;

  /// The currently displayed session-expiry warning route, if any.
  /// Tracked so the warning can never be shown twice and can be removed
  /// precisely (e.g. when the session ends while the dialog is up).
  DialogRoute<void>? _warningRoute;

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
      onWarning: _handleSessionWarning,
    );

    _authSubscription = ref.listenManual(
      authStateProvider,
      _handleAuthStateChanged,
    );

    // License enforcement: watch the status provider for a transition into
    // a locked state, and re-evaluate it on a timer so an armed license
    // that expires mid-session still logs everyone out.
    _licenseSubscription = ref.listenManual(
      licenseStatusProvider,
      _handleLicenseChanged,
    );
    _licenseTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _recheckLicense(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachInputListeners();
    _authSubscription.close();
    _licenseSubscription.close();
    _licenseTimer?.cancel();
    unawaited(_sessionTimeoutService.endSession());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_sessionTimeoutService.handleAppLifecycle(state));
    if (state == AppLifecycleState.resumed) {
      _recheckLicense();
    }
  }

  void _recheckLicense() {
    unawaited(ref.read(licenseStatusProvider.notifier).refresh());
  }

  void _handleLicenseChanged(LicenseStatus? previous, LicenseStatus next) {
    final gated = next.isLocked || next.requiresActivation;
    if (!gated) {
      _licenseLockEnforced = false;
      return;
    }
    final wasGated =
        (previous?.isLocked ?? false) || (previous?.requiresActivation ?? false);
    if (wasGated) return;
    _enforceLicenseLock(next);
  }

  /// Logs out any active session and replaces the whole navigation stack
  /// with the gate screen — [ActivationScreen] while the install is
  /// unactivated, [LicenseLockedScreen] for an expired/tampered license.
  /// Runs even when nobody is logged in so the gate also covers the login
  /// screen itself.
  void _enforceLicenseLock(LicenseStatus status) {
    if (_licenseLockEnforced) return;
    _licenseLockEnforced = true;

    unawaited(() async {
      try {
        if (ref.read(authStateProvider).user != null) {
          await ref.read(authStateProvider.notifier).logout();
        }
      } finally {
        widget.navigatorKey.currentState?.pushAndRemoveUntil(
          status.requiresActivation
              ? ActivationScreen.route()
              : LicenseLockedScreen.route(),
          (_) => false,
        );
      }
    }());
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

  /// Shows the "Session Expiring" modal on the root navigator.
  ///
  /// The guard lives above the [Navigator] (it is the `MaterialApp.builder`
  /// wrapper), so the dialog must be pushed directly on
  /// [GlobalKey<NavigatorState>.currentState] — `Navigator.of` from the
  /// guard's own context cannot reach the navigator below it.
  ///
  /// The dialog is a pure view of the service's state: the countdown is
  /// computed from the absolute [SessionTimeoutService.inactivityDeadlineAt]
  /// and the service's own warning timer fires the actual timeout, so
  /// suspending/resuming the app cannot drift the countdown or strand the
  /// dialog. Any auth-phase navigation ([pushAndRemoveUntil]) removes the
  /// dialog route along with the rest of the stack.
  void _handleSessionWarning() {
    if (!mounted || _warningRoute != null) return;

    final navigator = widget.navigatorKey.currentState;
    final navigatorContext = widget.navigatorKey.currentContext;
    final deadline = _sessionTimeoutService.inactivityDeadlineAt;
    if (navigator == null || navigatorContext == null || deadline == null) {
      return;
    }

    final route = DialogRoute<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (_) => SessionExpiringDialog(
        deadline: deadline,
        warningDuration: _sessionTimeoutService.warningThreshold,
        onContinue: _sessionTimeoutService.continueSession,
        onLogout: _handleWarningLogout,
      ),
    );
    _warningRoute = route;
    unawaited(navigator.push(route).whenComplete(() {
      _warningRoute = null;
    }));
  }

  /// "Log Out" from the warning dialog — a full logout, not a PIN lock.
  /// Idempotent: [endSession] and the auth-phase navigation both tolerate
  /// being driven more than once.
  void _handleWarningLogout() {
    unawaited(_sessionTimeoutService.endSession());
    _pushAuthPhaseAndUpdate(
      AuthSessionPhase.unauthenticated,
      () => ref.read(authStateProvider.notifier).logout(),
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
          () => ref.read(authStateProvider.notifier).lockSession(),
        );
      } else {
        _pushAuthPhaseAndUpdate(
          AuthSessionPhase.unauthenticated,
          () => ref.read(authStateProvider.notifier).logout(),
        );
      }
      return;
    }

    // Already on a PIN or forced-change screen; treat as full logout.
    _pushAuthPhaseAndUpdate(
      AuthSessionPhase.unauthenticated,
      () => ref.read(authStateProvider.notifier).logout(),
    );
  }

  void _handleSessionExpired() {
    _pushAuthPhaseAndUpdate(
      AuthSessionPhase.unauthenticated,
      () => ref.read(authStateProvider.notifier).logout(),
    );
  }

  /// Settles `AuthState` first, then pushes the target auth-phase route.
  ///
  /// The order matters: the pushed screen and every auth listener (the
  /// `AppShell` redirect, the `PinLockScreen`/`ForceChangePasswordScreen`
  /// subscriptions, and `LoginScreen`'s self-redirect) must observe the new
  /// phase before the transition begins. Pushing first would let the new
  /// screen build under the previous user's still-authenticated state and
  /// could bounce (e.g. a fresh `LoginScreen` redirecting straight back to
  /// the dashboard). If [updateState] throws, the navigation still runs so
  /// the user is never stranded on an authenticated screen.
  void _pushAuthPhaseAndUpdate(
    AuthSessionPhase phase,
    Future<void> Function() updateState,
  ) {
    unawaited(() async {
      try {
        await updateState();
      } finally {
        widget.navigatorKey.currentState?.pushAndRemoveUntil(
          AuthPhaseNavigator.routeForPhase(phase),
          (_) => false,
        );
      }
    }());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
