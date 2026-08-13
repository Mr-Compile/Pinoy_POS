import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/data/models/activity_log.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  final ActivityLogService _activityLogService = ActivityLogService();
  List<ActivityLog> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() => _isLoading = true);
    final activities = await _activityLogService.getRecentActivities();
    if (mounted) {
      setState(() {
        _activities = activities;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_activity_logs')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity Logs')),
        body: const Center(
          child: Text('You do not have permission to view activity logs.'),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity Logs')),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
