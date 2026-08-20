import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// A single entry shown on the "More" screen.
///
/// This is the SINGLE SOURCE OF TRUTH for what appears behind the More
/// navigation item. Both [MoreScreen] (which renders the entries) and
/// [AppShell] (which decides whether to show the More tab at all) read
/// from [MoreEntry.all] so the two can never drift apart.
class MoreEntry {
  final IconData icon;
  final String title;
  final String permission;
  final String routeName;
  final Widget screen;

  const MoreEntry({
    required this.icon,
    required this.title,
    required this.permission,
    required this.routeName,
    required this.screen,
  });

  /// Every possible More entry, in display order.
  ///
  /// AI Advisor is accessed via the floating chat bubble (not here).
  /// Activity Logs is accessed via Settings → Activity Logs.
  /// Trash Bin has been moved to Settings → System / Management.
  static const List<MoreEntry> all = [
    MoreEntry(
      icon: Icons.category_outlined,
      title: 'Categories',
      permission: 'view_categories',
      routeName: 'categories',
      screen: CategoriesScreen(),
    ),
    MoreEntry(
      icon: Icons.warehouse_outlined,
      title: 'Stock',
      permission: 'add_stock',
      routeName: 'stock',
      screen: StockScreen(),
    ),
    MoreEntry(
      icon: Icons.analytics_outlined,
      title: 'Reports',
      permission: 'view_reports',
      routeName: 'reports',
      screen: ReportsScreen(),
    ),
    MoreEntry(
      icon: Icons.campaign_outlined,
      title: 'Announcements',
      permission: 'view_announcements',
      routeName: 'announcements',
      screen: AnnouncementsScreen(),
    ),
  ];

  /// Returns only the entries the current user is authorized to access.
  ///
  /// [hasPermission] is the role-based permission checker (typically
  /// `authNotifier.hasPermission`). This is the single computation that
  /// both the More tab visibility and the More screen contents use.
  static List<MoreEntry> accessibleFor(bool Function(String) hasPermission) {
    return all.where((e) => hasPermission(e.permission)).toList();
  }
}

/// "More" screen — lists secondary feature screens that don't fit in the
/// main bottom navigation.
///
/// The entries shown here are exactly [MoreEntry.accessibleFor] the current
/// user's permissions. The More tab itself is only created by [AppShell]
/// when this list is non-empty, so this screen is never reached with zero
/// entries.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final entries = MoreEntry.accessibleFor(authNotifier.hasPermission);

    return Scaffold(
      appBar: const AppHeader(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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

  Widget _buildEntryCard(BuildContext context, WidgetRef ref, MoreEntry entry) {
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
