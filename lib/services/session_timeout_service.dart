import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/session_settings_service.dart';

/// Runs the inactivity and absolute session expiry timers.
///
/// This service is intentionally UI-agnostic.  It is driven by a root-level
/// [SessionGuard] which provides user input events and app lifecycle changes.
/// When a timeout fires, the service calls one of the supplied callbacks so
/// the UI can navigate to the correct screen.
///
/// Session timeline:
///
///     last activity ─────────── warning point ────────── inactivity deadline
///                     (idle)    │               │        │
///                               onWarning()     countdown expires
///                               fires once      -> onInactivityTimeout()
///
/// While the warning is active, incidental input is ignored — the user must
/// explicitly choose "Continue Session" ([continueSession]) or "Log Out".
/// All timers are derived from absolute timestamps ([_lastActivityAt] +
/// [_inactivityTimeout]), so suspension and resume cannot drift the
/// countdown.
class SessionTimeoutService {
  SessionTimeoutService({
    required this.authService,
    required this.sessionSettingsService,
    required this.onInactivityTimeout,
    required this.onSessionExpired,
    required this.onWarning,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AuthService authService;
  final SessionSettingsService sessionSettingsService;
  final void Function() onInactivityTimeout;
  final void Function() onSessionExpired;

  /// Fired once when the session enters the warning window — the last
  /// `warningThreshold` before the inactivity deadline. The UI shows the
  /// "Session Expiring" modal. The service then arms [_warningTimer] which
  /// fires [onInactivityTimeout] at the deadline.
  final void Function() onWarning;

  final DateTime Function() _clock;

  User? _user;
  Duration _inactivityTimeout = const Duration(minutes: 15);
  Duration _warningThreshold = Duration.zero;
  DateTime? _lastActivityAt;
  DateTime? _sessionExpiresAt;
  Timer? _inactivityTimer;
  Timer? _warningTimer;
  Timer? _absoluteTimer;
  DateTime? _lastPersistedAt;
  bool _warningActive = false;

  /// Whether the session is currently inside the warning window.
  bool get isWarningActive => _warningActive;

  /// The configured warning-window length — the effective
  /// `session_warning_seconds` clamped below the inactivity timeout. The
  /// warning countdown runs from this duration down to zero at
  /// [inactivityDeadlineAt].
  Duration get warningThreshold => _warningThreshold;

  /// The absolute moment the inactivity deadline is reached (the moment the
  /// warning countdown hits zero). Null when no session is running.
  DateTime? get inactivityDeadlineAt =>
      _lastActivityAt?.add(_inactivityTimeout);

  /// Starts or resumes the session timer for [user].
  ///
  /// When [resetActivity] is true, `lastActivityAt` is set to now. This is
  /// used when the user has just landed on a PIN/change screen so they get
  /// a fresh inactivity window. When false, the persisted timestamp is used.
  Future<void> startSession(User user, {required bool resetActivity}) async {
    _user = user;
    _inactivityTimeout = await sessionSettingsService.getEffectiveInactivityTimeout(user);
    _warningThreshold =
        await sessionSettingsService.getEffectiveWarningThreshold(user);
    _sessionExpiresAt = authService.currentSessionMetadata?.sessionExpiresAt;
    _lastActivityAt = resetActivity
        ? _clock()
        : authService.currentSessionMetadata?.lastActivityAt ?? _clock();
    _lastPersistedAt = _clock();
    await authService.touchSession(_lastActivityAt!);
    _startTimers();
  }

  /// Resets the inactivity clock. Call on every user input.
  ///
  /// Ignored while the warning window is active — during the countdown the
  /// user must explicitly choose "Continue Session" or "Log Out"; stray
  /// taps, scrolls, and key presses do not silently extend the session.
  void userDidInteract() {
    if (_user == null || _warningActive) return;
    _lastActivityAt = _clock();
    _restartInactivityTimer();

    final now = _clock();
    final shouldPersist = _lastPersistedAt == null ||
        now.difference(_lastPersistedAt!) > const Duration(seconds: 10);
    if (shouldPersist) {
      _lastPersistedAt = now;
      unawaited(authService.touchSession(_lastActivityAt!));
    }
  }

  /// Explicit "Continue Session" action from the warning dialog.
  ///
  /// Ends the warning window, resets the inactivity clock to the full
  /// configured timeout, and persists the new activity timestamp.
  void continueSession() {
    if (_user == null) return;
    _warningActive = false;
    _warningTimer?.cancel();
    _warningTimer = null;
    _lastActivityAt = _clock();
    _lastPersistedAt = _clock();
    unawaited(authService.touchSession(_lastActivityAt!));
    _restartInactivityTimer();
  }

  /// Called when the app changes lifecycle state.
  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    if (_user == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        await _handleResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _cancelTimers();
        await authService.touchSession(_lastActivityAt ?? _clock());
        _lastPersistedAt = _clock();
    }
  }

  /// Stops all timers and clears state.
  Future<void> endSession() async {
    _cancelTimers();
    _user = null;
    _lastActivityAt = null;
    _sessionExpiresAt = null;
    _lastPersistedAt = null;
  }

  void _startTimers() {
    _cancelTimers();
    _restartInactivityTimer();
    _restartAbsoluteTimer();
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    final remaining = _remainingInactivity();
    if (remaining <= Duration.zero) {
      _handleInactivityTimeout();
      return;
    }

    // If we are already inside the warning window (e.g. on resume), enter
    // the warning phase immediately; otherwise arm a timer that fires when
    // the warning window begins.
    final warningDelay = remaining - _warningThreshold;
    if (warningDelay > Duration.zero) {
      _inactivityTimer = Timer(warningDelay, _handleWarningStart);
    } else {
      _handleWarningStart();
    }
  }

  /// Enters the warning phase: fires [onWarning] once and arms the final
  /// countdown timer that ends the session at the inactivity deadline.
  void _handleWarningStart() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    final remaining = _remainingInactivity();
    if (remaining <= Duration.zero) {
      _handleInactivityTimeout();
      return;
    }

    if (_warningThreshold <= Duration.zero) {
      // No warning configured for this effective timeout.
      _handleInactivityTimeoutAtDeadline(remaining);
      return;
    }

    if (!_warningActive) {
      _warningActive = true;
      onWarning();
    }

    _warningTimer?.cancel();
    _warningTimer = Timer(remaining, _handleInactivityTimeout);
  }

  /// Arms the final countdown without a warning (used when the configured
  /// warning threshold is zero, i.e. no warning window exists).
  void _handleInactivityTimeoutAtDeadline(Duration remaining) {
    _warningTimer?.cancel();
    _warningTimer = Timer(remaining, _handleInactivityTimeout);
  }

  void _restartAbsoluteTimer() {
    _absoluteTimer?.cancel();
    final expiresAt = _sessionExpiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(_clock());
    if (remaining <= Duration.zero) {
      onSessionExpired();
      return;
    }
    _absoluteTimer = Timer(remaining, _handleSessionExpired);
  }

  Duration _remainingInactivity() {
    final lastActivity = _lastActivityAt;
    if (lastActivity == null) return _inactivityTimeout;
    final remaining = _inactivityTimeout - _clock().difference(lastActivity);
    return remaining;
  }

  Future<void> _handleResumed() async {
    final user = _user;
    final metadata = authService.currentSessionMetadata;
    if (user == null || metadata == null) return;

    final now = _clock();
    _sessionExpiresAt = metadata.sessionExpiresAt;
    _lastActivityAt = metadata.lastActivityAt;

    if (now.isAfter(_sessionExpiresAt!)) {
      onSessionExpired();
      return;
    }

    final inactivityExpired =
        now.difference(_lastActivityAt!) > _inactivityTimeout;
    if (inactivityExpired) {
      onInactivityTimeout();
      return;
    }

    _startTimers();
  }

  void _handleInactivityTimeout() {
    _cancelTimers();
    onInactivityTimeout();
  }

  void _handleSessionExpired() {
    _cancelTimers();
    onSessionExpired();
  }

  void _cancelTimers() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _warningTimer?.cancel();
    _warningTimer = null;
    _absoluteTimer?.cancel();
    _absoluteTimer = null;
    _warningActive = false;
  }
}
