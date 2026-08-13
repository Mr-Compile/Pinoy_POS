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

    if (isTablet) {
      return Scaffold(
        body: Row(
          children: [
            _buildNavigationRail(tabs),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: _getScreen(tabs[_selectedIndex].screen),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: _getScreen(tabs[_selectedIndex].screen),
      bottomNavigationBar: _buildBottomNavigationBar(tabs),
    );
  }

  NavigationBar _buildBottomNavigationBar(List<AppTab> tabs) {
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
                selectedIcon: Icon(tab.selectedIcon ?? tab.icon),
                label: tab.label,
                tooltip: tab.label,
              ))
          .toList(),
    );
  }

  NavigationRail _buildNavigationRail(List<AppTab> tabs) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      extended: MediaQuery.of(context).size.width >= 900,
      minExtendedWidth: 200,
      destinations: tabs
          .map((tab) => NavigationRailDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon ?? tab.icon),
                label: Text(tab.label),
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
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'POS',
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart,
            screen: const POSScreen(),
          ),
          AppTab(
            label: 'Products',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: const ProductsScreen(),
          ),
          AppTab(
            label: 'Reports',
            icon: Icons.analytics_outlined,
            selectedIcon: Icons.analytics,
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
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'POS',
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart,
            screen: const POSScreen(),
          ),
          AppTab(
            label: 'Sales',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            screen: const SalesScreen(),
          ),
          AppTab(
            label: 'Reports',
            icon: Icons.analytics_outlined,
            selectedIcon: Icons.analytics,
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
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
          ),
          AppTab(
            label: 'Users',
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            screen: const UsersScreen(),
          ),
          AppTab(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
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
  final IconData? selectedIcon;
  final Widget screen;

  AppTab({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.screen,
  });
}
