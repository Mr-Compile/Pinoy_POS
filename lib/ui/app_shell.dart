import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/ui/screens/dashboard_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
import 'package:pinoy_pos/ui/screens/force_change_password_screen.dart';
import 'package:pinoy_pos/ui/screens/login_screen.dart';
import 'package:pinoy_pos/ui/screens/pin_lock_screen.dart';
import 'package:pinoy_pos/ui/screens/backup_restore_screen.dart';
import 'package:pinoy_pos/ui/screens/settings_screen.dart';
import 'package:pinoy_pos/ui/screens/users_screen.dart';
import 'package:pinoy_pos/ui/screens/more_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_logo.dart';
import 'package:pinoy_pos/ui/widgets/ai_chat_head.dart';
import 'package:pinoy_pos/ui/widgets/ai_chat_panel.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  ProviderSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // ref.listen is only valid inside build(). For a ConsumerStatefulWidget
    // that must react to auth changes from initState, Riverpod 2.x exposes
    // ref.listenManual, which returns a ProviderSubscription we own and
    // must dispose ourselves. This avoids re-subscribing on every rebuild
    // and keeps the navigation-reset side effect out of the build phase.
    _authSubscription = ref.listenManual<AuthState>(
      authStateProvider,
      (previous, next) {
        if (previous?.user?.id != next.user?.id) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _authSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    // AppShell should only be visible when fully authenticated.
    // If the phase changes (e.g. forced password change, PIN lock,
    // or logout), navigate to the appropriate screen.
    if (authState.user == null ||
        authState.phase != AuthSessionPhase.fullyAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (authState.phase) {
          case AuthSessionPhase.fullyAuthenticated:
            break;
          case AuthSessionPhase.passwordAuthenticatedPendingPasswordChange:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ForceChangePasswordScreen()),
              (_) => false,
            );
          case AuthSessionPhase.passwordAuthenticatedPendingPin:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const PinLockScreen()),
              (_) => false,
            );
          case AuthSessionPhase.unauthenticated:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
        }
      });
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final role = authState.user!.role;
    final tabs = _getTabsForRole(role);

    final selectedIndex =
        _selectedIndex < tabs.length ? _selectedIndex : 0;

    // AI Advisor floating chat head -- available to all roles with
    // view_ai_advisor permission (Owner, Admin, Staff).
    final canViewAIAdvisor =
        ref.read(authStateProvider.notifier).hasPermission('view_ai_advisor');
    final aiChatState = ref.watch(aiAdvisorChatProvider);

    if (isTablet) {
      return Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                _buildNavigationRail(tabs, screenWidth, selectedIndex),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: _getScreen(tabs[selectedIndex].screen),
                ),
              ],
            ),
            if (canViewAIAdvisor && !aiChatState.isPanelOpen)
              AIChatHead(userId: authState.user!.id!),
            if (canViewAIAdvisor && aiChatState.isPanelOpen)
              const AIChatPanel(),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: _buildDrawer(tabs, selectedIndex),
      body: Stack(
        children: [
          _getScreen(tabs[selectedIndex].screen),
          if (canViewAIAdvisor && !aiChatState.isPanelOpen)
            AIChatHead(userId: authState.user!.id!),
          if (canViewAIAdvisor && aiChatState.isPanelOpen)
            const AIChatPanel(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(tabs, selectedIndex),
    );
  }

  Widget _getScreen(Widget screen) {
    return screen;
  }

  NavigationRail _buildNavigationRail(
      List<AppTab> tabs, double screenWidth, int selectedIndex) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      extended: screenWidth >= 900,
      minExtendedWidth: 200,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: screenWidth >= 900
            ? const AppLogo(size: 56, variant: LogoVariant.full)
            : const AppIcon(size: 40),
      ),
      destinations: tabs
          .map((tab) => NavigationRailDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon ?? tab.icon),
                label: Text(tab.label),
              ))
          .toList(),
    );
  }

  Widget _buildDrawer(List<AppTab> tabs, int selectedIndex) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppLogo(size: 80, variant: LogoVariant.full),
              ],
            ),
          ),
          ...tabs.asMap().entries.map((entry) {
            final index = entry.key;
            final tab = entry.value;
            return ListTile(
              leading: Icon(tab.icon),
              title: Text(tab.label),
              selected: selectedIndex == index,
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                });
                Navigator.of(context).pop();
              },
            );
          }),
        ],
      ),
    );
  }

  NavigationBar _buildBottomNavigationBar(
      List<AppTab> tabs, int selectedIndex) {
    return NavigationBar(
      selectedIndex: selectedIndex,
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

  List<AppTab> _getTabsForRole(UserRole role) {
    final authNotifier = ref.read(authStateProvider.notifier);

    // Determine whether the More screen would have any accessible entries
    // for the current user.  More is only shown if at least one More
    // screen permission is granted.
    final morePermissions = [
      'view_categories',
      'add_stock',
      'view_reports',
      'view_announcements',
    ];
    final hasMoreEntries =
        morePermissions.any((p) => authNotifier.hasPermission(p));

    final moreTab = AppTab(
      label: 'More',
      icon: Icons.more_horiz,
      screen: const MoreScreen(),
      permission: 'view_more',
    );

    switch (role) {
      case UserRole.owner:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
            permission: 'view_dashboard',
          ),
          AppTab(
            label: 'POS',
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart,
            screen: const POSScreen(),
            permission: 'view_pos',
          ),
          AppTab(
            label: 'Products',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: const ProductsScreen(),
            permission: 'view_products',
          ),
          AppTab(
            label: 'Sales',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            screen: const SalesScreen(),
            permission: 'view_sales',
          ),
          if (hasMoreEntries) moreTab,
        ];

      case UserRole.admin:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
            permission: 'view_dashboard',
          ),
          AppTab(
            label: 'Users',
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            screen: const UsersScreen(),
            permission: 'manage_users',
          ),
          AppTab(
            label: 'Backup',
            icon: Icons.backup_outlined,
            selectedIcon: Icons.backup,
            screen: const BackupRestoreScreen(),
            permission: 'backup_restore',
          ),
          AppTab(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            screen: const SettingsScreen(),
            permission: 'view_settings',
          ),
          if (hasMoreEntries) moreTab,
        ];

      case UserRole.staff:
        return [
          AppTab(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: const DashboardScreen(),
            permission: 'view_dashboard',
          ),
          AppTab(
            label: 'POS',
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart,
            screen: const POSScreen(),
            permission: 'view_pos',
          ),
          AppTab(
            label: 'Products',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: const ProductsScreen(),
            permission: 'view_products',
          ),
          AppTab(
            label: 'My Sales',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            screen: const SalesScreen(),
            permission: 'view_sales',
          ),
          if (hasMoreEntries) moreTab,
        ];
    }
  }

}

class AppTab {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final Widget screen;
  final String? permission;

  AppTab({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.screen,
    this.permission,
  });
}