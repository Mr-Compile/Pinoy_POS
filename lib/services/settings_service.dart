import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  final SettingsRepository _settingsRepository = SettingsRepository();
  Settings? _currentSettings;

  Settings? get currentSettings => _currentSettings;

  Future<Settings> getSettings() async {
    if (_currentSettings != null) {
      return _currentSettings!;
    }

    _currentSettings = await _settingsRepository.getSettings();
    
    if (_currentSettings == null) {
      _currentSettings = Settings(
        storeName: 'My Store',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _settingsRepository.insert(_currentSettings!);
    }

    return _currentSettings!;
  }

  Future<bool> updateSettings(Settings settings) async {
    final updated = settings.copyWith(updatedAt: DateTime.now());
    await _settingsRepository.update(updated);
    _currentSettings = updated;
    return true;
  }

  Future<String> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('theme') ?? 'light';
  }

  Future<void> setTheme(String theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', theme);
  }

  Future<String> getAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('accent_color') ?? 'green';
  }

  Future<void> setAccentColor(String color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent_color', color);
  }
}
