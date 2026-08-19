import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/activity_logs_screen.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// "More" screen — lists secondary feature screens that don't fit in the
/// main bottom navigation.
///
/// NOTE: Settings, Profile, Notifications, Backup & Restore, and AI
/// Configuration have been moved OUT of this screen:
///   - Profile      → profile dropdown (header avatar)
///   - Settings     → profile dropdown (header avatar)
///   - Notifications → notification bell (header)
///   - Backup & Restore → Settings hub (Admin only)
///   - AI Configuration  → Settings hub (Admin only)
///
/// Only feature screens remain here: Categories, Stock, Reports,
/// Announcements, AI Advisor, Users, Trash, Activity Logs.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);

    final entries = <_MoreEntry>[];

    // --- Business modules (Owner / Staff) ---
    if (authNotifier.hasPermission('view_categories')) {
      entries.add(_MoreEntry(
        icon: Icons.category_outlined,
        title: 'Categories',
        permission: 'view_categories',
        routeName: 'categories',
        screen: const CategoriesScreen(),
      ));
    }
    if (authNotifier.hasPermission('add_stock')) {
      entries.add(_MoreEntry(
        icon: Icons.warehouse_outlined,
        title: 'Stock',
        permission: 'add_stock',
        routeName: 'stock',
        screen: const StockScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_reports')) {
      entries.add(_MoreEntry(
        icon: Icons.analytics_outlined,
        title: 'Reports',
        permission: 'view_reports',
        routeName: 'reports',
        screen: const ReportsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_announcements')) {
      entries.add(_MoreEntry(
        icon: Icons.campaign_outlined,
        title: 'Announcements',
        permission: 'view_announcements',
        routeName: 'announcements',
        screen: const AnnouncementsScreen(),
      ));
    }
    if (authNotifier.hasPermission('view_ai_advisor')) {
      entries.add(_MoreEntry(
        icon: Icons.smart_toy_outlined,
        title: 'AI Advisor',
        permission: 'view_ai_advisor',
        routeName: 'ai_advisor',
        screen: const AIAdvisorScreen(),
      ));
    }

    // --- System modules (Admin) ---
    if (authNotifier.hasPermission('manage_users')) {
      entries.add(_MoreEntry(
        icon: Icons.people_outline,
        title: 'Users',
        permission: 'manage_users',
        routeName: 'users',
        screen: const UsersScreen(),
      ));
    }

    // --- Shared modules ---
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
        icon: Icons.history_rounded,
        title: 'Activity Logs',
        permission: 'view_activity_logs',
        routeName: 'activity_logs',
        screen: const ActivityLogsScreen(),
      ));
    }

    return Scaffold(
      appBar: const AppHeader(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No additional screens available.'),
              ),
            )
          else
            GridView.count(
              crossAxisCount:
                  MediaQuery.of(context).size.width >= 600 ? 4 : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: entries.map((entry) {
                return _buildEntryCard(context, ref, entry);
              }).toList(),
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
          RouteGuard.pushIfAuthorized(
            context,
            ref,
            screen: entry.screen,
            permission: entry.permission,
            routeName: entry.routeName,
          );
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
  final String permission;
  final String routeName;
  final Widget screen;

  _MoreEntry({
    required this.icon,
    required this.title,
    required this.permission,
    required this.routeName,
    required this.screen,
  });
}
