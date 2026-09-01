import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
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

class _TrashScreenState extends ConsumerState<TrashScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Product> _deletedProducts = [];
  List<Category> _deletedCategories = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTrash();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Product'),
        content: Text('Restore "${product.name}" from trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber),
        iconColor: AppSemanticColors.warning,
        title: const Text('Permanently Delete Product?'),
        content: Text(
          'Are you sure you want to permanently delete '
          '"${product.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.error,
              foregroundColor: AppSemanticColors.onError,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Category'),
        content: Text('Restore "${category.name}" from trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber),
        iconColor: AppSemanticColors.warning,
        title: const Text('Permanently Delete Category?'),
        content: Text(
          'Are you sure you want to permanently delete '
          '"${category.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.error,
              foregroundColor: AppSemanticColors.onError,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore User?'),
        content: Text(
          '${user.fullName} (@${user.username}) will become active '
          'in User Management again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber),
        iconColor: AppSemanticColors.warning,
        title: const Text('Permanently Delete User?'),
        content: Text(
          'Are you sure you want to permanently delete '
          '${user.fullName} (@${user.username})?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.error,
              foregroundColor: AppSemanticColors.onError,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
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
    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore = authNotifier.hasPermission('restore_trash');
    final canDeleteUsers = authNotifier.hasPermission('delete_users');
    final canDeleteProducts = authNotifier.hasPermission('delete_products');
    final canDeleteCategories = authNotifier.hasPermission('delete_categories');
    final deletedUsers = ref.watch(userControllerProvider).deletedUsers;

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

    return Scaffold(
      appBar: AppHeader(
        title: 'Trash Bin',
        showBackButton: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Products'),
            Tab(icon: Icon(Icons.category_outlined), text: 'Categories'),
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductsTab(canRestore, canDeleteProducts),
          _buildCategoriesTab(canRestore, canDeleteCategories),
          _buildUsersTab(canRestore, canDeleteUsers, deletedUsers),
        ],
      ),
    );
  }

  Widget _buildProductsTab(bool canRestore, bool canDelete) {
    if (_deletedProducts.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2,
        title: 'No Deleted Products',
        message: 'Deleted products will appear here for recovery',
      );
    }

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
              '₱${product.price.toStringAsFixed(2)} • Stock: ${product.stock}',
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

  Widget _buildCategoriesTab(bool canRestore, bool canDelete) {
    if (_deletedCategories.isEmpty) {
      return const EmptyState(
        icon: Icons.category,
        title: 'No Deleted Categories',
        message: 'Deleted categories will appear here for recovery',
      );
    }

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

  Widget _buildUsersTab(
      bool canRestore, bool canDeleteUsers, List<User> deletedUsers) {
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
