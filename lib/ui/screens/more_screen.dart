import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (authNotifier.hasPermission('edit_categories'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.category),
                title: const Text('Categories'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CategoriesScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('edit_categories'))
            const SizedBox(height: 12),
          if (authNotifier.hasPermission('add_stock'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Stock'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('add_stock'))
            const SizedBox(height: 12),
          if (authNotifier.hasPermission('manage_users'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Users'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UsersScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('manage_users'))
            const SizedBox(height: 12),
          if (authNotifier.hasPermission('view_settings'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('view_settings'))
            const SizedBox(height: 12),
          if (authNotifier.hasPermission('view_ai_advisor'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.psychology),
                title: const Text('AI Advisor'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AIAdvisorScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('view_ai_advisor'))
            const SizedBox(height: 12),
          if (authNotifier.hasPermission('view_trash'))
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Trash Bin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrashScreen(),
                    ),
                  );
                },
              ),
            ),
          if (authNotifier.hasPermission('view_trash'))
            const SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                final confirmed = await EnhancedDialogs.showLogoutDialog(
                  context: context,
                );
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
}
