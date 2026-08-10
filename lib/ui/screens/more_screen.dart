import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/ai_advisor_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/stock_screen.dart';
import 'package:pinoy_pos/ui/screens/trash_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final user = ref.read(authStateProvider).user;
    final role = user?.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          if (role == UserRole.owner || role == UserRole.admin)
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
          if (role == UserRole.owner || role == UserRole.admin)
            const SizedBox(height: 12),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await authNotifier.logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}
