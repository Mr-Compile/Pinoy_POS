import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:pinoy_pos/data/models/session_metadata.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/session_settings_service.dart';
import 'package:pinoy_pos/services/session_timeout_service.dart';

class _FakeAuthService extends AuthService {
  _FakeAuthService(this._metadata);

  SessionMetadata? _metadata;
  DateTime? lastTouched;

  @override
  SessionMetadata? get currentSessionMetadata => _metadata;

  @override
  Future<void> touchSession(DateTime lastActivityAt) async {
    lastTouched = lastActivityAt;
    _metadata = _metadata?.copyWith(lastActivityAt: lastActivityAt);
  }

  void setMetadata(SessionMetadata metadata) {
    _metadata = metadata;
  }
}

class _FakeSessionSettingsService extends SessionSettingsService {
  _FakeSessionSettingsService(this._timeout,
      {this._warning = Duration.zero});

  final Duration _timeout;
  final Duration _warning;

  @override
  Future<Duration> getEffectiveInactivityTimeout(User user) async => _timeout;

  @override
  Future<Duration> getEffectiveWarningThreshold(User user) async => _warning;
}

void main() {
  final user = User(
    id: 1,
    username: 'owner',
    passwordHash: 'hash',
    role: UserRole.owner,
    fullName: 'Owner',
    createdAt: DateTime.now(),
  );

  group('SessionTimeoutService', () {
    test('inactivity timer fires after the timeout', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 1));
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        expect(fired, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(fired, isTrue);
      });
    });

    test('userDidInteract resets the inactivity timer', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 1));
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        service.userDidInteract();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 40));
        expect(fired, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(fired, isTrue);
      });
    });

    test('absolute session timer fires when the hard limit is reached', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 2)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 5));
        bool expired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () {},
          onSessionExpired: () => expired = true,
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: false));
        async.flushMicrotasks();

        expect(expired, isFalse);
        async.elapse(const Duration(minutes: 2));
        expect(expired, isTrue);
      });
    });

    test('handleAppLifecycle resumed checks wall-clock inactivity', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 1));
        bool locked = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => locked = true,
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        final stale = now.subtract(const Duration(minutes: 2));
        unawaited(auth.touchSession(stale));
        async.flushMicrotasks();

        unawaited(service.handleAppLifecycle(AppLifecycleState.resumed));
        async.flushMicrotasks();

        expect(locked, isTrue);
      });
    });

    test('handleAppLifecycle resumed checks wall-clock hard expiry', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 1)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 5));
        bool expired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () {},
          onSessionExpired: () => expired = true,
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        // Advance time past the 8-hour hard limit.
        async.elapse(const Duration(minutes: 2));

        unawaited(service.handleAppLifecycle(AppLifecycleState.resumed));
        async.flushMicrotasks();

        expect(expired, isTrue);
      });
    });

    test('handleAppLifecycle paused persists the last activity time', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 1));

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () {},
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        unawaited(service.handleAppLifecycle(AppLifecycleState.paused));
        async.flushMicrotasks();

        expect(auth.lastTouched, isNotNull);
      });
    });

    test('endSession cancels timers and clears state', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(const Duration(minutes: 1));
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        unawaited(service.endSession());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 2));
        expect(fired, isFalse);
      });
    });

    test('warning fires at the threshold and timeout still fires at the '
        'deadline', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(
          const Duration(minutes: 1),
          warning: const Duration(seconds: 30),
        );
        bool warned = false;
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () => warned = true,
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        expect(service.isWarningActive, isFalse);
        expect(service.inactivityDeadlineAt, isNotNull);
        expect(service.warningThreshold, const Duration(seconds: 30));

        // Warning fires when 30 seconds remain.
        async.elapse(const Duration(seconds: 30));
        expect(warned, isTrue);
        expect(fired, isFalse);
        expect(service.isWarningActive, isTrue);

        // Timeout still fires at the full deadline.
        async.elapse(const Duration(seconds: 30));
        expect(fired, isTrue);
        expect(service.isWarningActive, isFalse);
      });
    });

    test('activity during the warning window does not reset the session', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(
          const Duration(minutes: 1),
          warning: const Duration(seconds: 30),
        );
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () {},
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        // Enter the warning window, then interact — the warning must stay
        // active and the deadline must not move.
        async.elapse(const Duration(seconds: 31));
        expect(service.isWarningActive, isTrue);

        service.userDidInteract();
        service.userDidInteract();
        async.elapse(const Duration(seconds: 10));
        service.userDidInteract();

        // The session still ends at the original deadline.
        async.elapse(const Duration(seconds: 20));
        expect(fired, isTrue);
      });
    });

    test('continueSession ends the warning and restores the full timeout',
        () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(
          const Duration(minutes: 1),
          warning: const Duration(seconds: 30),
        );
        int warnings = 0;
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () => warnings++,
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 31));
        expect(service.isWarningActive, isTrue);

        // Continuing at t=31 restores the full 60s timeout: new deadline
        // t=91, next warning at t=61.
        service.continueSession();
        expect(service.isWarningActive, isFalse);

        async.elapse(const Duration(seconds: 29)); // t=60
        expect(warnings, 1);
        expect(fired, isFalse);

        // The warning fires again only inside the new window.
        async.elapse(const Duration(seconds: 2)); // t=62
        expect(warnings, 2);
        expect(fired, isFalse);

        async.elapse(const Duration(seconds: 28)); // t=90
        expect(fired, isFalse);
        async.elapse(const Duration(seconds: 2)); // t=92 — past deadline
        expect(fired, isTrue);
      });
    });

    test('a zero warning threshold produces no warning phase', () {
      fakeAsync((async) {
        final now = clock.now();
        final metadata = SessionMetadata(
          userId: 1,
          sessionExpiresAt: now.add(const Duration(minutes: 10)),
          lastActivityAt: now,
          pinVerified: true,
        );
        final auth = _FakeAuthService(metadata);
        final settings = _FakeSessionSettingsService(
          const Duration(minutes: 1),
        );
        bool warned = false;
        bool fired = false;

        final service = SessionTimeoutService(
          authService: auth,
          sessionSettingsService: settings,
          onInactivityTimeout: () => fired = true,
          onSessionExpired: () {},
          onWarning: () => warned = true,
          clock: clock.now,
        );

        unawaited(service.startSession(user, resetActivity: true));
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 1));
        expect(warned, isFalse);
        expect(fired, isTrue);
      });
    });
  });
}
