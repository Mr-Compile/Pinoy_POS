import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashTab {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  const _TrashTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

class _TrashScreenState extends ConsumerState<TrashScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<_TrashTab> _visibleTabs = [];

  List<Product> _deletedProducts = [];
  List<Category> _deletedCategories = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initTabs();
    _loadTrash();
  }

  void _initTabs() {
    final authNotifier = ref.read(authStateProvider.notifier);
    _visibleTabs = [
      if (authNotifier.hasPermission('view_products'))
        _TrashTab(
          label: 'Products',
          icon: Icons.inventory_2_outlined,
          builder: (_) => _buildProductsTab(),
        ),
      if (authNotifier.hasPermission('view_categories'))
        _TrashTab(
          label: 'Categories',
          icon: Icons.category_outlined,
          builder: (_) => _buildCategoriesTab(),
        ),
      if (authNotifier.hasPermission('manage_users'))
        _TrashTab(
          label: 'Users',
          icon: Icons.people_outline,
          builder: (_) => _buildUsersTab(),
        ),
    ];
    _tabController?.dispose();
    _tabController = _visibleTabs.isEmpty
        ? null
        : TabController(length: _visibleTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadTrash() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      // Load deleted products and categories through their Riverpod
      // service providers (UI -> Provider -> Service -> Repository -> DAO
      // -> SQLite).  Deleted users are loaded via the user controller.
      final productService = ref.read(productServiceProvider);
      final categoryService = ref.read(categoryServiceProvider);
      final products = await productService.getDeletedProducts();
      final categories = await categoryService.getDeletedCategories();
      await ref.read(userControllerProvider.notifier).loadUsers();
      if (mounted) {
        setState(() {
          _deletedProducts = products;
          _deletedCategories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Failed to load trash. Please try again.';
        });
      }
    }
  }

  // ── PRODUCT RESTORE ──────────────────────────────────────────────────

  Future<void> _restoreProduct(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.restoreConfirm(
      context,
      itemName: product.name,
    );

    if (confirmed == true && mounted) {
      try {
        final productService = ref.read(productServiceProvider);
        await productService.restoreProduct(product.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Restored', message: 'Product restored successfully.');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Restore Failed', message: 'Failed to restore product.');
        }
      }
    }
  }

  // ── PRODUCT PERMANENT DELETE ─────────────────────────────────────────

  Future<void> _permanentlyDeleteProduct(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_products')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: product.name,
    );

    if (confirmed == true && mounted) {
      try {
        final productService = ref.read(productServiceProvider);
        await productService.permanentlyDeleteProduct(product.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Deleted', message: 'Product permanently deleted.');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to permanently delete product.');
        }
      }
    }
  }

  // ── CATEGORY RESTORE ─────────────────────────────────────────────────

  Future<void> _restoreCategory(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.restoreConfirm(
      context,
      itemName: category.name,
    );

    if (confirmed == true && mounted) {
      try {
        final categoryService = ref.read(categoryServiceProvider);
        await categoryService.restoreCategory(category.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Restored', message: 'Category restored successfully.');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Restore Failed', message: 'Failed to restore category.');
        }
      }
    }
  }

  // ── CATEGORY PERMANENT DELETE ────────────────────────────────────────

  Future<void> _permanentlyDeleteCategory(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_categories')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: category.name,
    );

    if (confirmed == true && mounted) {
      try {
        final categoryService = ref.read(categoryServiceProvider);
        await categoryService.permanentlyDeleteCategory(category.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Deleted', message: 'Category permanently deleted.');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to permanently delete category.');
        }
      }
    }
  }

  // ── USER RESTORE ─────────────────────────────────────────────────────

  Future<void> _restoreUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.restoreConfirm(
      context,
      itemName: '${user.fullName} (@${user.username})',
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(userControllerProvider.notifier)
          .restoreUser(user.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(context, title: 'Done', message: result.message);
          _loadTrash();
        } else {
          AppDialogService.error(context, title: 'Error', message: result.message);
        }
      }
    }
  }

  // ── USER PERMANENT DELETE ────────────────────────────────────────────

  Future<void> _permanentlyDeleteUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_users')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: '${user.fullName} (@${user.username})',
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(userControllerProvider.notifier)
          .permanentlyDeleteUser(user.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(context, title: 'Done', message: result.message);
          _loadTrash();
        } else {
          AppDialogService.error(context, title: 'Error', message: result.message);
        }
      }
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash Bin', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash Bin', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load Trash',
          message: _loadError,
          onRetry: _loadTrash,
        ),
      );
    }

    if (_visibleTabs.isEmpty) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash Bin', showBackButton: true),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'No Trash Items',
          message: 'You do not have access to any trash categories.',
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(
        title: 'Trash Bin',
        showBackButton: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: _visibleTabs
              .map((tab) => Tab(icon: Icon(tab.icon), text: tab.label))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _visibleTabs.map((tab) => tab.builder(context)).toList(),
      ),
    );
  }

  Widget _buildProductsTab() {
    if (_deletedProducts.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2,
        title: 'No Deleted Products',
        message: 'Deleted products will appear here for recovery',
      );
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore =
        authNotifier.hasPermission('restore_trash') &&
        authNotifier.hasPermission('edit_products');
    final canDelete = authNotifier.hasPermission('delete_products');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deletedProducts.length,
      itemBuilder: (context, index) {
        final product = _deletedProducts[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(product.name),
            subtitle: Text(
              '${CurrencyUtils.format(product.price)} • Stock: ${product.stock}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRestore)
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreProduct(product),
                  ),
                if (canDelete)
                  IconButton(
                    icon: Icon(Icons.delete_forever,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Delete Permanently',
                    onPressed: () => _permanentlyDeleteProduct(product),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoriesTab() {
    if (_deletedCategories.isEmpty) {
      return const EmptyState(
        icon: Icons.category,
        title: 'No Deleted Categories',
        message: 'Deleted categories will appear here for recovery',
      );
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore =
        authNotifier.hasPermission('restore_trash') &&
        authNotifier.hasPermission('edit_categories');
    final canDelete = authNotifier.hasPermission('delete_categories');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deletedCategories.length,
      itemBuilder: (context, index) {
        final category = _deletedCategories[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(category.name),
            subtitle: Text(
                category.description.isNotEmpty ? category.description : 'No description'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRestore)
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreCategory(category),
                  ),
                if (canDelete)
                  IconButton(
                    icon: Icon(Icons.delete_forever,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Delete Permanently',
                    onPressed: () => _permanentlyDeleteCategory(category),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    final deletedUsers = ref.watch(userControllerProvider).deletedUsers;
    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore =
        authNotifier.hasPermission('restore_trash') &&
        authNotifier.hasPermission('edit_users');
    final canDeleteUsers = authNotifier.hasPermission('delete_users');

    if (deletedUsers.isEmpty) {
      return const EmptyState(
        icon: Icons.people,
        title: 'No Deleted Users',
        message: 'Deleted users will appear here for recovery',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deletedUsers.length,
      itemBuilder: (context, index) {
        final user = deletedUsers[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                user.fullName.isNotEmpty
                    ? user.fullName[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(user.fullName),
            subtitle: Text(
              '${user.username} • ${user.role.displayName}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRestore)
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreUser(user),
                  ),
                if (canDeleteUsers)
                  IconButton(
                    icon: Icon(Icons.delete_forever,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Delete Permanently',
                    onPressed: () => _permanentlyDeleteUser(user),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
