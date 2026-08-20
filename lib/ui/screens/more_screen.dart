import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/announcements_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

/// "More" screen — lists secondary feature screens that don't fit in the
/// main bottom navigation.
///
/// AI Advisor is accessed via the floating chat bubble (not here).
/// Activity Logs is accessed via Settings → Activity Logs.
///
/// Only feature screens remain here: Categories, Stock, Reports,
/// Announcements.
///
/// Trash Bin has been moved to Settings → System / Management.
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
