import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/notifications_screen.dart';
import 'package:pinoy_pos/ui/screens/profile_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    final entries = <_MoreEntry>[];

    // --- Business modules (Owner / Staff) ---
    // Categories: Staff can view and toggle status, so gate on
    // view_categories (not edit_categories) so Staff can reach the screen.
    if (authNotifier.hasPermission('view_categories')) {
      entries.add(_MoreEntry(
        icon: Icons.category,
        title: 'Categories',
        permission: 'view_categories',
        routeName: 'categories',
        screen: const CategoriesScreen(),
      ));
    }
    if (authNotifier.hasPermission('add_stock')) {
      entries.add(_MoreEntry(
        icon: Icons.warehouse,
        title: 'Stock',
        permission: 'add_stock',
        routeName: 'stock',
        screen: const StockScreen(),
      ));
    }
    // Reports: reachable from More because the mobile bottom navigation is
    // capped at 4 primary destinations + "More". Reports is a 5th primary
    // destination for Owner/Staff and would otherwise be unreachable.
    if (authNotifier.hasPermission('view_reports')) {
      entries.add(_MoreEntry(
        icon: Icons.analytics,
        title: 'Reports',
        permission: 'view_reports',
        routeName: 'reports',
        screen: const ReportsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_announcements')) {
      entries.add(_MoreEntry(
        icon: Icons.campaign,
        title: 'Announcements',
        permission: 'view_announcements',
        routeName: 'announcements',
        screen: const AnnouncementsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_ai_advisor')) {
      entries.add(_MoreEntry(
        icon: Icons.smart_toy,
        title: 'AI Advisor',
        permission: 'view_ai_advisor',
        routeName: 'ai_advisor',
        screen: const AIAdvisorScreen(),
      ));
    }

    // --- System modules (System Admin) ---
    if (authNotifier.hasPermission('manage_users')) {
      entries.add(_MoreEntry(
        icon: Icons.people,
        title: 'Users',
        permission: 'manage_users',
        routeName: 'users',
        screen: const UsersScreen(),
      ));
    }
    if (authNotifier.hasPermission('backup_restore')) {
      entries.add(_MoreEntry(
        icon: Icons.backup,
        title: 'Backup & Restore',
        permission: 'backup_restore',
        routeName: 'backup_restore',
        screen: const BackupRestoreScreen(),
      ));
    }

    // --- Shared modules ---
    if (authNotifier.hasPermission('view_settings')) {
      entries.add(_MoreEntry(
        icon: Icons.settings,
        title: 'Settings',
        permission: 'view_settings',
        routeName: 'settings',
        screen: const SettingsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_trash')) {
      entries.add(_MoreEntry(
        icon: Icons.delete_outline,
        title: 'Trash Bin',
        permission: 'view_trash',
        routeName: 'trash',
        screen: const TrashScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_activity_logs')) {
      entries.add(_MoreEntry(
        icon: Icons.history,
        title: 'Activity Logs',
        permission: 'view_activity_logs',
        routeName: 'activity_logs',
        screen: const ActivityLogsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_notifications')) {
      entries.add(_MoreEntry(
        icon: Icons.notifications,
        title: 'Notifications',
        permission: 'view_notifications',
        routeName: 'notifications',
        screen: const NotificationsScreen(),
      ));
    }

    // Profile (all roles)
    entries.add(_MoreEntry(
      icon: Icons.person,
      title: 'Profile',
      permission: null,
      routeName: 'profile',
      screen: const ProfileScreen(),
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Grid of navigation entries
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: entries.map((entry) {
              return _buildEntryCard(context, ref, entry);
            }).toList(),
          ),
          const SizedBox(height: 24),
          // Logout button
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: colorScheme.error),
              title: Text(
                'Logout',
                style: TextStyle(color: colorScheme.error),
              ),
              trailing: Icon(Icons.chevron_right, color: colorScheme.error),
              onTap: () async {
                final confirmed = await AppDialogService.logoutConfirm(context);
                if (confirmed == true) {
                  await authNotifier.logout();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(BuildContext context, WidgetRef ref, _MoreEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (entry.permission == null) {
            // No permission required (e.g. Profile)
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => entry.screen),
            );
          } else {
            RouteGuard.pushIfAuthorized(
              context,
              ref,
              screen: entry.screen,
              permission: entry.permission!,
              routeName: entry.routeName,
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(entry.icon, size: 32, color: colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                entry.title,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreEntry {
  final IconData icon;
  final String title;
  final String? permission;
  final String routeName;
  final Widget screen;

  _MoreEntry({
    required this.icon,
    required this.title,
    this.permission,
    required this.routeName,
    required this.screen,
  });
}
