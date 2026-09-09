import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

enum _LogFilter { all, sales, stock, users }

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  List<ActivityLog> _activities = [];
  bool _isLoading = true;
  String? _loadError;

  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final activityLogService = ref.read(activityLogServiceProvider);
      final activities = await activityLogService.getRecentActivities();
      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load activity logs. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_activity_logs')) {
      return Scaffold(
        appBar: AppHeader(title: 'Activity Logs', showBackButton: true),
        body: const Center(
          child: Text('You do not have permission to view activity logs.'),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'Activity Logs', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'Activity Logs', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load Activity Logs',
          message: _loadError,
          onRetry: _loadActivities,
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'Activity Logs',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadActivities,
          ),
        ],
      ),
      body: _activities.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No Activity',
              message: 'User actions will appear here',
            )
          : _filteredActivities.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterChips(),
                    Expanded(
                      child: EmptyState(
                        icon: Icons.filter_alt_off,
                        title: 'No matching logs',
                        message:
                            'Try a different filter to see more activity.',
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterChips(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredActivities.length,
                        itemBuilder: (context, index) {
                          final activity = _filteredActivities[index];
                          return _buildLogRow(activity);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  List<ActivityLog> get _filteredActivities {
    return _activities.where((a) {
      switch (_filter) {
        case _LogFilter.sales:
          if (!_isSalesLog(a)) return false;
          break;
        case _LogFilter.stock:
          if (!_isStockLog(a)) return false;
          break;
        case _LogFilter.users:
          if (!_isUserLog(a)) return false;
          break;
        case _LogFilter.all:
          break;
      }
      return true;
    }).toList();
  }

  bool _isSalesLog(ActivityLog a) {
    final e = a.entity?.toLowerCase() ?? '';
    final act = a.action.toLowerCase();
    return e == 'sale' || act.contains('sale') || act.contains('gcash');
  }

  bool _isStockLog(ActivityLog a) {
    final e = a.entity?.toLowerCase() ?? '';
    return e == 'product' || e == 'stock' || e == 'category';
  }

  bool _isUserLog(ActivityLog a) {
    final e = a.entity?.toLowerCase() ?? '';
    return e == 'user' || e == 'staff';
  }

  Widget _buildLogRow(ActivityLog activity) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final icon = _logIcon(activity);
    final color = _logColor(activity, brightness);
    final title = activity.details?.isNotEmpty == true
        ? activity.details!
        : _humanizeAction(activity.action);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'by ${_humanizeActor(activity)} · ${_formatTime(activity.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final cs = Theme.of(context).colorScheme;
    final filters = [
      _LogFilter.all,
      _LogFilter.sales,
      _LogFilter.stock,
      _LogFilter.users,
    ];
    final labels = {
      _LogFilter.all: 'All',
      _LogFilter.sales: 'Sales',
      _LogFilter.stock: 'Stock',
      _LogFilter.users: 'Users',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: Spacing.sm,
        children: filters.map((filter) {
          final isSelected = _filter == filter;
          return ChoiceChip(
            label: Text(labels[filter]!),
            selected: isSelected,
            onSelected: (_) => setState(() => _filter = filter),
            selectedColor: cs.primaryContainer,
            labelStyle: TextStyle(
              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          );
        }).toList(),
      ),
    );
  }

  String _humanizeAction(String action) {
    return action
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _humanizeActor(ActivityLog a) {
    return _humanizeAction(a.role ?? 'User');
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDay = DateTime(date.year, date.month, date.day);
    if (logDay == today) return DateFormat.jm().format(date.toLocal());
    if (logDay == today.subtract(const Duration(days: 1))) {
      return 'yesterday';
    }
    return DateFormat.yMMMd().format(date.toLocal());
  }

  IconData _logIcon(ActivityLog a) {
    final e = a.entity?.toLowerCase() ?? '';
    if (e == 'sale') return Icons.receipt_outlined;
    if (e == 'product' || e == 'stock' || e == 'category') {
      return Icons.inventory_2_outlined;
    }
    if (e == 'user' || e == 'staff') return Icons.person_outlined;
    return Icons.history;
  }

  Color _logColor(ActivityLog a, Brightness brightness) {
    final e = a.entity?.toLowerCase() ?? '';
    if (e == 'sale') return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
    if (e == 'product' || e == 'stock' || e == 'category') {
      return AppSemanticColors.resolve(AppSemanticColors.success, brightness);
    }
    if (e == 'user' || e == 'staff') {
      return AppSemanticColors.resolve(AppSemanticColors.violet, brightness);
    }
    return AppSemanticColors.resolve(AppSemanticColors.neutral, brightness);
  }
}
