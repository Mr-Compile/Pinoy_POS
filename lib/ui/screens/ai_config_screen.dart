import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/groq_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';

/// Admin-only screen for configuring the Groq AI integration.
///
/// Permission: `manage_ai_config` (System Admin only).
///
/// The Admin can:
/// - Add / edit / replace the Groq API key
/// - Test the API connection (real HTTP request to Groq Models API)
/// - Refresh available models from Groq
/// - Select the default AI model (stores the exact model ID)
/// - View connection status
///
/// The API key is stored in the SQLite settings table and is never
/// displayed as plain text after saving. The field is obscured by
/// default with a show/hide toggle for entry only.
///
/// The Owner never sees this screen and never sees the API key.
class AIConfigScreen extends ConsumerStatefulWidget {
  const AIConfigScreen({super.key});

  @override
  ConsumerState<AIConfigScreen> createState() => _AIConfigScreenState();
}

class _AIConfigScreenState extends ConsumerState<AIConfigScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isRefreshingModels = false;
  bool _isConfigured = false;
  String? _loadError;

  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedModel = '';
  bool _obscureKey = true;

  // Connection status: null = unknown, true = connected, false = failed.
  bool? _connectionStatus;
  String? _connectionMessage;

  // Available models from Groq.
  List<GroqModel> _availableModels = [];
  String _modelSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final settingsService = ref.read(settingsServiceProvider);
      final configured = await settingsService.isGroqConfigured();
      final model = await settingsService.getGroqModel();

      if (mounted) {
        setState(() {
          _isConfigured = configured;
          _selectedModel = model;
          // Never load the raw key into the text field. If configured,
          // show a placeholder so the admin knows a key exists.
          _apiKeyController.text = configured ? '••••••••••••••••' : '';
          _isLoading = false;
        });

        // Load cached models if available.
        final cached = settingsService.getCachedModels();
        if (cached.isNotEmpty) {
          setState(() => _availableModels = cached);
        }
      }
    } catch (e, st) {
      _log('loadConfig failed', e, st);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load AI configuration.';
        });
      }
    }
  }

  // ── Test Connection ───────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    // Determine which key to test.
    final keyInput = _apiKeyController.text.trim();
    String keyToTest;

    if (keyInput.isEmpty) {
      AppDialogService.warning(context,
          title: 'No API Key',
          message: 'Please enter a Groq API key before testing the connection.');
      return;
    }

    if (keyInput == '••••••••••••••••') {
      // Use the saved key.
      final settingsService = ref.read(settingsServiceProvider);
      keyToTest = await settingsService.getGroqApiKey() ?? '';
      if (keyToTest.isEmpty) {
        if (mounted) {
          AppDialogService.warning(context,
              title: 'No Saved Key',
              message: 'No API key is saved. Please enter a new key.');
        }
        return;
      }
    } else {
      keyToTest = keyInput;
    }

    setState(() {
      _isTesting = true;
      _connectionStatus = null;
      _connectionMessage = null;
    });

    try {
      final settingsService = ref.read(settingsServiceProvider);
      final result = await settingsService.testGroqConnection(keyToTest);

      if (mounted) {
        setState(() {
          _isTesting = false;
          _connectionStatus = result.success;
          _connectionMessage = result.message;
          if (result.success && result.models.isNotEmpty) {
            _availableModels = result.models;
          }
        });

        await AppDialogService.aiTestConnectionResult(
          context,
          isConnected: result.success,
          message: result.message,
        );
      }
    } catch (e, st) {
      _log('testConnection failed', e, st);
      if (mounted) {
        setState(() {
          _isTesting = false;
          _connectionStatus = false;
          _connectionMessage = 'An unexpected error occurred.';
        });
        await AppDialogService.aiTestConnectionResult(
          context,
          isConnected: false,
          message: 'An unexpected error occurred during the connection test.',
        );
      }
    }
  }

  // ── Refresh Models ────────────────────────────────────────────────────

  Future<void> _refreshModels() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    // Check if a key is available.
    final keyInput = _apiKeyController.text.trim();
    if (keyInput.isEmpty || keyInput == '••••••••••••••••') {
      final settingsService = ref.read(settingsServiceProvider);
      final hasKey = await settingsService.isGroqConfigured();
      if (!hasKey) {
        if (mounted) {
          AppDialogService.warning(context,
              title: 'No API Key',
              message: 'Please enter and save an API key before refreshing models.');
        }
        return;
      }
    }

    setState(() => _isRefreshingModels = true);

    try {
      final settingsService = ref.read(settingsServiceProvider);
      final result = await settingsService.refreshModels();

      if (mounted) {
        setState(() => _isRefreshingModels = false);

        if (result.success) {
          setState(() => _availableModels = result.models);
          // If the current selected model is not in the list, suggest
          // the recommended default.
          final modelExists = result.models.any((m) =>
              m.id == _selectedModel && m.active);
          if (!modelExists && result.models.isNotEmpty) {
            final recommended =
                settingsService.getRecommendedModel(result.models);
            setState(() => _selectedModel = recommended);
          }
          await AppDialogService.success(
            context,
            title: 'Models Refreshed',
            message: '${result.models.length} models are currently available.',
            primaryLabel: 'Done',
          );
        } else {
          final retry = await AppDialogService.aiRefreshModelsFailed(
            context,
            reason: result.errorMessage,
          );
          if (retry && mounted) _refreshModels();
        }
      }
    } catch (e, st) {
      _log('refreshModels failed', e, st);
      if (mounted) {
        setState(() => _isRefreshingModels = false);
        final retry = await AppDialogService.aiRefreshModelsFailed(
          context,
          reason: 'An unexpected error occurred.',
        );
        if (retry && mounted) _refreshModels();
      }
    }
  }

  // ── Save Configuration ────────────────────────────────────────────────

  Future<void> _saveConfig() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final keyInput = _apiKeyController.text.trim();
    final model = _selectedModel;

    if (keyInput.isEmpty) {
      AppDialogService.warning(context,
          title: 'Empty API Key', message: 'Please enter a Groq API key.');
      return;
    }

    if (model.isEmpty) {
      AppDialogService.warning(context,
          title: 'No Model Selected', message: 'Please select a Groq model.');
      return;
    }

    // Determine if the key is being changed.
    final isKeyPlaceholder = keyInput == '••••••••••••••••';

    setState(() => _isSaving = true);

    try {
      final settingsService = ref.read(settingsServiceProvider);

      if (isKeyPlaceholder) {
        // Key unchanged — only update the model.
        final currentKey = await settingsService.getGroqApiKey();
        if (currentKey == null || currentKey.isEmpty) {
          if (mounted) {
            setState(() => _isSaving = false);
            AppDialogService.warning(context,
                title: 'No Saved Key',
                message: 'The API key field shows a placeholder but no key is saved. Please enter a new key.');
          }
          return;
        }
        final success = await settingsService.saveGroqConfig(
          apiKey: currentKey,
          model: model,
        );
        if (mounted) {
          setState(() => _isSaving = false);
          if (success) {
            await AppDialogService.success(context,
                title: 'Saved',
                message: 'AI model updated successfully.');
            _loadConfig();
            await _notifyChatProvider();
          } else {
            AppDialogService.error(context,
                title: 'Save Failed',
                message: 'Failed to save AI configuration.');
          }
        }
      } else {
        // New key entered.
        final success = await settingsService.saveGroqConfig(
          apiKey: keyInput,
          model: model,
        );
        if (mounted) {
          setState(() => _isSaving = false);
          if (success) {
            // Mask the key after saving.
            setState(() {
              _apiKeyController.text = '••••••••••••••••';
              _isConfigured = true;
            });
            await AppDialogService.success(context,
                title: 'Saved',
                message: 'Groq AI configuration saved successfully.');
            _loadConfig();
            await _notifyChatProvider();
          } else {
            AppDialogService.error(context,
                title: 'Save Failed',
                message: 'Failed to save AI configuration.');
          }
        }
      }
    } catch (e, st) {
      _log('saveConfig failed', e, st);
      if (mounted) {
        setState(() => _isSaving = false);
        AppDialogService.error(context,
            title: 'Save Failed',
            message: 'Failed to save AI configuration.');
      }
    }
  }

  // ── Clear Configuration ───────────────────────────────────────────────

  Future<void> _clearConfig() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Clear AI Configuration?',
      message:
          'This will remove the Groq API key and model. The AI Advisor will be unavailable until reconfigured.',
      confirmLabel: 'Clear',
      destructive: true,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final settingsService = ref.read(settingsServiceProvider);
      final success = await settingsService.clearGroqConfig();
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isConfigured = false;
          _connectionStatus = null;
          _connectionMessage = null;
          _availableModels = [];
          _selectedModel = '';
          _apiKeyController.clear();
        });
        if (success) {
          await AppDialogService.success(context,
              title: 'Cleared',
              message: 'AI configuration has been cleared.');
          await _notifyChatProvider();
        } else {
          AppDialogService.error(context,
              title: 'Error', message: 'Failed to clear AI configuration.');
        }
      }
    } catch (e, st) {
      _log('clearConfig failed', e, st);
      if (mounted) {
        setState(() => _isSaving = false);
        AppDialogService.error(context,
            title: 'Error', message: 'Failed to clear AI configuration.');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'AI Integration', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'AI Integration', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load',
          message: _loadError,
          onRetry: _loadConfig,
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'AI Integration',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadConfig,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIntroCard(context),
            const SizedBox(height: 16),
            _buildStatusCard(context),
            const SizedBox(height: 16),
            _buildApiKeyCard(context),
            const SizedBox(height: 16),
            _buildModelSelectionCard(context),
          ],
        ),
      ),
    );
  }

  // ── Intro Card ────────────────────────────────────────────────────────

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.smart_toy, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Integration',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Configure the Groq AI service used by the Owner\'s Business Advisor.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Card ───────────────────────────────────────────────────────

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isConnected = _connectionStatus == true;
    final isFailed = _connectionStatus == false;

    final statusColor = isConnected
        ? AppSemanticColors.resolve(
            AppSemanticColors.success, theme.brightness)
        : isFailed
            ? cs.error
            : cs.onSurfaceVariant;
    final statusIcon = isConnected
        ? Icons.check_circle
        : isFailed
            ? Icons.error_outline
            : _isConfigured
                ? Icons.info_outline
                : Icons.help_outline;
    final statusText = isConnected
        ? 'Connected'
        : isFailed
            ? 'Connection Failed'
            : _isConfigured
                ? 'Configured (not tested)'
                : 'Not Configured';

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(statusText, style: theme.textTheme.bodyLarge),
                        ],
                      ),
                      if (_connectionMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _connectionMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── API Key Card ──────────────────────────────────────────────────────

  Widget _buildApiKeyCard(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Groq API Key', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'The API key is stored locally and never displayed after saving.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  tooltip: _obscureKey ? 'Show' : 'Hide',
                  onPressed: () {
                    setState(() => _obscureKey = !_obscureKey);
                  },
                ),
                hintText: _isConfigured
                    ? 'Enter a new key to replace'
                    : 'Enter Groq API key',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.wifi_protected_setup),
                    label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Model Selection Card ──────────────────────────────────────────────

  Widget _buildModelSelectionCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Model', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isRefreshingModels ? null : _refreshModels,
                  icon: _isRefreshingModels
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(
                      _isRefreshingModels ? 'Refreshing...' : 'Refresh Models'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select the model the AI Advisor will use. The exact model ID is stored.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_availableModels.isEmpty)
              _buildNoModelsState(context)
            else
              _buildModelList(context),
            const SizedBox(height: 16),
            if (_selectedModel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Selected Model',
                                style: theme.textTheme.bodySmall),
                            Text(_selectedModel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isConfigured)
                  TextButton(
                    onPressed: _isSaving ? null : _clearConfig,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                    ),
                    child: const Text('Clear'),
                  ),
                const SizedBox(width: 8),
                LoadingButton(
                  isLoading: _isSaving,
                  onPressed: _saveConfig,
                  label: 'Save Configuration',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoModelsState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.memory, size: 40,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No models loaded',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Test the connection or tap "Refresh Models" to fetch the latest available models from Groq.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildModelList(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Filter models by search query.
    final filtered = _modelSearchQuery.isEmpty
        ? _availableModels
        : _availableModels
            .where((m) => m.id.toLowerCase().contains(_modelSearchQuery.toLowerCase()))
            .toList();

    // Sort: selected model first, then by id.
    filtered.sort((a, b) {
      if (a.id == _selectedModel) return -1;
      if (b.id == _selectedModel) return 1;
      return a.id.compareTo(b.id);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        TextField(
          decoration: InputDecoration(
            labelText: 'Search Models',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            isDense: true,
          ),
          onChanged: (value) {
            setState(() => _modelSearchQuery = value);
          },
        ),
        const SizedBox(height: 12),
        Text('${filtered.length} models available',
            style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                )),
        const SizedBox(height: 8),
        // Model list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final model = filtered[index];
              final isSelected = model.id == _selectedModel;
              return _buildModelTile(context, model, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelTile(
      BuildContext context, GroqModel model, bool isSelected) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: isSelected,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
          size: 22,
        ),
        title: Text(
          model.id,
          style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('by ${model.ownedBy}',
                style: theme.textTheme.bodySmall),
            if (model.contextWindow != null)
              Text('Context: ${_formatContext(model.contextWindow!)} tokens',
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: model.active
                        ? AppSemanticColors.resolve(
                                AppSemanticColors.success, theme.brightness)
                            .withValues(alpha: 0.1)
                        : cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    model.active ? 'Active' : 'Inactive',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: model.active
                          ? AppSemanticColors.resolve(
                              AppSemanticColors.success, theme.brightness)
                          : cs.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: isSelected
            ? Icon(Icons.check, color: cs.primary)
            : TextButton(
                onPressed: () {
                  setState(() => _selectedModel = model.id);
                },
                child: const Text('Select'),
              ),
        onTap: () {
          setState(() => _selectedModel = model.id);
        },
      ),
    );
  }

  String _formatContext(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(tokens % 1000 == 0 ? 0 : 1)}K';
    }
    return tokens.toString();
  }



  /// Notifies the shared AI chat provider that the configuration has
  /// changed, so the floating chat head, dashboard AI card, and any open
  /// chat panel reflect the new status immediately.
  Future<void> _notifyChatProvider() async {
    try {
      await ref.read(aiAdvisorChatProvider.notifier).checkConfig();
    } catch (e, st) {
      _log('notifyChatProvider failed', e, st);
    }
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[AIConfigScreen] $message: $error\n$stackTrace');
    }
  }
}
