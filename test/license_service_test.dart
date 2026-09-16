import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/services/license_service.dart';

/// In-memory [LicenseStore] so tests never touch platform channels.
class MemoryLicenseStore implements LicenseStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late MemoryLicenseStore stateStore;
  late MemoryLicenseStore markerStore;
  late DateTime now;
  late LicenseService service;

  LicenseService buildService() => LicenseService(
    stateStore: stateStore,
    markerStore: markerStore,
    clock: () => now,
  );

  /// Satisfies the activation gate so tests can exercise post-activation
  /// license states. Devices under test start unactivated — anything that
  /// asserts an active/inactive/expired state must call this first.
  Future<void> activate() async {
    final result = await service.redeemActivationCode(
      service.activationCode(),
    );
    assert(result.success);
  }

  setUp(() {
    stateStore = MemoryLicenseStore();
    markerStore = MemoryLicenseStore();
    now = DateTime(2026, 9, 14, 12, 0);
    service = buildService();
  });

  String? rawBlob() => stateStore.data['pinoy_pos.license_state.v1'];

  group('evaluate', () {
    test('requires activation on a fresh device', () async {
      final status = await service.evaluate();
      expect(status.state, LicenseLockState.activationRequired);
      expect(status.requiresActivation, isTrue);
      expect(status.isLocked, isFalse);
    });

    test('armed with a future deadline is active and not locked', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
        message: 'Pay up',
        contactInfo: 'Dev 0917',
      );
      await activate();

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.active);
      expect(status.isLocked, isFalse);
      expect(status.message, 'Pay up');
      expect(status.contactInfo, 'Dev 0917');
      expect(status.remaining!.inDays, greaterThanOrEqualTo(29));
    });

    test('armed past the deadline is expired and locked', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      await activate();

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.expired);
      expect(status.isLocked, isTrue);
    });

    test(
      'expires mid-window when the clock advances past the deadline',
      () async {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(hours: 1)),
        );
        await activate();
        now = now.add(const Duration(hours: 2));

        final status = await service.evaluate();
        expect(status.state, LicenseLockState.expired);
        expect(status.isLocked, isTrue);
      },
    );

    test('disarmed config is inactive even past a stored deadline', () async {
      await service.saveConfig(
        armed: false,
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      await activate();

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.inactive);
      expect(status.isLocked, isFalse);
    });
  });

  group('expiry warning', () {
    test('isExpiringSoon inside the proportional warning window', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      // 30-day term → the warning appears only in the last ~7.5 days.
      expect((await service.evaluate()).isExpiringSoon, isFalse);

      now = now.add(const Duration(days: 23)); // 7 days remain
      expect((await service.evaluate()).isExpiringSoon, isTrue);
    });

    test('a 30-day license warns for a quarter of its term', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      final status = await service.evaluate();
      expect(status.warningThreshold, const Duration(days: 7, hours: 12));
      expect(status.isExpiringSoon, isFalse);
    });

    test('warning threshold is capped at 30 days for long terms', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 365)),
      );
      await activate();
      final status = await service.evaluate();
      expect(status.warningThreshold, LicenseService.warningWindow);
      expect(status.isExpiringSoon, isFalse);
    });

    test('very short licenses warn for at least a day', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 2)),
      );
      await activate();
      var status = await service.evaluate();
      expect(status.warningThreshold, const Duration(days: 1));
      expect(status.isExpiringSoon, isFalse); // 2 days remain

      now = now.add(const Duration(hours: 25)); // 23 hours remain
      status = await service.evaluate();
      expect(status.isExpiringSoon, isTrue);
    });

    test('a status without armedAt falls back to the 30-day window', () async {
      final status = LicenseStatus(
        state: LicenseLockState.active,
        effectiveNow: now,
        expiresAt: now.add(const Duration(days: 60)),
      );
      expect(status.totalTerm, isNull);
      expect(status.warningThreshold, LicenseService.warningWindow);
      expect(status.isTrial, isFalse);
    });

    test('isExpiringSoon is false outside the warning window', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 45)),
      );
      await activate();
      expect((await service.evaluate()).isExpiringSoon, isFalse);
    });

    test('expired and inactive states never report a warning', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      await activate();
      expect((await service.evaluate()).isExpiringSoon, isFalse);

      await service.saveConfig(
        armed: false,
        expiresAt: now.add(const Duration(days: 3)),
      );
      expect((await service.evaluate()).isExpiringSoon, isFalse);
    });
  });

  group('license term', () {
    test('arming records the term start and computes the term', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      final status = await service.evaluate();
      expect(status.armedAt, now);
      expect(status.totalTerm, const Duration(days: 30));
      expect(status.isTrial, isTrue);
    });

    test('re-saving the same deadline keeps the original term start', () async {
      final expiry = now.add(const Duration(days: 30));
      await service.saveConfig(armed: true, expiresAt: expiry);
      await activate();
      final armedAt = (await service.evaluate()).armedAt;

      now = now.add(const Duration(days: 1));
      final status = await service.saveConfig(
        armed: true,
        expiresAt: expiry,
        message: 'updated',
      );
      expect(status.armedAt, armedAt);
      expect(status.totalTerm, const Duration(days: 30));
    });

    test('a new deadline starts a new term', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();

      now = now.add(const Duration(days: 10));
      final status = await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 90)),
      );
      expect(status.armedAt, now);
      expect(status.totalTerm, const Duration(days: 90));
      expect(status.isTrial, isFalse);
    });

    test('disarming clears the term start', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      final status = await service.saveConfig(armed: false);
      expect(status.armedAt, isNull);
      expect(status.totalTerm, isNull);
    });

    test('redeeming a code starts a new term', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      now = now.add(const Duration(days: 28)); // 2 days left — warning on
      expect((await service.evaluate()).isExpiringSoon, isTrue);

      final result = await service.redeemUnlockCode(service.unlockCode(90, 0));
      expect(result.success, isTrue);

      final status = await service.evaluate();
      expect(status.armedAt, now);
      expect(status.isTrial, isFalse);
      expect(status.isExpiringSoon, isFalse);
      expect(status.showCountdown, isTrue);
    });

    test('showCountdown is false once the warning window opens', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      expect((await service.evaluate()).showCountdown, isTrue);

      now = now.add(const Duration(days: 28)); // inside the window
      final status = await service.evaluate();
      expect(status.isExpiringSoon, isTrue);
      expect(status.showCountdown, isFalse);
    });
  });

  group('clock rollback defence', () {
    test('rolling the clock back does not undo an expiry', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      await activate();

      // Time passes: watermark advances past the deadline.
      now = now.add(const Duration(hours: 2));
      expect((await service.evaluate()).isLocked, isTrue);

      // Client rolls the device clock back to before the deadline.
      now = DateTime(2026, 9, 14, 12, 0);
      final status = await service.evaluate();
      expect(status.state, LicenseLockState.expired);
      expect(status.isLocked, isTrue);
      // Effective time stays at the watermark, not the rolled-back clock.
      expect(status.effectiveNow.isAfter(now), isTrue);
    });

    test(
      'a rolled-back clock cannot revive an about-to-expire license',
      () async {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 30)),
        );
        await activate();

        // Advance real time to just before expiry — watermark follows.
        now = now.add(const Duration(days: 29));
        await service.evaluate();

        // Client rolls the clock back to install day.
        now = DateTime(2026, 9, 14, 12, 0);
        final status = await service.evaluate();

        // Still nearly expired — remaining is measured from the watermark.
        expect(status.state, LicenseLockState.active);
        expect(status.remaining!.inDays, lessThanOrEqualTo(1));
      },
    );
  });

  group('tamper detection', () {
    test('editing the stored blob fails the signature and locks', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );

      final decoded = jsonDecode(rawBlob()!) as Map<String, Object?>;
      final data = (decoded['data'] as Map).cast<String, Object?>();
      data['armed'] = false; // client tries to disarm by editing storage
      decoded['data'] = data;
      stateStore.data['pinoy_pos.license_state.v1'] = jsonEncode(decoded);

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.tampered);
      expect(status.isLocked, isTrue);
    });

    test('deleting the blob while the marker survives locks', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await stateStore.delete('pinoy_pos.license_state.v1');

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.tampered);
      expect(status.isLocked, isTrue);
    });

    test('a forged unsigned blob locks', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      stateStore.data['pinoy_pos.license_state.v1'] = jsonEncode({
        'data': {'armed': false},
        'sig': 'deadbeef',
      });

      expect((await service.evaluate()).state, LicenseLockState.tampered);
    });
  });

  group('developer password', () {
    test('activated device offers setup, then verifies', () async {
      await activate();
      expect(await service.developerGateMode(), DevGateMode.setup);

      expect(await service.initializeDeveloperPassword('devpass123'), isTrue);
      expect(await service.developerGateMode(), DevGateMode.verify);

      final ok = await service.verifyDeveloperPassword('devpass123');
      expect(ok.result, DevAuthResult.ok);
    });

    test('initialize is refused once a password exists', () async {
      await activate();
      await service.initializeDeveloperPassword('devpass123');
      expect(await service.initializeDeveloperPassword('other'), isFalse);
    });

    test('wrong password reports incorrect', () async {
      await activate();
      await service.initializeDeveloperPassword('devpass123');
      final res = await service.verifyDeveloperPassword('nope');
      expect(res.result, DevAuthResult.incorrect);
    });

    test('five wrong attempts trigger a lockout window', () async {
      await activate();
      await service.initializeDeveloperPassword('devpass123');
      for (var i = 0; i < 5; i++) {
        await service.verifyDeveloperPassword('wrong$i');
      }
      final res = await service.verifyDeveloperPassword('devpass123');
      expect(res.result, DevAuthResult.lockedOut);
      expect(res.retryAfter, isNotNull);
    });

    test('lockout clears after the window passes', () async {
      await activate();
      await service.initializeDeveloperPassword('devpass123');
      for (var i = 0; i < 5; i++) {
        await service.verifyDeveloperPassword('wrong$i');
      }
      now = now.add(const Duration(minutes: 6));
      final res = await service.verifyDeveloperPassword('devpass123');
      expect(res.result, DevAuthResult.ok);
    });

    test('changing the password requires the current one', () async {
      await activate();
      await service.initializeDeveloperPassword('devpass123');

      final bad = await service.changeDeveloperPassword('wrong', 'newpass1');
      expect(bad.isOk, isFalse);

      final good = await service.changeDeveloperPassword(
        'devpass123',
        'newpass1',
      );
      expect(good.isOk, isTrue);
      expect(
        (await service.verifyDeveloperPassword('newpass1')).result,
        DevAuthResult.ok,
      );
    });

    test('tampered state blocks developer access entirely', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      await stateStore.delete('pinoy_pos.license_state.v1');
      expect(await service.developerGateMode(), DevGateMode.blocked);
    });
  });

  group('unlock codes', () {
    test('codes have the expected XXXX-XXXX format and are stable', () {
      final code = service.unlockCode(90, 0);
      expect(code, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
      expect(service.unlockCode(90, 0), code);
      expect(service.unlockCode(90, 1), isNot(code));
      expect(service.unlockCode(365, 0), isNot(code));
    });

    test('every code in every grant redeems', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      for (final grant in LicenseService.unlockGrants.entries) {
        for (var i = 0; i < grant.value; i++) {
          final code = service.unlockCode(grant.key, i);
          expect(
            code,
            matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')),
            reason: 'grant ${grant.key} index $i is malformed',
          );
          // Actually redeem it — a colliding code would come back as
          // alreadyUsed instead of success.
          final result = await service.redeemUnlockCode(code);
          expect(
            result.success,
            isTrue,
            reason: 'grant ${grant.key} index $i failed to redeem',
          );
        }
      }
    });

    test('a code redeems only once', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      final code = service.unlockCode(30, 0);

      final first = await service.redeemUnlockCode(code);
      expect(first.success, isTrue);
      expect(first.daysGranted, 30);
      expect((await service.evaluate()).isCodeRedeemed(30, 0), isTrue);

      final second = await service.redeemUnlockCode(code);
      expect(second.success, isFalse);
      expect(second.alreadyUsed, isTrue);
    });

    test('a spent code stays spent after the blob is deleted', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      final code = service.unlockCode(30, 0);
      expect((await service.redeemUnlockCode(code)).success, isTrue);

      // Client deletes the secure blob — the marker survives, so
      // redemption into a fresh config is allowed, but the mirrored
      // redeemed list still blocks the spent code.
      await stateStore.delete('pinoy_pos.license_state.v1');
      expect((await service.evaluate()).state, LicenseLockState.tampered);

      final result = await service.redeemUnlockCode(code);
      expect(result.success, isFalse);
      expect(result.alreadyUsed, isTrue);
    });

    test('other codes still redeem after one is spent', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      expect(
        (await service.redeemUnlockCode(service.unlockCode(30, 0))).success,
        isTrue,
      );
      expect(
        (await service.redeemUnlockCode(service.unlockCode(30, 1))).success,
        isTrue,
      );
    });

    test('a valid code extends the license and unlocks the app', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      await activate();
      expect((await service.evaluate()).isLocked, isTrue);

      final code = service.unlockCode(90, 0);
      final result = await service.redeemUnlockCode(code);

      expect(result.success, isTrue);
      expect(result.daysGranted, 90);
      expect(result.newExpiry!.isAfter(now), isTrue);
      expect((await service.evaluate()).state, LicenseLockState.active);
    });

    test('redeeming before the deadline stacks on top of it', () async {
      final deadline = now.add(const Duration(days: 10));
      await service.saveConfig(armed: true, expiresAt: deadline);

      final result = await service.redeemUnlockCode(service.unlockCode(90, 0));

      expect(result.success, isTrue);
      // 10 remaining days + 90 granted = ~100 days, not 90.
      expect(
        result.newExpiry!.millisecondsSinceEpoch,
        deadline.add(const Duration(days: 90)).millisecondsSinceEpoch,
      );
      final status = await service.evaluate();
      expect(status.state, LicenseLockState.active);
      expect(status.remaining!.inDays, greaterThanOrEqualTo(99));
    });

    test('redeeming after the deadline extends from now', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(days: 2)),
      );

      final result = await service.redeemUnlockCode(service.unlockCode(365, 0));

      expect(result.success, isTrue);
      expect(
        result.newExpiry!.isAfter(now.add(const Duration(days: 364))),
        isTrue,
      );
    });

    test('a code cannot re-arm a disarmed (paid in full) license', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await activate();
      await service.saveConfig(armed: false, expiresAt: null);

      final result = await service.redeemUnlockCode(service.unlockCode(90, 0));
      expect(result.success, isFalse);
      expect((await service.evaluate()).state, LicenseLockState.inactive);
    });

    test('codes tolerate lowercase input and the dash separator', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      final code = service.unlockCode(90, 3).toLowerCase();
      expect((await service.redeemUnlockCode(code)).success, isTrue);
    });

    test('an invalid code is rejected', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      await activate();
      final result = await service.redeemUnlockCode('AAAA-BBBB');
      expect(result.success, isFalse);
      expect((await service.evaluate()).isLocked, isTrue);
    });

    test(
      'redemption works after the blob was deleted (tamper recovery)',
      () async {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 1)),
        );
        await stateStore.delete('pinoy_pos.license_state.v1');
        expect((await service.evaluate()).state, LicenseLockState.tampered);

        final result = await service.redeemUnlockCode(
          service.unlockCode(90, 0),
        );
        expect(result.success, isTrue);
        expect((await service.evaluate()).state, LicenseLockState.active);
      },
    );

    test('redemption on a never-configured device is refused', () async {
      final result = await service.redeemUnlockCode(service.unlockCode(90, 0));
      expect(result.success, isFalse);
    });

    test('repeated wrong codes hit the shared lockout', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(hours: 1)),
      );
      for (var i = 0; i < 5; i++) {
        await service.redeemUnlockCode('BAD0-COD$i');
      }
      final res = await service.redeemUnlockCode(service.unlockCode(90, 0));
      expect(res.success, isFalse);
      expect(res.retryAfter, isNotNull);
    });
  });

  group('clearConfiguration', () {
    test('returns the device to the activation gate', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      await service.clearConfiguration();

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.activationRequired);
      expect(status.isLocked, isFalse);
      expect(await service.developerGateMode(), DevGateMode.blocked);
    });

    test('clears the redeemed-code record like a fresh install', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      final code = service.unlockCode(30, 0);
      expect((await service.redeemUnlockCode(code)).success, isTrue);

      await service.clearConfiguration();
      await service.saveConfig(armed: true, expiresAt: now);

      final result = await service.redeemUnlockCode(code);
      expect(result.success, isTrue);
      expect(result.alreadyUsed, isFalse);
    });
  });

  group('activity log', () {
    test('arming records an armed event with the term length', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 90)),
      );

      final events = (await service.evaluate()).events;
      expect(events, hasLength(1));
      expect(events.single.type, LicenseEventType.armed);
      expect(events.single.detail, '90-day term');
    });

    test(
      're-saving the same armed deadline does not duplicate the event',
      () async {
        final expiresAt = now.add(const Duration(days: 30));
        await service.saveConfig(armed: true, expiresAt: expiresAt);
        await service.saveConfig(armed: true, expiresAt: expiresAt);

        final events = (await service.evaluate()).events;
        expect(
          events.where((e) => e.type == LicenseEventType.armed),
          hasLength(1),
        );
      },
    );

    test(
      'disarming and re-arming record both transitions, newest first',
      () async {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 30)),
        );
        await service.saveConfig(armed: false);
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 60)),
        );

        final events = (await service.evaluate()).events;
        expect(events.map((e) => e.type), [
          LicenseEventType.armed,
          LicenseEventType.disarmed,
          LicenseEventType.armed,
        ]);
      },
    );

    test('redeeming a code records a redeemed event with the grant', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      await service.redeemUnlockCode(service.unlockCode(30, 0));

      final events = (await service.evaluate()).events;
      expect(events.first.type, LicenseEventType.redeemed);
      expect(events.first.detail, '+30 days');
    });

    test('password set and change are recorded', () async {
      await activate();
      expect(await service.initializeDeveloperPassword('Str0ng!Pass'), isTrue);
      expect(
        (await service.changeDeveloperPassword(
          'Str0ng!Pass',
          'N3w!Passw0rd',
        )).isOk,
        isTrue,
      );

      final types = (await service.evaluate()).events
          .map((e) => e.type)
          .toList();
      expect(types, [
        LicenseEventType.passwordChanged,
        LicenseEventType.passwordSet,
        LicenseEventType.activated,
      ]);
    });

    test(
      'evaluate() never writes events — the log only grows on actions',
      () async {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 30)),
        );
        await service.evaluate();
        await service.evaluate();
        now = now.add(const Duration(minutes: 5));
        await service.evaluate();

        expect((await service.evaluate()).events, hasLength(1));
      },
    );

    test('events survive a service restart over the same stores', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      final restarted = buildService();

      final events = (await restarted.evaluate()).events;
      expect(events.single.type, LicenseEventType.armed);
    });

    test('the log is capped and drops the oldest entries', () async {
      // 15 arm/disarm pairs → 30 events; the cap keeps the newest 25.
      for (var i = 0; i < 15; i++) {
        await service.saveConfig(
          armed: true,
          expiresAt: now.add(const Duration(days: 30)),
        );
        await service.saveConfig(armed: false);
      }

      final events = (await service.evaluate()).events;
      expect(events, hasLength(25));
      expect(events.first.type, LicenseEventType.disarmed);
      expect(events.last.type, LicenseEventType.disarmed);
    });

    test('a tampered blob exposes no activity', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      final raw = rawBlob()!;
      stateStore.data['pinoy_pos.license_state.v1'] = raw.replaceFirst(
        '"armed":true',
        '"armed":false',
      );

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.tampered);
      expect(status.events, isEmpty);
    });

    test('clearConfiguration wipes the log like a fresh install', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await service.clearConfiguration();

      expect((await service.evaluate()).events, isEmpty);
    });
  });

  group('activation', () {
    test('master code is stable, formatted, and distinct from grants', () {
      final code = service.activationCode();
      expect(code, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
      expect(service.activationCode(), code);
      expect(code, isNot(service.unlockCode(30, 0)));
    });

    test('the master code activates a fresh install', () async {
      final result = await service.redeemActivationCode(
        service.activationCode(),
      );
      expect(result.success, isTrue);

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.inactive);
      expect(status.requiresActivation, isFalse);
      expect(status.events.single.type, LicenseEventType.activated);
    });

    test('the code tolerates lowercase input and the dash', () async {
      final result = await service.redeemActivationCode(
        service.activationCode().toLowerCase(),
      );
      expect(result.success, isTrue);
    });

    test(
      'a wrong code keeps the gate closed and persists the failure',
      () async {
        final result = await service.redeemActivationCode('AAAA-BBBB');
        expect(result.success, isFalse);

        // The bookkeeping blob exists — but activated:false keeps the
        // device gated.
        expect(rawBlob(), isNotNull);
        expect(
          (await service.evaluate()).state,
          LicenseLockState.activationRequired,
        );
      },
    );

    test('five wrong attempts lock out further tries', () async {
      for (var i = 0; i < 5; i++) {
        await service.redeemActivationCode('BAD0-COD$i');
      }
      final res = await service.redeemActivationCode(
        service.activationCode(),
      );
      expect(res.success, isFalse);
      expect(res.retryAfter, isNotNull);
    });

    test('activation preserves an already-armed license', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      expect(
        (await service.evaluate()).state,
        LicenseLockState.activationRequired,
      );

      await activate();
      expect((await service.evaluate()).state, LicenseLockState.active);
    });

    test('a wiped device returns to the gate', () async {
      await activate();
      await service.clearConfiguration();
      expect(
        (await service.evaluate()).state,
        LicenseLockState.activationRequired,
      );
    });

    test('a legacy blob without the activated key is grandfathered', () async {
      await service.saveConfig(armed: false);

      // Strip the key and re-sign — exactly what a pre-feature build
      // stored on devices already in the field.
      final decoded = jsonDecode(rawBlob()!) as Map<String, Object?>;
      final data = (decoded['data'] as Map).cast<String, Object?>()
        ..remove('activated');
      decoded['sig'] = LicenseService.signPayloadForTest(data);
      stateStore.data['pinoy_pos.license_state.v1'] = jsonEncode(decoded);

      final status = await service.evaluate();
      expect(status.state, LicenseLockState.inactive);
      expect(status.requiresActivation, isFalse);
    });

    test('setting a developer password cannot sidestep activation', () async {
      // The panel is blocked while gated — no password setup, no access.
      expect(await service.developerGateMode(), DevGateMode.blocked);
      expect(
        await service.initializeDeveloperPassword('devpass123'),
        isFalse,
      );
      expect(
        (await service.evaluate()).state,
        LicenseLockState.activationRequired,
      );
    });

    test('saving a config cannot sidestep activation', () async {
      await service.saveConfig(
        armed: true,
        expiresAt: now.add(const Duration(days: 30)),
      );
      expect(
        (await service.evaluate()).state,
        LicenseLockState.activationRequired,
      );
    });

    test('an unlock code redemption also activates the device', () async {
      await service.saveConfig(armed: true, expiresAt: now);
      expect(
        (await service.evaluate()).state,
        LicenseLockState.activationRequired,
      );

      final result = await service.redeemUnlockCode(service.unlockCode(30, 0));
      expect(result.success, isTrue);
      expect((await service.evaluate()).state, LicenseLockState.active);
    });
  });
}
