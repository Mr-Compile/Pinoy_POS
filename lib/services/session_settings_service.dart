import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';

/// Resolves session-timeout configuration.
///
/// The effective inactivity timeout is the per-user override (if set),
/// otherwise the store default from the `settings` table.
///
/// This service does not perform permission checks because it is used by
/// the auth/session flow before the session is fully established.
class SessionSettingsService {
  final SettingsRepository _settingsRepository = SettingsRepository();

  static const int _defaultInactivityTimeoutMinutes = 15;
  static const int defaultWarningSeconds = 30;
  static const Duration maxSessionLifetime = Duration(hours: 8);

  Future<Duration> getEffectiveInactivityTimeout(User user) async {
    if (user.inactivityTimeoutMinutes != null) {
      return Duration(minutes: user.inactivityTimeoutMinutes!);
    }

    final settings = await _settingsRepository.getSettings();
    final minutes = settings?.inactivityTimeoutMinutes ?? _defaultInactivityTimeoutMinutes;
    return Duration(minutes: minutes);
  }

  /// The configured session-expiry warning threshold, in seconds.
  ///
  /// This is the raw store setting; it is NOT adjusted for the effective
  /// inactivity timeout. Use [getEffectiveWarningThreshold] for the value
  /// that should drive the timer.
  Future<Duration> getWarningThreshold() async {
    final settings = await _settingsRepository.getSettings();
    final seconds =
        settings?.sessionWarningSeconds ?? defaultWarningSeconds;
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }

  /// The warning threshold for [user], clamped below the effective
  /// inactivity timeout so the warning can never be equal to or greater
  /// than the timeout itself.
  ///
  /// Returns [Duration.zero] when the effective timeout is too short to
  /// leave any room for a warning (the session then expires without one).
  Future<Duration> getEffectiveWarningThreshold(User user) async {
    final timeout = await getEffectiveInactivityTimeout(user);
    var warning = await getWarningThreshold();
    if (warning >= timeout) {
      warning = timeout - const Duration(seconds: 1);
    }
    return warning.isNegative ? Duration.zero : warning;
  }
}
