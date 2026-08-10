import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/dashboard_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/reports_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/more_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/screens/categories_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (authState.user == null) {
      return const LoginScreen();
    }

    final role = authState.user!.role;
    final tabs = _getTabsForRole(role);

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      body: _getScreen(tabs[_selectedIndex].screen),
      bottomNavigationBar: isTablet ? null : _buildBottomNavigationBar(tabs),
    );
  }

  Widget _buildBottomNavigationBar(List<AppTab> tabs) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      destinations: tabs
          .map((tab) => NavigationDestination(
                icon: Icon(tab.icon),
                label: tab.label,
              ))
          .toList(),
    );
  }

  Widget _getScreen(Widget screen) {
    return screen;
  }

  List<AppTab> _getTabsForRole(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'POS',
            icon: Icons.point_of_sale,
            screen: const POSScreen(),
          ),
          AppTab(
            label: 'Products',
            icon: Icons.inventory_2,
            screen: const ProductsScreen(),
          ),
          AppTab(
            label: 'Reports',
            icon: Icons.bar_chart,
            screen: const ReportsScreen(),
          ),
          AppTab(
            label: 'More',
            icon: Icons.more_horiz,
            screen: const MoreScreen(),
          ),
        ];
      case UserRole.staff:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'POS',
            icon: Icons.point_of_sale,
            screen: const POSScreen(),
          ),
          AppTab(
            label: 'Sales',
            icon: Icons.receipt_long,
            screen: const SalesScreen(),
          ),
          AppTab(
            label: 'Reports',
            icon: Icons.bar_chart,
            screen: const ReportsScreen(),
          ),
          AppTab(
            label: 'More',
            icon: Icons.more_horiz,
            screen: const MoreScreen(),
          ),
        ];
      case UserRole.admin:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'Categories',
            icon: Icons.category,
            screen: const CategoriesScreen(),
          ),
          AppTab(
            label: 'Products',
            icon: Icons.inventory_2,
            screen: const ProductsScreen(),
          ),
          AppTab(
            label: 'Users',
            icon: Icons.people,
            screen: const UsersScreen(),
          ),
          AppTab(
            label: 'Settings',
            icon: Icons.settings,
            screen: const SettingsScreen(),
          ),
          AppTab(
            label: 'More',
            icon: Icons.more_horiz,
            screen: const MoreScreen(),
          ),
        ];
    }
  }
}

class AppTab {
  final String label;
  final IconData icon;
  final Widget screen;

  AppTab({
    required this.label,
    required this.icon,
    required this.screen,
  });
}
