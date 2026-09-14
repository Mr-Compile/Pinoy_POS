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

  /// A stored timeout of 0 minutes means the session never ends due to
  /// inactivity. The absolute [maxSessionLifetime] still applies.
  static const int unlimitedInactivityMinutes = 0;

  /// The choices offered by the inactivity-timeout dropdowns, in minutes.
  static const List<int> inactivityTimeoutChoices = [
    3,
    15,
    30,
    60,
    unlimitedInactivityMinutes,
  ];

  /// Display label for a stored inactivity timeout in minutes.
  static String inactivityTimeoutLabel(int minutes) => switch (minutes) {
        unlimitedInactivityMinutes => 'Unlimited',
        60 => '1 hour',
        _ => '$minutes minutes',
      };

  /// The choices offered by the session-warning dropdown, in seconds.
  static const List<int> sessionWarningChoices = [15, 30, 60, 120];

  /// Display label for a stored session warning in seconds.
  static String sessionWarningLabel(int seconds) => switch (seconds) {
        60 => '1 minute',
        120 => '2 minutes',
        _ => '$seconds seconds',
      };

  /// The effective inactivity timeout for [user], or `null` when the
  /// session is unlimited and never expires due to inactivity.
  Future<Duration?> getEffectiveInactivityTimeout(User user) async {
    final minutes = user.inactivityTimeoutMinutes ??
        (await _settingsRepository.getSettings())?.inactivityTimeoutMinutes ??
        _defaultInactivityTimeoutMinutes;
    if (minutes <= unlimitedInactivityMinutes) return null;
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
  /// Returns [Duration.zero] when the effective timeout is unlimited or too
  /// short to leave any room for a warning (no warning is ever shown).
  Future<Duration> getEffectiveWarningThreshold(User user) async {
    final timeout = await getEffectiveInactivityTimeout(user);
    if (timeout == null) return Duration.zero;
    var warning = await getWarningThreshold();
    if (warning >= timeout) {
      warning = timeout - const Duration(seconds: 1);
    }
    return warning.isNegative ? Duration.zero : warning;
  }
}
