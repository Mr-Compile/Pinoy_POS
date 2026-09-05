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
  static const Duration maxSessionLifetime = Duration(hours: 8);

  Future<Duration> getEffectiveInactivityTimeout(User user) async {
    if (user.inactivityTimeoutMinutes != null) {
      return Duration(minutes: user.inactivityTimeoutMinutes!);
    }

    final settings = await _settingsRepository.getSettings();
    final minutes = settings?.inactivityTimeoutMinutes ?? _defaultInactivityTimeoutMinutes;
    return Duration(minutes: minutes);
  }
}
