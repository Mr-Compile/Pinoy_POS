import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal key-value storage adapter so [LicenseService] stays testable
/// without platform channels.
abstract class LicenseStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [LicenseStore] backed by [flutter_secure_storage] (Keystore/DPAPI
/// encrypted). This is where the signed license blob lives — unlike the
/// SQLite database or plain SharedPreferences, the client cannot casually
/// open and edit it.
class SecureLicenseStore implements LicenseStore {
  SecureLicenseStore([SecureStorageService? storage])
    : _storage = storage ?? SecureStorageService();

  final SecureStorageService _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// [LicenseStore] backed by [SharedPreferences]. Used only for the
/// "configured" marker — a second storage location so that deleting the
/// secure blob alone still trips the tamper path.
class SharedPrefsLicenseStore implements LicenseStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// Lifecycle of the developer license lock.
enum LicenseLockState {
  /// State is still being read from storage.
  evaluating,

  /// The feature has never been configured on this device.
  notConfigured,

  /// Configured but not armed — no enforcement.
  inactive,

  /// Armed and within the license window.
  active,

  /// Armed and the deadline has passed — the app is locked.
  expired,

  /// Stored state failed its integrity check (edited or deleted while the
  /// configured marker survives) — the app is locked.
  tampered,
}

/// Which gate the developer access dialog should present.
enum DevGateMode {
  /// No password exists yet — offer "create password" fields.
  setup,

  /// A password exists — ask for it.
  verify,

  /// The stored state is untrusted — only an unlock code can proceed.
  blocked,
}

/// Result of a developer password attempt.
enum DevAuthResult { ok, incorrect, lockedOut, notSet, denied }

class DevAuthResponse {
  const DevAuthResponse({required this.result, this.retryAfter});

  final DevAuthResult result;
  final Duration? retryAfter;

  bool get isOk => result == DevAuthResult.ok;
}

/// License lifecycle events persisted inside the signed blob.
///
/// [warning] and [expired] are never stored — the owner status screen
/// derives them from the deadline so they cannot be forged by replaying
/// or editing the blob.
enum LicenseEventType {
  armed,
  disarmed,
  redeemed,
  passwordSet,
  passwordChanged,
  warning,
  expired,
}

/// One entry in the signed license activity log.
class LicenseEvent {
  const LicenseEvent({required this.type, required this.at, this.detail = ''});

  final LicenseEventType type;
  final DateTime at;

  /// Short human-readable context, e.g. `'90-day term'` or `'+30 days'`.
  final String detail;
}

/// Result of redeeming an unlock code on the lock screen.
class LicenseRedeemResult {
  const LicenseRedeemResult._({
    required this.success,
    this.alreadyUsed = false,
    this.daysGranted,
    this.newExpiry,
    this.retryAfter,
  });

  factory LicenseRedeemResult.success({
    required int daysGranted,
    required DateTime newExpiry,
  }) => LicenseRedeemResult._(
    success: true,
    daysGranted: daysGranted,
    newExpiry: newExpiry,
  );

  factory LicenseRedeemResult.invalid() =>
      const LicenseRedeemResult._(success: false);

  factory LicenseRedeemResult.alreadyUsed() =>
      const LicenseRedeemResult._(success: false, alreadyUsed: true);

  factory LicenseRedeemResult.lockedOut(Duration retryAfter) =>
      LicenseRedeemResult._(success: false, retryAfter: retryAfter);

  final bool success;

  /// The code is genuine but was redeemed before on this device — codes
  /// are single-use.
  final bool alreadyUsed;
  final int? daysGranted;
  final DateTime? newExpiry;
  final Duration? retryAfter;
}

/// Snapshot of the evaluated license state, exposed to the UI.
class LicenseStatus {
  const LicenseStatus({
    required this.state,
    required this.effectiveNow,
    this.expiresAt,
    this.armedAt,
    this.message = '',
    this.contactInfo = '',
    this.hasDeveloperPassword = false,
    this.redeemedCodes = const <String>{},
    this.events = const <LicenseEvent>[],
  });

  factory LicenseStatus.evaluating() => LicenseStatus(
    state: LicenseLockState.evaluating,
    effectiveNow: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final LicenseLockState state;

  /// Monotonic "now" used for the expiry check — never moves backwards even
  /// if the device clock is rolled back.
  final DateTime effectiveNow;

  final DateTime? expiresAt;

  /// When the current armed term began. Null for legacy blobs written
  /// before term tracking existed — those fall back to the full
  /// [LicenseService.warningWindow].
  final DateTime? armedAt;

  final String message;
  final String contactInfo;
  final bool hasDeveloperPassword;

  /// Unlock codes already redeemed on this device (`'<days>:<index>'`).
  /// Codes are single-use — the developer panel marks these as spent.
  final Set<String> redeemedCodes;

  /// Signed license activity log, newest first. Read-only and surfaced
  /// only in the hidden developer panel — the owner-facing license screen
  /// never shows it. Entries are recorded on arm, disarm, redeem and
  /// password changes.
  final List<LicenseEvent> events;

  bool isCodeRedeemed(int days, int index) =>
      redeemedCodes.contains('$days:$index');

  bool get isEvaluating => state == LicenseLockState.evaluating;

  bool get isLocked =>
      state == LicenseLockState.expired || state == LicenseLockState.tampered;

  /// Total length of the current armed term, when known.
  Duration? get totalTerm {
    if (armedAt == null || expiresAt == null) return null;
    final term = expiresAt!.difference(armedAt!);
    return term.isNegative ? null : term;
  }

  /// How far before the deadline the warning banner appears — a quarter
  /// of the term, clamped between [LicenseService._minWarningWindow] and
  /// [LicenseService.warningWindow]. A 30-day trial warns for its last
  /// ~7 days instead of the whole term.
  Duration get warningThreshold {
    final term = totalTerm;
    if (term == null) return LicenseService.warningWindow;
    final quarter = term ~/ 4;
    if (quarter <= LicenseService._minWarningWindow) {
      return LicenseService._minWarningWindow;
    }
    return quarter < LicenseService.warningWindow
        ? quarter
        : LicenseService.warningWindow;
  }

  /// Short terms (at most [LicenseService.trialMaxTerm]) read as a trial
  /// in the UI copy.
  bool get isTrial {
    final term = totalTerm;
    return term != null && term <= LicenseService.trialMaxTerm;
  }

  /// True while the license is armed and inside the warning window —
  /// drives the "expires soon" banner so the lock never lands silently.
  bool get isExpiringSoon =>
      state == LicenseLockState.active &&
      (remaining ?? Duration.zero) <= warningThreshold;

  /// Inside the warning window AND inside [LicenseService.criticalWindow]
  /// — the last stretch before the lock engages. Drives the red tier of
  /// the license notice.
  bool get isCritical =>
      isExpiringSoon &&
      (remaining ?? Duration.zero) <= LicenseService.criticalWindow;

  /// Armed and inside the term but outside the warning window — the
  /// quiet countdown indicator shows instead of the alarm banner.
  bool get showCountdown => state == LicenseLockState.active && !isExpiringSoon;

  /// Time left before the lock engages, or null when not armed.
  Duration? get remaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(effectiveNow);
    return diff.isNegative ? Duration.zero : diff;
  }
}

/// Signed, persisted license configuration. Every field is covered by the
/// HMAC signature — editing any of them invalidates the blob.
class _LicenseConfig {
  _LicenseConfig({
    this.armed = false,
    this.expiresAtMs,
    this.armedAtMs = 0,
    this.message = '',
    this.contactInfo = '',
    this.devPasswordHash = '',
    this.lastSeenAtMs = 0,
    this.failedAttempts = 0,
    this.lockoutUntilMs = 0,
    List<String>? redeemedCodes,
    List<LicenseEvent>? events,
  }) : redeemedCodes = redeemedCodes ?? <String>[],
       events = events ?? <LicenseEvent>[];

  bool armed;
  int? expiresAtMs;
  int armedAtMs;
  String message;
  String contactInfo;
  String devPasswordHash;
  int lastSeenAtMs;
  int failedAttempts;
  int lockoutUntilMs;

  /// `'<days>:<index>'` keys of codes already redeemed on this device.
  /// Kept sorted so the signature stays stable.
  List<String> redeemedCodes;

  /// Chronological (oldest-first) activity log, covered by the HMAC
  /// signature like every other field. Capped at
  /// [LicenseService._maxEvents].
  List<LicenseEvent> events;

  /// Canonical payload — keys are always emitted in this order so the
  /// signature is stable across writes.
  Map<String, Object?> toPayload() => {
    'armed': armed,
    'expiresAtMs': expiresAtMs,
    'armedAtMs': armedAtMs,
    'message': message,
    'contactInfo': contactInfo,
    'devPasswordHash': devPasswordHash,
    'lastSeenAtMs': lastSeenAtMs,
    'failedAttempts': failedAttempts,
    'lockoutUntilMs': lockoutUntilMs,
    'redeemedCodes': redeemedCodes,
    'events': events
        .map(
          (e) => <String, Object?>{
            't': e.at.millisecondsSinceEpoch,
            'e': e.type.name,
            'd': e.detail,
          },
        )
        .toList(),
  };

  static _LicenseConfig? fromPayload(Map<String, Object?> map) {
    try {
      return _LicenseConfig(
        armed: map['armed'] == true,
        expiresAtMs: (map['expiresAtMs'] as num?)?.toInt(),
        armedAtMs: (map['armedAtMs'] as num?)?.toInt() ?? 0,
        message: (map['message'] as String?) ?? '',
        contactInfo: (map['contactInfo'] as String?) ?? '',
        devPasswordHash: (map['devPasswordHash'] as String?) ?? '',
        lastSeenAtMs: (map['lastSeenAtMs'] as num?)?.toInt() ?? 0,
        failedAttempts: (map['failedAttempts'] as num?)?.toInt() ?? 0,
        lockoutUntilMs: (map['lockoutUntilMs'] as num?)?.toInt() ?? 0,
        redeemedCodes:
            (map['redeemedCodes'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[],
        events:
            (map['events'] as List?)
                ?.map((e) {
                  if (e is! Map) return null;
                  final t = (e['t'] as num?)?.toInt();
                  final type = LicenseEventType.values.asNameMap()[e['e']];
                  if (t == null || type == null) return null;
                  return LicenseEvent(
                    type: type,
                    at: DateTime.fromMillisecondsSinceEpoch(t),
                    detail: (e['d'] as String?) ?? '',
                  );
                })
                .whereType<LicenseEvent>()
                .toList() ??
            <LicenseEvent>[],
      );
    } catch (_) {
      return null;
    }
  }
}

class _LoadedLicense {
  const _LoadedLicense({
    required this.exists,
    required this.signatureValid,
    this.config,
  });

  final bool exists;
  final bool signatureValid;
  final _LicenseConfig? config;
}

/// Developer license lock ("time bomb") service.
///
/// Design notes:
/// - State lives in `flutter_secure_storage` as an HMAC-SHA256-signed JSON
///   blob; a separate SharedPreferences marker records that the feature was
///   configured at least once. Editing OR deleting the blob while the marker
///   survives resolves to [LicenseLockState.tampered] (fail-closed).
/// - `lastSeenAtMs` is a monotonic watermark: effective time never moves
///   backwards, so rolling the device clock back cannot extend the license.
/// - Unlock codes are `HMAC(secret, 'PINOY-POS:EXTEND:<days>:<index>')`
///   rendered as 8 Crockford-base32 characters. [unlockGrants] defines how
///   many distinct codes exist per grant, so different codes can be handed
///   to different clients. Redemption stacks: a code redeemed before the
///   deadline extends FROM the deadline, never losing the remaining days.
/// - Codes are single-use per device. The redeemed `'<days>:<index>'` keys
///   live inside the signed blob and are mirrored (also signed) into the
///   marker store, so deleting the secure blob alone does not reset them.
///   The mirror is best-effort: wiping ALL app storage still returns the
///   device to a fresh install — an accepted limit of any offline scheme.
/// - The developer password hash lives inside the signed blob, so it cannot
///   be swapped without invalidating the signature.
/// - Password and unlock-code attempts share a persisted, signed
///   rate-limit counter (5 failures → 5-minute lockout).
class LicenseService {
  LicenseService({
    LicenseStore? stateStore,
    LicenseStore? markerStore,
    DateTime Function()? clock,
  }) : _stateStore = stateStore ?? SecureLicenseStore(),
       _markerStore = markerStore ?? SharedPrefsLicenseStore(),
       _clock = clock ?? DateTime.now;

  static const String _stateKey = 'pinoy_pos.license_state.v1';
  static const String _markerKey = 'pinoy_pos.license_configured.v1';
  static const String _redeemedKey = 'pinoy_pos.license_redeemed.v1';

  // Compiled-in secrets. These gate a license check, not user data — for a
  // stronger posture, ship release builds with --obfuscate.
  static const String _stateSecret = 'pp-lic-state-4f2a9c7e1d6b83';
  static const String _unlockSecret = 'pp-lic-unlock-8b3d5f20a9e4c7';

  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);
  static const Duration _watermarkWriteThreshold = Duration(seconds: 60);

  /// Upper bound on the expiry warning — the actual threshold is
  /// proportional to the license term (see [LicenseStatus.warningThreshold]).
  static const Duration warningWindow = Duration(days: 30);

  /// Shortest practical warning runway — a license of a few days still
  /// gets at least this much notice before it locks.
  static const Duration _minWarningWindow = Duration(days: 1);

  /// Last stretch before the lock engages — inside the warning window,
  /// the license notice escalates to the red tier once the remaining
  /// time drops below this.
  static const Duration criticalWindow = Duration(hours: 48);

  /// Cap on the signed activity log — bounded so the blob never grows
  /// without limit; oldest entries drop off first.
  static const int _maxEvents = 25;

  /// Terms at or below this are presented as a trial in the UI copy.
  static const Duration trialMaxTerm = Duration(days: 45);

  /// Pre-filled lock-screen messages. The developer panel auto-fills
  /// [defaultLockMessage] when no message is stored and offers the rest
  /// as one-tap presets, so a fresh setup only needs the developer's
  /// name and number.
  static const String defaultLockMessage =
      "This system's license has expired. Please contact the developer to reactivate it.";
  static const String trialLockMessage =
      'The trial period has ended. Please contact the developer to activate it.';
  static const String balanceDueLockMessage =
      'Please settle the remaining balance to reactivate the system.';

  /// (label, text) quick-fill options under the panel's message field.
  static const List<(String, String)> lockMessagePresets = [
    ('License expired', defaultLockMessage),
    ('Trial ended', trialLockMessage),
    ('Balance due', balanceDueLockMessage),
  ];

  /// Day grants → number of distinct codes available for each. The codes
  /// are deterministic, so all of them can be listed in the developer
  /// panel and handed out one per client. Each code redeems once per
  /// device.
  static const Map<int, int> unlockGrants = {30: 25, 90: 20, 365: 5};

  static const String _base32Alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final LicenseStore _stateStore;
  final LicenseStore _markerStore;
  final DateTime Function() _clock;

  // ── Evaluation ───────────────────────────────────────────────────────

  /// Reads, verifies and evaluates the persisted license state.
  ///
  /// Also advances the monotonic [LicenseStatus.effectiveNow] watermark —
  /// the value used for every expiry comparison.
  Future<LicenseStatus> evaluate() async {
    final marker = await _readMarker();
    final loaded = await _load();
    final wallNow = _clock();

    if (!loaded.exists) {
      // Blob missing but the configured marker survives → someone deleted
      // the secure blob. Fail closed.
      return LicenseStatus(
        state: marker
            ? LicenseLockState.tampered
            : LicenseLockState.notConfigured,
        effectiveNow: wallNow,
      );
    }

    if (!loaded.signatureValid || loaded.config == null) {
      return LicenseStatus(
        state: LicenseLockState.tampered,
        effectiveNow: wallNow,
      );
    }

    final cfg = loaded.config!;
    final effectiveNow = await _advanceWatermark(cfg, wallNow);

    return LicenseStatus(
      state: _resolveState(cfg, effectiveNow),
      effectiveNow: effectiveNow,
      expiresAt: cfg.expiresAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cfg.expiresAtMs!),
      armedAt: cfg.armedAtMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cfg.armedAtMs),
      message: cfg.message,
      contactInfo: cfg.contactInfo,
      hasDeveloperPassword: cfg.devPasswordHash.isNotEmpty,
      redeemedCodes: cfg.redeemedCodes.toSet(),
      events: List.unmodifiable(cfg.events.reversed),
    );
  }

  LicenseLockState _resolveState(_LicenseConfig cfg, DateTime effectiveNow) {
    if (!cfg.armed || cfg.expiresAtMs == null) {
      return LicenseLockState.inactive;
    }
    return effectiveNow.millisecondsSinceEpoch < cfg.expiresAtMs!
        ? LicenseLockState.active
        : LicenseLockState.expired;
  }

  /// Keeps `lastSeenAtMs` monotonic. Returns the effective "now": the wall
  /// clock, or the watermark if the wall clock moved backwards.
  Future<DateTime> _advanceWatermark(
    _LicenseConfig cfg,
    DateTime wallNow,
  ) async {
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(cfg.lastSeenAtMs);
    if (wallNow.isBefore(lastSeen)) {
      return lastSeen;
    }
    if (cfg.lastSeenAtMs == 0 ||
        wallNow.difference(lastSeen) >= _watermarkWriteThreshold) {
      cfg.lastSeenAtMs = wallNow.millisecondsSinceEpoch;
      await _persist(cfg);
    }
    return wallNow;
  }

  // ── Developer password ───────────────────────────────────────────────

  /// Determines whether the hidden dialog should offer first-time setup,
  /// normal verification, or nothing at all (untrusted state).
  ///
  /// [DevGateMode.setup] is safe when the blob is signature-valid but has no
  /// password: only this code (holding the secret) can produce a valid
  /// signature, so a client cannot reach setup by tampering.
  Future<DevGateMode> developerGateMode() async {
    final marker = await _readMarker();
    final loaded = await _load();

    if (loaded.exists && loaded.signatureValid && loaded.config != null) {
      return loaded.config!.devPasswordHash.isEmpty
          ? DevGateMode.setup
          : DevGateMode.verify;
    }
    if (loaded.exists) return DevGateMode.blocked;
    return marker ? DevGateMode.blocked : DevGateMode.setup;
  }

  /// Sets the developer password. Only allowed in [DevGateMode.setup].
  Future<bool> initializeDeveloperPassword(String password) async {
    if (await developerGateMode() != DevGateMode.setup) return false;
    final loaded = await _load();
    final cfg =
        (loaded.signatureValid ? loaded.config : null) ?? _LicenseConfig();
    cfg.devPasswordHash = SecurityHelper.hashPassword(password);
    _recordEvent(cfg, LicenseEventType.passwordSet);
    await _persist(cfg);
    return true;
  }

  /// Verifies the developer password against the signed, persisted hash.
  Future<DevAuthResponse> verifyDeveloperPassword(String password) async {
    final loaded = await _load();
    if (!loaded.signatureValid || loaded.config == null) {
      return const DevAuthResponse(result: DevAuthResult.denied);
    }
    final cfg = loaded.config!;
    if (cfg.devPasswordHash.isEmpty) {
      return const DevAuthResponse(result: DevAuthResult.notSet);
    }
    final lockout = _lockoutRemaining(cfg);
    if (lockout != null) {
      return DevAuthResponse(
        result: DevAuthResult.lockedOut,
        retryAfter: lockout,
      );
    }
    if (SecurityHelper.verifyPassword(password, cfg.devPasswordHash)) {
      cfg.failedAttempts = 0;
      cfg.lockoutUntilMs = 0;
      await _persist(cfg);
      return const DevAuthResponse(result: DevAuthResult.ok);
    }
    await _registerFailure(cfg);
    return const DevAuthResponse(result: DevAuthResult.incorrect);
  }

  /// Changes the developer password. Requires the current password.
  Future<DevAuthResponse> changeDeveloperPassword(
    String current,
    String next,
  ) async {
    final auth = await verifyDeveloperPassword(current);
    if (!auth.isOk) return auth;

    final loaded = await _load();
    final cfg = loaded.config!;
    cfg.devPasswordHash = SecurityHelper.hashPassword(next);
    _recordEvent(cfg, LicenseEventType.passwordChanged);
    await _persist(cfg);
    return const DevAuthResponse(result: DevAuthResult.ok);
  }

  // ── Configuration ────────────────────────────────────────────────────

  /// Persists the license configuration (arm state, deadline, lock-screen
  /// message and developer contact). Returns the fresh status.
  Future<LicenseStatus> saveConfig({
    required bool armed,
    DateTime? expiresAt,
    String message = '',
    String contactInfo = '',
  }) async {
    final loaded = await _load();
    final cfg =
        (loaded.signatureValid ? loaded.config : null) ?? _LicenseConfig();
    final newExpiresAtMs = expiresAt?.millisecondsSinceEpoch;
    if (armed) {
      // A new deadline starts a fresh term — the warning window is
      // proportional to it. Re-saving the same armed deadline keeps the
      // original term start.
      if (!cfg.armed || cfg.expiresAtMs != newExpiresAtMs) {
        cfg.armedAtMs = _clock().millisecondsSinceEpoch;
        final term = Duration(
          milliseconds: (newExpiresAtMs ?? 0) - _effectiveNowMs(cfg),
        );
        _recordEvent(
          cfg,
          LicenseEventType.armed,
          term.inDays >= 1
              ? '${term.inDays}-day term'
              : '${term.inHours}-hour term',
        );
      }
    } else {
      if (cfg.armed) _recordEvent(cfg, LicenseEventType.disarmed);
      cfg.armedAtMs = 0;
    }
    cfg.armed = armed;
    cfg.expiresAtMs = newExpiresAtMs;
    cfg.message = message.trim();
    cfg.contactInfo = contactInfo.trim();
    await _persist(cfg);
    return evaluate();
  }

  /// Removes all license state, the configured marker and the redeemed
  /// code mirror. After this the device behaves exactly like a fresh
  /// install — including making previously spent codes redeemable again.
  Future<void> clearConfiguration() async {
    try {
      await _stateStore.delete(_stateKey);
    } catch (_) {}
    try {
      await _markerStore.delete(_markerKey);
      await _markerStore.delete(_redeemedKey);
    } catch (_) {}
  }

  // ── Unlock codes ─────────────────────────────────────────────────────

  /// The human-dictatable unlock code for grant [days], slot [index]
  /// (0-based, must be below `unlockGrants[days]`). Deterministic — no
  /// generation step or server needed.
  String unlockCode(int days, int index) {
    final digest = Hmac(
      sha256,
      utf8.encode(_unlockSecret),
    ).convert(utf8.encode('PINOY-POS:EXTEND:$days:$index')).bytes;
    var value = 0;
    for (var i = 0; i < 5; i++) {
      value = (value << 8) | digest[i];
    }
    final chars = List<String>.generate(
      8,
      (i) => _base32Alphabet[(value >> (35 - i * 5)) & 0x1F],
    );
    return '${chars.sublist(0, 4).join()}-${chars.sublist(4).join()}';
  }

  /// Redeems an unlock code entered on the lock screen.
  ///
  /// On success the license is re-armed with a new deadline of
  /// `effectiveNow + grantedDays`. Works fully offline.
  Future<LicenseRedeemResult> redeemUnlockCode(String input) async {
    final marker = await _readMarker();
    final loaded = await _load();

    // A valid HMAC code can only come from the developer, so redemption is
    // allowed even on a tampered/deleted blob — but nothing is salvaged
    // from untrusted payloads (a planted password hash included).
    if (!loaded.exists && !marker) {
      return LicenseRedeemResult.invalid();
    }
    final cfg = (loaded.exists && loaded.signatureValid)
        ? loaded.config!
        : _LicenseConfig();

    // A deliberately disarmed license (paid in full / enforcement off)
    // must not be silently re-armed by a code the client is holding.
    if (loaded.signatureValid && !cfg.armed) {
      return LicenseRedeemResult.invalid();
    }

    final lockout = _lockoutRemaining(cfg);
    if (lockout != null) {
      return LicenseRedeemResult.lockedOut(lockout);
    }

    // Single-use enforcement: the signed blob is authoritative, the
    // marker-store mirror preserves the record across blob deletion.
    final redeemed = <String>{
      ...cfg.redeemedCodes,
      ...await _loadRedeemedMirror(),
    };

    final normalized = _normalizeCode(input);
    for (final grant in unlockGrants.entries) {
      for (var i = 0; i < grant.value; i++) {
        if (normalized == _normalizeCode(unlockCode(grant.key, i))) {
          final grantKey = '${grant.key}:$i';
          if (redeemed.contains(grantKey)) {
            return LicenseRedeemResult.alreadyUsed();
          }
          redeemed.add(grantKey);

          final nowMs = _effectiveNowMs(cfg);
          // Stack: redeemed before the deadline, the grant extends from
          // the deadline; redeemed after, it extends from now.
          final baseMs = max(nowMs, cfg.expiresAtMs ?? 0);
          cfg
            ..armed = true
            ..expiresAtMs = baseMs + Duration(days: grant.key).inMilliseconds
            ..armedAtMs = nowMs
            ..failedAttempts = 0
            ..lockoutUntilMs = 0
            ..lastSeenAtMs = max(cfg.lastSeenAtMs, nowMs)
            ..redeemedCodes = (redeemed.toList()..sort());
          _recordEvent(cfg, LicenseEventType.redeemed, '+${grant.key} days');
          await _persist(cfg);
          await _persistRedeemedMirror(redeemed);
          return LicenseRedeemResult.success(
            daysGranted: grant.key,
            newExpiry: DateTime.fromMillisecondsSinceEpoch(cfg.expiresAtMs!),
          );
        }
      }
    }

    await _registerFailure(cfg);
    return LicenseRedeemResult.invalid();
  }

  static String _normalizeCode(String input) =>
      input.trim().toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

  // ── Internals ────────────────────────────────────────────────────────

  Future<bool> _readMarker() async {
    try {
      return (await _markerStore.read(_markerKey)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<_LoadedLicense> _load() async {
    String? raw;
    try {
      raw = await _stateStore.read(_stateKey);
    } catch (_) {
      raw = null;
    }
    if (raw == null || raw.isEmpty) {
      return const _LoadedLicense(exists: false, signatureValid: false);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const _LoadedLicense(exists: true, signatureValid: false);
      }
      final map = decoded.cast<String, Object?>();
      final sig = map['sig'];
      final data = map['data'];
      if (sig is! String || data is! Map) {
        return const _LoadedLicense(exists: true, signatureValid: false);
      }
      final payload = data.cast<String, Object?>();
      final valid = sig == _sign(payload);
      return _LoadedLicense(
        exists: true,
        signatureValid: valid,
        config: _LicenseConfig.fromPayload(payload),
      );
    } catch (_) {
      return const _LoadedLicense(exists: true, signatureValid: false);
    }
  }

  Future<void> _persist(_LicenseConfig cfg) async {
    final payload = cfg.toPayload();
    final blob = jsonEncode({'data': payload, 'sig': _sign(payload)});
    await _stateStore.write(_stateKey, blob);
    try {
      await _markerStore.write(_markerKey, '1');
    } catch (_) {
      // Marker write is best-effort; the signed blob is authoritative.
    }
  }

  /// Signed mirror of the redeemed-code set, kept in the marker store so
  /// single-use tracking survives deletion of the secure blob. Read back
  /// only during redemption — a missing or invalid mirror reads as empty
  /// (it cannot be distinguished from a device that never redeemed).
  Future<Set<String>> _loadRedeemedMirror() async {
    try {
      final raw = await _markerStore.read(_redeemedKey);
      if (raw == null || raw.isEmpty) return const <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String>{};
      final map = decoded.cast<String, Object?>();
      final sig = map['sig'];
      final data = map['data'];
      if (sig is! String || data is! Map) return const <String>{};
      final payload = data.cast<String, Object?>();
      if (sig != _sign(payload)) return const <String>{};
      final list = payload['redeemed'];
      if (list is! List) return const <String>{};
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> _persistRedeemedMirror(Set<String> redeemed) async {
    final payload = <String, Object?>{'redeemed': redeemed.toList()..sort()};
    try {
      await _markerStore.write(
        _redeemedKey,
        jsonEncode({'data': payload, 'sig': _sign(payload)}),
      );
    } catch (_) {
      // Best-effort — the signed blob still carries the redeemed set.
    }
  }

  static String _sign(Map<String, Object?> payload) => Hmac(
    sha256,
    utf8.encode(_stateSecret),
  ).convert(utf8.encode(jsonEncode(payload))).toString();

  /// Effective "now" in milliseconds — the wall clock clamped to the
  /// monotonic watermark so lockouts cannot be dodged by rewinding time.
  int _effectiveNowMs(_LicenseConfig cfg) =>
      max(_clock().millisecondsSinceEpoch, cfg.lastSeenAtMs);

  /// Appends a signed activity-log entry to [cfg] (kept oldest-first) and
  /// trims to [_maxEvents]. Called only on explicit lifecycle actions —
  /// arming, disarming, redeeming, password changes — never from
  /// [evaluate], so the periodic watermark write cannot spam the log.
  /// Timestamps use the effective clock so a wound-back wall clock cannot
  /// reorder events.
  void _recordEvent(
    _LicenseConfig cfg,
    LicenseEventType type, [
    String detail = '',
  ]) {
    cfg.events.add(
      LicenseEvent(
        type: type,
        at: DateTime.fromMillisecondsSinceEpoch(_effectiveNowMs(cfg)),
        detail: detail,
      ),
    );
    if (cfg.events.length > _maxEvents) {
      cfg.events.removeRange(0, cfg.events.length - _maxEvents);
    }
  }

  Duration? _lockoutRemaining(_LicenseConfig cfg) {
    final remaining = cfg.lockoutUntilMs - _effectiveNowMs(cfg);
    return remaining > 0 ? Duration(milliseconds: remaining) : null;
  }

  Future<void> _registerFailure(_LicenseConfig cfg) async {
    cfg.failedAttempts++;
    if (cfg.failedAttempts >= _maxFailedAttempts) {
      cfg.failedAttempts = 0;
      cfg.lockoutUntilMs =
          _effectiveNowMs(cfg) + _lockoutDuration.inMilliseconds;
    }
    await _persist(cfg);
  }
}
