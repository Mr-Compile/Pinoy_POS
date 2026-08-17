import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/category_repository.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/user_provider.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductRepository _productRepository = ProductRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();

  List<Product> _deletedProducts = [];
  List<Category> _deletedCategories = [];
  bool _isLoading = true;

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
    setState(() => _isLoading = true);
    try {
      final products = await _productRepository.getDeleted();
      final categories = await _categoryRepository.getDeleted();
      // Load deleted users via the user controller.
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
        setState(() => _isLoading = false);
      }
    }
  }

  // ── PRODUCT RESTORE ──────────────────────────────────────────────────

  Future<void> _restoreProduct(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
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
        await _productService.restoreProduct(product.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'Product restored successfully');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to restore product');
        }
      }
    }
  }

  // ── CATEGORY RESTORE ─────────────────────────────────────────────────

  Future<void> _restoreCategory(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
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
        await _categoryService.restoreCategory(category.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'Category restored successfully');
          _loadTrash();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to restore category');
        }
      }
    }
  }

  // ── USER RESTORE ─────────────────────────────────────────────────────

  Future<void> _restoreUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
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
          showSuccessSnackbar(context, result.message);
          _loadTrash();
        } else {
          showErrorSnackbar(context, result.message);
        }
      }
    }
  }

  // ── USER PERMANENT DELETE ────────────────────────────────────────────

  Future<void> _permanentlyDeleteUser(User user) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_users')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              backgroundColor: Theme.of(context).colorScheme.error,
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
          showSuccessSnackbar(context, result.message);
          _loadTrash();
        } else {
          showErrorSnackbar(context, result.message);
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
    final deletedUsers = ref.watch(userControllerProvider).deletedUsers;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trash Bin')),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash Bin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
                text: 'Products (${_deletedProducts.length})',
                icon: const Icon(Icons.inventory_2)),
            Tab(
                text: 'Categories (${_deletedCategories.length})',
                icon: const Icon(Icons.category)),
            Tab(
                text: 'Users (${deletedUsers.length})',
                icon: const Icon(Icons.people)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductsTab(canRestore),
          _buildCategoriesTab(canRestore),
          _buildUsersTab(canRestore, canDeleteUsers, deletedUsers),
        ],
      ),
    );
  }

  Widget _buildProductsTab(bool canRestore) {
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
            trailing: canRestore
                ? IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreProduct(product),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildCategoriesTab(bool canRestore) {
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
            trailing: canRestore
                ? IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => _restoreCategory(category),
                  )
                : null,
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
