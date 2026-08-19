import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  List<ActivityLog> _activities = [];
  bool _isLoading = true;
  String? _loadError;

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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _activities.length,
              itemBuilder: (context, index) {
                final activity = _activities[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(_getActionIcon(activity.action)),
                    title: Text(activity.action),
                    subtitle: Text(
                      '${activity.entity ?? 'N/A'} • ${activity.createdAt.toLocal().toString().split('.')[0]}',
                    ),
                    trailing: activity.details != null
                        ? Text(
                            activity.details!,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }

  IconData _getActionIcon(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('login') || lower.contains('logout')) {
      return Icons.login;
    }
    if (lower.contains('create') || lower.contains('add')) {
      return Icons.add_circle;
    }
    if (lower.contains('update') || lower.contains('edit')) {
      return Icons.edit;
    }
    if (lower.contains('delete') || lower.contains('remove')) {
      return Icons.delete;
    }
    if (lower.contains('void')) {
      return Icons.cancel;
    }
    return Icons.history;
  }
}
