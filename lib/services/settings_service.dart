import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/repositories/settings_repository.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  final SettingsRepository _settingsRepository = SettingsRepository();
  final SessionManager _sessionManager = SessionManager();
  final GroqService _groqService = GroqService();
  final SecureStorageService _secureStorage = SecureStorageService();
  static const String _groqApiKeySecureKey = 'groq_api_key';
  Settings? _currentSettings;
  Settings? _storeInfo;

  /// Cached list of available Groq models (refreshed by Admin).
  List<GroqModel> _cachedModels = [];
  bool _modelsFetched = false;

  Settings? get currentSettings => _currentSettings;

  Future<Settings> getSettings() async {
    if (!_sessionManager.hasPermission('view_settings') &&
        !_sessionManager.hasPermission('use_ai_advisor') &&
        !_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('view_settings');
    }
    if (_currentSettings != null) {
      await _migrateGroqApiKey();
      _currentSettings = _currentSettings!.copyWith(groqApiKey: null);
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

    await _migrateGroqApiKey();
    _currentSettings = _currentSettings!.copyWith(groqApiKey: null);
    return _currentSettings!;
  }

  /// Returns the operational GCash/payment settings for the POS flow.
  ///
  /// This is intentionally scoped so that Staff (who have `create_sales`)
  /// can read the GCash rules without receiving sensitive store
  /// configuration such as the Groq API key.
  Future<PaymentSettings> getPaymentSettings() async {
    if (!_sessionManager.hasPermission('create_sales') &&
        !_sessionManager.hasPermission('view_settings') &&
        !_sessionManager.hasPermission('edit_settings')) {
      throw AuthorizationException('create_sales');
    }

    var settings = await _settingsRepository.getSettings();

    if (settings == null) {
      final defaultSettings = Settings(
        storeName: 'My Store',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final id = await _settingsRepository.insert(defaultSettings);
      settings = defaultSettings.copyWith(id: id);
    }

    _currentSettings = settings;

    return PaymentSettings.fromSettings(settings);
  }

  Future<bool> updateSettings(Settings settings) async {
    if (!_sessionManager.hasPermission('edit_settings')) {
      throw AuthorizationException('edit_settings');
    }
    // The API key is never written to the settings table.
    final updated = settings.copyWith(
      groqApiKey: null,
      updatedAt: DateTime.now(),
    );
    await _settingsRepository.update(updated);
    _currentSettings = updated;
    _storeInfo = null;
    return true;
  }

  /// Returns the store information (name, address, contact, currency) to use
  /// in reports, receipts and exports.  If none is configured, a default is
  /// returned.  This does not require `view_settings` because it is needed by
  /// all roles (e.g., printing a receipt).
  Future<Settings> getStoreInfo() async {
    if (_storeInfo != null) return _storeInfo!;

    final settings = await _settingsRepository.getSettings();
    _storeInfo = settings ??
        Settings(
          storeName: 'Pinoy POS',
          currency: 'PHP',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
    return _storeInfo!;
  }

  /// Returns true when store information is missing or still has the default
  /// placeholder name.  Used to show setup guidance on the reports screen.
  Future<bool> isStoreInfoIncomplete() async {
    final info = await getStoreInfo();
    return info.storeName.trim().isEmpty ||
        info.storeName.trim().toLowerCase() == 'my store' ||
        info.storeName.trim().toLowerCase() == 'pinoy pos';
  }

  /// Refreshes the cached store info, used after settings are updated.
  Future<void> refreshStoreInfo() async {
    _storeInfo = null;
    _currentSettings = null;
    await getStoreInfo();
  }

  /// Migrates a plain-text `groq_api_key` from the settings table into
  /// [flutter_secure_storage] and clears the column.
  ///
  /// If the secure-storage key already exists, it overwrites the DB copy only.
  Future<bool> _migrateGroqApiKey() async {
    final dbKey = await _settingsRepository.getGroqApiKeyRaw();
    if (dbKey == null || dbKey.isEmpty) return false;

    final settings = await _settingsRepository.getSettings();
    if (settings == null) return false;

    final secureKey = await _secureStorage.read(key: _groqApiKeySecureKey);
    if (secureKey == null || secureKey.isEmpty) {
      await _secureStorage.write(key: _groqApiKeySecureKey, value: dbKey);
    }

    await _settingsRepository.update(
      settings.copyWith(groqApiKey: null, updatedAt: DateTime.now()),
    );
    return true;
  }

  Future<String> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('theme') ?? 'light';

    // Migrate legacy 'system' values to the default light mode.
    if (stored == 'system') {
      await prefs.setString('theme', 'light');
      return 'light';
    }

    return (stored == 'light' || stored == 'dark') ? stored : 'light';
  }

  Future<void> setTheme(String theme) async {
    final validated = (theme == 'light' || theme == 'dark') ? theme : 'light';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', validated);
  }

  // ── Groq AI configuration ────────────────────────────────────────────
  //
  // The Groq API key is stored in flutter_secure_storage, not the SQLite
  // settings table. Only System Admin (who has the `manage_ai_config`
  // permission) may set it. The Owner's AI Advisor reads the key via
  // [getGroqApiKey]; it is fetched inside the service and used only for the
  // HTTP Authorization header.

  /// Returns the configured Groq API key, or null if not configured.
  /// Requires `use_ai_advisor` (all roles — used to send AI requests) or
  /// `manage_ai_config` (Admin — used to test/save the key). The key is
  /// never returned to the UI; it is consumed inside the service layer
  /// for the HTTP Authorization header only.
  Future<String?> getGroqApiKey() async {
    if (!_sessionManager.hasPermission('use_ai_advisor') &&
        !_sessionManager.hasPermission('manage_ai_config')) {
      return null;
    }
    // getSettings will migrate any old plain-text key from the DB first.
    await getSettings();
    final key = await _secureStorage.read(key: _groqApiKeySecureKey);
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
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim();

    // Store the key in secure storage, never in the settings table.
    await _secureStorage.write(key: _groqApiKeySecureKey, value: trimmedKey);

    final settings = await getSettings();
    final updated = settings.copyWith(
      groqApiKey: null,
      groqModel: trimmedModel,
      updatedAt: DateTime.now(),
    );
    return updateSettings(updated);
  }

  /// Clears the Groq API key and model. Requires `manage_ai_config`.
  Future<bool> clearGroqConfig() async {
    if (!_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('manage_ai_config');
    }
    await _secureStorage.delete(key: _groqApiKeySecureKey);

    final settings = await getSettings();
    final updated = settings.copyWith(
      groqApiKey: null,
      groqModel: null,
      updatedAt: DateTime.now(),
    );
    _cachedModels = [];
    _modelsFetched = false;
    return updateSettings(updated);
  }

  // ── Test Connection & Model Management ───────────────────────────────

  /// Tests the Groq API connection by fetching the models list.
  ///
  /// This is the authoritative Test Connection — it only reports success
  /// when a real HTTP 200 response with valid model data is received.
  /// Requires `manage_ai_config` (Admin only).
  Future<GroqTestResult> testGroqConnection(String apiKey) async {
    if (!_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('manage_ai_config');
    }
    final result = await _groqService.testConnection(apiKey: apiKey);
    if (result.success) {
      _cachedModels = result.models;
      _modelsFetched = true;
    }
    return result;
  }

  /// Fetches the latest available models from Groq and caches them.
  ///
  /// Uses the currently saved API key. Requires `manage_ai_config`.
  Future<GroqModelsResult> refreshModels() async {
    if (!_sessionManager.hasPermission('manage_ai_config')) {
      throw AuthorizationException('manage_ai_config');
    }
    final apiKey = await getGroqApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return GroqModelsResult(
        success: false,
        errorMessage: 'No API key configured. Please enter an API key first.',
      );
    }
    final result = await _groqService.listModels(apiKey: apiKey);
    if (result.success) {
      _cachedModels = result.models;
      _modelsFetched = true;
    }
    return result;
  }

  /// Returns the cached available models, or an empty list if not fetched.
  List<GroqModel> getCachedModels() {
    return _cachedModels;
  }

  /// Returns true if models have been fetched at least once.
  bool get modelsFetched => _modelsFetched;

  /// Validates that the saved model exists in the available model list.
  ///
  /// If models haven't been fetched yet, fetches them first.
  /// Returns true if the model exists and is active.
  Future<bool> validateSavedModel() async {
    final model = await getGroqModel();
    if (!_modelsFetched) {
      await refreshModels();
    }
    return _cachedModels.any((m) => m.id == model && m.active);
  }

  /// Returns a recommended default model from the available models.
  ///
  /// Evaluates models based on:
  /// - Business analysis quality (larger context preferred for analysis)
  /// - Response speed (instant models for quick answers)
  /// - Current availability
  ///
  /// Does not hardcode a model that may be deprecated. Picks from the
  /// actually available models returned by the Groq Models API.
  String getRecommendedModel(List<GroqModel> models) {
    if (models.isEmpty) return 'llama-3.3-70b-versatile';

    // Preferred models in priority order (by capability for business analysis).
    // These are evaluated against the ACTUAL available list — if a model
    // has been deprecated, it won't be in the list and we skip it.
    const preferred = [
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-120b',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'qwen/qwen3-32b',
      'openai/gpt-oss-20b',
      'llama-3.1-8b-instant',
    ];

    final activeIds = models.where((m) => m.active).map((m) => m.id).toSet();

    for (final id in preferred) {
      if (activeIds.contains(id)) return id;
    }

    // Fallback: first active model.
    final firstActive = models.where((m) => m.active).firstOrNull;
    return firstActive?.id ?? 'llama-3.3-70b-versatile';
  }
}
