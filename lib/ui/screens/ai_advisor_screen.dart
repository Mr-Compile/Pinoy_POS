import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/constants.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/ai_advisor_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Owner-only AI Business Advisor screen.
///
/// Uses [AIAdvisorService] which calls the Groq chat/completions API with
/// real local business data as context. Requires internet access and a
/// configured Groq API key (set by System Admin via [AIConfigScreen]).
///
/// Usage is capped at [AppConstants.maxDailyAIQueries] (10) queries per day
/// per user. The service is authoritative for both permission and the
/// daily limit — the UI only reflects the remaining count and cannot
/// bypass the service check.
class AIAdvisorScreen extends ConsumerStatefulWidget {
  const AIAdvisorScreen({super.key});

  @override
  ConsumerState<AIAdvisorScreen> createState() => _AIAdvisorScreenState();
}

class _AIAdvisorScreenState extends ConsumerState<AIAdvisorScreen> {
  final TextEditingController _queryController = TextEditingController();

  bool _isLoading = false;
  bool _hasResult = false;
  String _resultContent = '';
  int _remainingToday = AppConstants.maxDailyAIQueries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUsage());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _refreshUsage() async {
    final aiUsageService = ref.read(aiUsageServiceProvider);
    final used = await aiUsageService.getTodayUsageCount();
    if (mounted) {
      setState(() {
        _remainingToday =
            (AppConstants.maxDailyAIQueries - used).clamp(0, AppConstants.maxDailyAIQueries);
      });
    }
  }

  // ── Preset queries ───────────────────────────────────────────────────

  static const _presets = <_Preset>[
    _Preset(
      label: 'Business Insights',
      icon: Icons.insights,
      query: 'Give me an overview of my business performance.',
    ),
    _Preset(
      label: 'Sales Analysis',
      icon: Icons.trending_up,
      query: 'Analyze my recent sales performance and suggest improvements.',
    ),
    _Preset(
      label: 'Inventory Recommendations',
      icon: Icons.inventory_2,
      query: 'What inventory actions should I take based on current stock levels?',
    ),
  ];

  // ── Analyze ──────────────────────────────────────────────────────────

  Future<void> _analyze({String? query}) async {
    final q = (query ?? _queryController.text).trim();
    if (q.isEmpty) {
      AppDialogService.warning(context,
          title: 'Empty Query', message: 'Please enter a question for the advisor.');
      return;
    }

    // Permission re-check at the UI layer (service also enforces).
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_ai_advisor')) {
      AppDialogService.accessDenied(context);
      return;
    }

    // Daily limit pre-check (service is authoritative; this is UX only).
    if (_remainingToday <= 0) {
      AppDialogService.warning(context,
          title: 'Daily Limit Reached',
          message:
              'You have used all ${AppConstants.maxDailyAIQueries} AI queries for today. Please try again tomorrow.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final aiAdvisorService = ref.read(aiAdvisorServiceProvider);
      final result = await aiAdvisorService.query(q);

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (result.success) {
        if (mounted) {
          setState(() {
            _hasResult = true;
            _resultContent = result.content ?? 'No response from the advisor.';
          });
        }
      } else {
        // All error types are shown via the centralized dialog system.
        // The error message from the service is safe — it never contains
        // the API key, headers, or stack traces.
        if (mounted) {
          AppDialogService.error(context,
              title: _errorTitle(result), message: result.errorMessage);
        }
      }

      await _refreshUsage();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppDialogService.error(context,
            title: 'Analysis Failed',
            message: 'The advisor could not complete the analysis. Please try again.');
      }
    }
  }

  String _errorTitle(AIAdvisorResult result) {
    if (result.isNotConfigured) return 'Not Configured';
    if (result.isNetworkError) return 'No Internet';
    if (result.isAuthError) return 'Authentication Failed';
    if (result.limitReached) return 'Daily Limit Reached';
    return 'Analysis Failed';
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Business Advisor'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Chip(
                avatar: Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary),
                label: Text('$_remainingToday left today'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header card.
                  AppCard(
                    child: Row(
                      children: [
                        Icon(Icons.psychology, size: 40, color: colorScheme.primary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Business Insights',
                                  style: AppTypography.titleMediumBold(context)),
                              const SizedBox(height: 4),
                              Text(
                                'The advisor analyzes your store\'s real sales, inventory, and product data to provide actionable recommendations. Requires internet access.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Preset query chips.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presets
                        .map((p) => ActionChip(
                              label: Text(p.label),
                              avatar: Icon(p.icon, size: 18),
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      _queryController.text = p.query;
                                      _analyze(query: p.query);
                                    },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),

                  // Free-text query input.
                  TextField(
                    controller: _queryController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What would you like to know about your business?',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.question_answer),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Analyze button.
                  Align(
                    alignment: Alignment.centerRight,
                    child: LoadingButton(
                      isLoading: _isLoading,
                      onPressed: _remainingToday <= 0
                          ? null
                          : () => _analyze(),
                      label: 'Ask Advisor',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.auto_awesome, size: 18),
                          SizedBox(width: 8),
                          Text('Ask Advisor'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Result area.
                  if (_hasResult) ...[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.insights, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Advisor Response',
                                  style: AppTypography.titleMediumBold(context)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                          SelectableText(
                            _resultContent,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _hasResult = false;
                          _resultContent = '';
                          _queryController.clear();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('New Question'),
                    ),
                  ] else if (!_isLoading) ...[
                    const EmptyState(
                      icon: Icons.auto_awesome,
                      title: 'Ask a Question',
                      message:
                          'Choose a preset above or type your own question, then tap "Ask Advisor".',
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Preset {
  final String label;
  final IconData icon;
  final String query;
  const _Preset({required this.label, required this.icon, required this.query});
}
