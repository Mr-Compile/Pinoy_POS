# Fresh-Install Activation Gate — Design

Date: 2026-09-16
Status: Approved by user (design review)

## Problem

The existing developer license system treats "no license state" (no secure blob, no
SharedPreferences marker) as `LicenseLockState.notConfigured` — the app runs with no
enforcement. A full wipe (Clear Data or reinstall) therefore returns the device to an
ungated state. The code documents this as an accepted limit; this feature closes it.

Goal: every fresh install — and every install whose storage was wiped — must require
a developer-held activation code before the app can be used.

## Decisions (from brainstorming)

- Activation **unlocks the install only**. It does not arm a license term; arming
  stays a separate developer-panel action.
- **Single master code**, compiled in via HMAC derivation (same scheme as unlock
  codes). Not a pool, not device-bound. Accepted risk: one leaked code unlocks every
  install; rotation means changing the secret and shipping an update.
- Fully offline. No server, no device-fingerprint dependency.

## State model

`lib/services/license_service.dart`:

- `_LicenseConfig` gains a nullable `activated` field persisted in the signed payload:
  - absent/`null` → **legacy blob** written before this feature → treated as activated
    (existing licensed installs are grandfathered, never gated by this). Re-persisting
    a legacy config keeps emitting `null`.
  - `false` → blob exists only for activation bookkeeping (rate-limit counter); the
    device is NOT activated.
  - `true` → activation code was redeemed.
- **`_LicenseConfig()` defaults `activated=false`.** Every constructor site that mints
  a fresh config — `initializeDeveloperPassword`, `saveConfig`, failed activation —
  writes `activated:false` explicitly. This is load-bearing: without it, "Developer
  access → set password" on a wiped device would persist a keyless (legacy-looking)
  blob and open the gate with no code. `fromPayload` maps an absent key to `null`
  (legacy), so only blobs that carry the literal `false` are gated.
- New `LicenseLockState.activationRequired`.
- `evaluate()` resolution order:
  1. no blob + no marker → `activationRequired` (fresh install / full wipe)
  2. no blob + marker → `tampered` (unchanged)
  3. blob exists, signature invalid → `tampered` (unchanged)
  4. blob valid, `activated == false` → `activationRequired`
  5. otherwise → existing `inactive` / `active` / `expired` resolution (unchanged)
- `LicenseStatus` gains `bool get requiresActivation => state == activationRequired`.
  `isLocked` stays `expired || tampered` only — activation uses a different screen
  with different copy.

### Why the tri-state

A failed activation attempt must persist its rate-limit counter, which writes a blob
(`activated=false`, `failedAttempts=N`). If blob existence alone meant "configured",
one wrong guess would open the gate permanently. The explicit `false` keeps the device
on the activation screen while preserving lockout bookkeeping.

## Activation code

- `String activationCode()` → `HMAC-SHA256(_activationSecret, 'PINOY-POS:ACTIVATE')`
  rendered as 8 Crockford-base32 chars in `XXXX-XXXX` form — identical derivation
  pipeline to `unlockCode()`, new secret + payload namespace.
- `Future<ActivationResult> redeemActivationCode(String input)`:
  - Normalizes input with `_normalizeCode` (uppercase, strip non-alphanumerics).
  - Shares the persisted rate limiter (5 failures → 5-minute lockout) via
    `_lockoutRemaining` / `_registerFailure`.
  - On failure: persists a config with `activated=false` and the incremented counter
    (creating the blob + marker if absent).
  - On success: sets `activated=true` on the existing-or-new config, records a
    `LicenseEventType.activated` event, persists. License arm state is preserved —
    activation does not arm or disarm.
- Result type mirrors `LicenseRedeemResult` (`success`, `retryAfter`); no
  `alreadyUsed` concept — the master code is reusable by design.
- A successful `redeemUnlockCode` also sets `activated=true`: a valid developer code
  is proof the developer was present. EXTEND codes on a wiped device still return
  invalid (no marker, no blob), so they cannot bypass the gate.
- `clearConfiguration()` removes blob + marker → next `evaluate()` returns
  `activationRequired`. Consistent with "behaves like a fresh install".

## UI flow

- New `lib/ui/screens/activation_screen.dart`, modeled on `LicenseLockedScreen`:
  - Hierarchy: brand/lock badge → "Activation Required" headline → explainer copy →
    developer contact (if configured) → code field (`XXXX-XXXX`, same formatters) →
    primary **Activate** button → tertiary **Developer access** text button.
  - Self-healing exit: when status leaves `activationRequired`, route to
    `LoginScreen` via `pushAndRemoveUntil` (same pattern as the locked screen).
  - `PopScope(canPop: false)`.
- `SplashScreen`: `requiresActivation` routes to `ActivationScreen`, taking
  precedence over auth phase — same precedence `isLocked` has today.
- `SessionGuard`: the existing `licenseStatusProvider` listener + 1-minute timer +
  app-resume recheck also enforce `requiresActivation` → `pushAndRemoveUntil` to
  `ActivationScreen`. Factor the shared "replace stack on license state" path if it
  stays readable.
- `DeveloperLicenseScreen`: display the master activation code at the top of the
  code section (derived on demand, like the unlock-code list).
- `settings_screen` license subtitle / `LicenseNotice`: `activationRequired` renders
  a neutral "Activation required" subtitle; the notice banner stays hidden (the app
  is unreachable anyway).
- Developer on-site flow on a wiped device: activation screen → Developer access →
  (first time) set developer password → panel shows the master code → back → enter
  code → activated.

## Persistence & wipe behavior

- Activation state lives only in the signed secure-storage blob (+ marker). Wipe or
  reinstall → `activationRequired` again. This is the feature, not a gap.
- Backup/restore does not carry activation: the license blob is in
  `flutter_secure_storage`, outside the SQLite/zip backup payload. A restored
  database on a fresh install still requires activation.

## Security notes

- Same ceiling as the existing license system: the secret is compiled in, and a
  determined attacker who decompiles the APK can patch the check. Deterrent for
  non-technical operators, not DRM. Ship release builds with `--obfuscate`.
- `_activationSecret` is a new constant; rotating it later invalidates nothing else
  because `activated` is just a flag in the signed blob (a new secret only changes
  which code redeems).
- Rate limiting persists across app restarts via the signed blob.

## Testing

Extend `test/license_service_test.dart` patterns (in-memory `LicenseStore` fakes,
injectable clock):

- fresh stores → `activationRequired`
- wrong code → still `activationRequired`, `failedAttempts` persisted
- 5 wrong codes → lockout returns `retryAfter`
- right code → resolves `inactive`, `activated=true` persisted, event logged
- legacy blob (payload without `activated` key) → normal resolution, not gated
- activated → delete both stores (simulated wipe) → `activationRequired` again
- marker present + blob absent → `tampered` (regression)
- `redeemUnlockCode` success → `activated` becomes true
- widget: `ActivationScreen` renders code field + Activate, routes out on activation
  (fake `LicenseService` like `announcement_banner_test` fakes)

## Out of scope

- Device-bound or server-verified codes
- Auto-arming a trial term on activation
- Rotating existing secrets / re-signing legacy blobs
- Any change to unlock-code grants, lock-screen copy, or the developer panel layout
  beyond adding the activation code display
