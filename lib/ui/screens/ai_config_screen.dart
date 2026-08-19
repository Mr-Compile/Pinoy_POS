import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';

/// Admin-only screen for configuring the Groq AI API key and model.
///
/// Permission: `manage_ai_config` (System Admin only).
/// The API key is stored in the SQLite settings table and is never
/// displayed as plain text after saving. The field is obscured by
/// default with a show/hide toggle for entry only.
class AIConfigScreen extends ConsumerStatefulWidget {
  const AIConfigScreen({super.key});

  @override
  ConsumerState<AIConfigScreen> createState() => _AIConfigScreenState();
}

class _AIConfigScreenState extends ConsumerState<AIConfigScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isConfigured = false;
  String? _loadError;

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  bool _obscureKey = true;

  static const List<String> _availableModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'llama3-70b-8192',
    'llama3-8b-8192',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
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
          _modelController.text = model;
          // Never load the raw key into the text field. If configured,
          // show a placeholder so the admin knows a key exists.
          _apiKeyController.text = configured ? '••••••••••••••••' : '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load AI configuration.';
        });
      }
    }
  }

  Future<void> _saveConfig() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final keyInput = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    // If the field still shows the placeholder, the admin didn't change
    // the key — don't overwrite the stored key with the placeholder.
    if (keyInput.isEmpty) {
      AppDialogService.warning(context,
          title: 'Empty API Key', message: 'Please enter a Groq API key.');
      return;
    }

    if (keyInput == '••••••••••••••••') {
      // Key unchanged — only update the model if it changed.
      AppDialogService.warning(context,
          title: 'No Changes',
          message:
              'The API key field is unchanged. To update the key, clear the placeholder and enter a new key.');
      return;
    }

    if (model.isEmpty) {
      AppDialogService.warning(context,
          title: 'Empty Model', message: 'Please select a Groq model.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final settingsService = ref.read(settingsServiceProvider);
      final success = await settingsService.saveGroqConfig(
        apiKey: keyInput,
        model: model,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        if (success) {
          await AppDialogService.success(context,
              title: 'Saved',
              message: 'Groq AI configuration saved successfully.');
          _loadConfig();
        } else {
          AppDialogService.error(context,
              title: 'Save Failed',
              message: 'Failed to save AI configuration.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppDialogService.error(context,
            title: 'Save Failed',
            message: 'Failed to save AI configuration.');
      }
    }
  }

  Future<void> _clearConfig() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('manage_ai_config')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear AI Configuration?'),
        content: const Text(
            'This will remove the Groq API key and model. The AI Advisor will be unavailable until reconfigured.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final settingsService = ref.read(settingsServiceProvider);
      final success = await settingsService.clearGroqConfig();
      if (mounted) {
        setState(() => _isSaving = false);
        if (success) {
          await AppDialogService.success(context,
              title: 'Cleared',
              message: 'AI configuration has been cleared.');
          _loadConfig();
        } else {
          AppDialogService.error(context,
              title: 'Error', message: 'Failed to clear AI configuration.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppDialogService.error(context,
            title: 'Error', message: 'Failed to clear AI configuration.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'AI Configuration', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'AI Configuration', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load',
          message: _loadError,
          onRetry: _loadConfig,
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'AI Configuration',
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
            // Status card.
            AppCard(
              child: Row(
                children: [
                  Icon(
                    _isConfigured ? Icons.check_circle : Icons.error_outline,
                    color: _isConfigured ? colorScheme.primary : colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isConfigured
                              ? 'AI Advisor is configured'
                              : 'AI Advisor is not configured',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isConfigured
                              ? 'The Owner can use the AI Advisor.'
                              : 'Configure the Groq API key to enable the AI Advisor for the Owner.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Configuration form.
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Groq API Key',
                        style: theme.textTheme.titleSmall),
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
                            _obscureKey
                                ? Icons.visibility
                                : Icons.visibility_off,
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
                    const SizedBox(height: 16),
                    Text('Groq Model', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Select the model the AI Advisor will use.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _availableModels.contains(_modelController.text)
                          ? _modelController.text
                          : _availableModels.first,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.memory),
                      ),
                      items: _availableModels
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _modelController.text = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_isConfigured)
                          TextButton(
                            onPressed: _isSaving ? null : _clearConfig,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error,
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
            ),
            const SizedBox(height: 16),

            // Help text.
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('How to get a Groq API Key',
                            style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Visit console.groq.com and sign in.\n'
                      '2. Navigate to API Keys.\n'
                      '3. Create a new API key.\n'
                      '4. Copy and paste it above.\n'
                      '5. Select a model and save.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
