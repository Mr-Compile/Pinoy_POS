import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/auth_navigation.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/navigation_provider.dart';
import 'package:pinoy_pos/ui/screens/dashboard_screen.dart';
import 'package:pinoy_pos/ui/screens/pos_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/ui/screens/sales_screen.dart';
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
  bool _hasRedirected = false;
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
          _updateCurrentDestination();
        }
      },
    );

    // Set the initial destination once the shell is first built so the
    // AI advisor knows which tab is visible before the user interacts
    // with the navigation.
    _updateCurrentDestination();
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _authSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final authState = ref.watch(authStateProvider);
        final layout = layoutClassFor(constraints.maxWidth);
        final isTablet = layout.isAtLeastMedium;

        // AppShell should only be visible when fully authenticated.
    // If the phase changes (e.g. forced password change, PIN lock,
    // or logout), navigate to the appropriate screen.
    if ((authState.user == null ||
            authState.phase != AuthSessionPhase.fullyAuthenticated) &&
        !_hasRedirected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hasRedirected || !mounted) return;

        final current = ref.read(authStateProvider);
        if (current.phase == AuthSessionPhase.fullyAuthenticated) return;

        _hasRedirected = true;
        AuthPhaseNavigator.pushAndRemoveUntil(context, current.phase);
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

    // Clamp the selected index to the valid range. When the destination
    // set shrinks (e.g. the More tab disappears because its entries became
    // inaccessible), the old index can fall out of bounds. Reset to 0 and
    // persist the correction so _selectedIndex stays consistent for the
    // next navigation event. The reset is deferred to a post-frame
    // callback to avoid calling setState during build.
    int selectedIndex;
    if (_selectedIndex >= 0 && _selectedIndex < tabs.length) {
      selectedIndex = _selectedIndex;
    } else {
      selectedIndex = 0;
      if (_selectedIndex != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedIndex = 0);
        });
      }
    }

    // Keep the AI advisor's current route in sync with the visible tab,
    // including when the user pops back to the shell from a detail screen
    // (e.g. sale detail or receipt).
    final expectedDestination = _destinationIdForPermission(tabs[selectedIndex].permission);
    if (expectedDestination != null &&
        ref.read(currentRouteProvider) != expectedDestination) {
      _updateCurrentDestination();
    }

    // AI Advisor floating chat head — available to users with
    // use_ai_advisor permission (Owner, Admin, Staff). Each role gets a
    // role-appropriate AI assistant (Business Advisor, System Assistant,
    // or Work Assistant). Tapping it opens the full AIAdvisorScreen route.
    final canUseAIAdvisor =
        ref.read(authStateProvider.notifier).hasPermission('use_ai_advisor');
    final aiChatState = ref.watch(aiAdvisorChatProvider);

    if (isTablet) {
      return Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                _buildNavigationRail(tabs, constraints.maxWidth, selectedIndex),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: _getScreen(tabs[selectedIndex].screen),
                ),
              ],
            ),
            if (canUseAIAdvisor && !aiChatState.isPanelOpen)
              AIChatHead(userId: authState.user!.id!),
            if (canUseAIAdvisor && aiChatState.isPanelOpen)
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
          if (canUseAIAdvisor && !aiChatState.isPanelOpen)
            AIChatHead(userId: authState.user!.id!),
          if (canUseAIAdvisor && aiChatState.isPanelOpen)
            const AIChatPanel(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(tabs, selectedIndex),
    );
      },
    );
  }

  Widget _getScreen(Widget screen) {
    return screen;
  }

  NavigationRail _buildNavigationRail(
      List<AppTab> tabs, double screenWidth, int selectedIndex) {
    final layout = layoutClassFor(screenWidth);
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
        _updateCurrentDestination();
      },
      extended: layout.isAtLeastExpanded,
      minExtendedWidth: 200,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: layout.isAtLeastExpanded
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
                _updateCurrentDestination();
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
        _updateCurrentDestination();
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

    // More is only shown if at least one More entry is accessible for the
    // current user. The entry list is the SINGLE SOURCE OF TRUTH shared
    // with MoreScreen, so the two can never drift apart and More is never
    // created when it would be empty.
    final moreEntries =
        MoreEntry.accessibleFor(authNotifier.hasPermission);
    final hasMoreEntries = moreEntries.isNotEmpty;

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


  void _updateCurrentDestination() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = ref.read(authStateProvider).user?.role;
      final tabs = _getTabsForRole(role ?? UserRole.staff);
      if (_selectedIndex < 0 || _selectedIndex >= tabs.length) return;

      final destinationId = _destinationIdForPermission(tabs[_selectedIndex].permission);
      if (destinationId != null) {
        ref.read(currentRouteProvider.notifier).state = destinationId;
      }
    });
  }

  String? _destinationIdForPermission(String? permission) {
    return switch (permission) {
      'view_dashboard' => 'dashboard',
      'view_pos' => 'pos',
      'view_products' => 'products',
      'view_sales' => 'sales',
      'manage_users' => 'users',
      'backup_restore' => 'backup_restore',
      'view_settings' => 'settings',
      'view_more' => 'more',
      _ => null,
    };
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
