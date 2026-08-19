import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  final SettingsRepository _settingsRepository = SettingsRepository();
  final SessionManager _sessionManager = SessionManager();
  Settings? _currentSettings;

  Settings? get currentSettings => _currentSettings;

  Future<Settings> getSettings() async {
    if (!_sessionManager.hasPermission('view_settings')) {
      throw AuthorizationException('view_settings');
    }
    if (_currentSettings != null) {
      return _currentSettings!;
    }

    _currentSettings = await _settingsRepository.getSettings();
    
    if (_currentSettings == null) {
      final defaultSettings = Settings(
        storeName: 'My Store',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final id = await _settingsRepository.insert(defaultSettings);
      _currentSettings = defaultSettings.copyWith(id: id);
    }

    return _currentSettings!;
  }

  Future<bool> updateSettings(Settings settings) async {
    if (!_sessionManager.hasPermission('edit_settings')) {
      throw AuthorizationException('edit_settings');
    }
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

  // ── Groq AI configuration ────────────────────────────────────────────
  //
  // The Groq API key and model are stored in the settings table. Only
  // System Admin (who has the `manage_ai_config` permission) may set them.
  // The Owner's AI Advisor reads the key via [getGroqApiKey] but never
  // receives it through provider state — it is fetched inside the service
  // and used only for the HTTP Authorization header.

  /// Returns the configured Groq API key, or null if not configured.
  /// Requires `view_ai_advisor` (Owner) or `manage_ai_config` (Admin).
  Future<String?> getGroqApiKey() async {
    if (!_sessionManager.hasPermission('view_ai_advisor') &&
        !_sessionManager.hasPermission('manage_ai_config')) {
      return null;
    }
    final settings = await getSettings();
    final key = settings.groqApiKey;
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  /// Returns true if a Groq API key has been configured.
  Future<bool> isGroqConfigured() async {
    final key = await getGroqApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Returns the configured Groq model, defaulting to llama-3.3-70b-versatile.
  Future<String> getGroqModel() async {
    final settings = await getSettings();
    final model = settings.groqModel;
    if (model == null || model.trim().isEmpty) {
      return 'llama-3.3-70b-versatile';
    }
    return model.trim();
  }

  /// Saves the Groq API key and model. Requires `manage_ai_config`.
  Future<bool> saveGroqConfig({required String apiKey, required String model}) async {
    if (!_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('manage_ai_config');
    }
    final settings = await getSettings();
    final updated = settings.copyWith(
      groqApiKey: apiKey.trim(),
      groqModel: model.trim(),
      updatedAt: DateTime.now(),
    );
    return updateSettings(updated);
  }

  /// Clears the Groq API key and model. Requires `manage_ai_config`.
  Future<bool> clearGroqConfig() async {
    if (!_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('manage_ai_config');
    }
    final settings = await getSettings();
    final updated = settings.copyWith(
      groqApiKey: null,
      groqModel: null,
      updatedAt: DateTime.now(),
    );
    return updateSettings(updated);
  }
}
