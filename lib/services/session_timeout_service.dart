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
class SessionTimeoutService {
  SessionTimeoutService({
    required this.authService,
    required this.sessionSettingsService,
    required this.onInactivityTimeout,
    required this.onSessionExpired,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AuthService authService;
  final SessionSettingsService sessionSettingsService;
  final void Function() onInactivityTimeout;
  final void Function() onSessionExpired;
  final DateTime Function() _clock;

  User? _user;
  Duration _inactivityTimeout = const Duration(minutes: 15);
  DateTime? _lastActivityAt;
  DateTime? _sessionExpiresAt;
  Timer? _inactivityTimer;
  Timer? _absoluteTimer;
  DateTime? _lastPersistedAt;

  /// Starts or resumes the session timer for [user].
  ///
  /// When [resetActivity] is true, `lastActivityAt` is set to now. This is
  /// used when the user has just landed on a PIN/change screen so they get
  /// a fresh inactivity window. When false, the persisted timestamp is used.
  Future<void> startSession(User user, {required bool resetActivity}) async {
    _user = user;
    _inactivityTimeout = await sessionSettingsService.getEffectiveInactivityTimeout(user);
    _sessionExpiresAt = authService.currentSessionMetadata?.sessionExpiresAt;
    _lastActivityAt = resetActivity
        ? _clock()
        : authService.currentSessionMetadata?.lastActivityAt ?? _clock();
    _lastPersistedAt = _clock();
    await authService.touchSession(_lastActivityAt!);
    _startTimers();
  }

  /// Resets the inactivity clock. Call on every user input.
  void userDidInteract() {
    if (_user == null) return;
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
    final remaining = _remainingInactivity();
    if (remaining <= Duration.zero) {
      onInactivityTimeout();
      return;
    }
    _inactivityTimer = Timer(remaining, _handleInactivityTimeout);
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
    _absoluteTimer?.cancel();
    _absoluteTimer = null;
  }
}
