import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashTab {
  final String label;
  final String entityType;
  final IconData icon;
  final WidgetBuilder builder;

  const _TrashTab({
    required this.label,
    required this.entityType,
    required this.icon,
    required this.builder,
  });
}

class _TrashScreenState extends ConsumerState<TrashScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<_TrashTab> _visibleTabs = [];

  List<TrashItem> _trashItems = [];
  List<TrashItem> _filteredItems = [];
  bool _isLoading = true;
  String? _loadError;
  final _searchController = TextEditingController();

  final Set<int> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _initTabs();
    _loadTrash();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initTabs() {
    final authNotifier = ref.read(authStateProvider.notifier);
    _visibleTabs = [
      if (authNotifier.hasPermission('view_products'))
        _TrashTab(
          label: 'Products',
          entityType: 'product',
          icon: Icons.inventory_2_outlined,
          builder: (_) => _buildProductsTab(),
        ),
      if (authNotifier.hasPermission('view_categories'))
        _TrashTab(
          label: 'Categories',
          entityType: 'category',
          icon: Icons.category_outlined,
          builder: (_) => _buildCategoriesTab(),
        ),
      if (authNotifier.hasPermission('view_users'))
        _TrashTab(
          label: 'Users',
          entityType: 'user',
          icon: Icons.people_outline,
          builder: (_) => _buildUsersTab(),
        ),
    ];
    _tabController?.dispose();
    _tabController = _visibleTabs.isEmpty
        ? null
        : TabController(length: _visibleTabs.length, vsync: this);
  }

  Future<void> _loadTrash() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _selectionMode = false;
      _selectedIds.clear();
    });
    try {
      final trashService = ref.read(trashServiceProvider);
      await trashService.backfillSoftDeletedToTrash();
      await trashService.processExpiredTrash();
      final items = await trashService.getAllTrash();
      if (mounted) {
        setState(() {
          _trashItems = items;
          _isLoading = false;
        });
        _filterItems();
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

  void _filterItems() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredItems = List.unmodifiable(_trashItems));
      return;
    }

    setState(() {
      _filteredItems = _trashItems.where((item) {
        final name = (item.entityName ?? '').toLowerCase();
        final type = item.entityType.toLowerCase();
        final snapshot = item.snapshotMap;
        final snapshotText = snapshot != null
            ? snapshot.values
                .whereType<String>()
                .map((v) => v.toLowerCase())
                .join(' ')
            : '';
        return name.contains(query) ||
            type.contains(query) ||
            snapshotText.contains(query);
      }).toList();
    });
  }

  List<TrashItem> _itemsForType(String entityType) {
    return _filteredItems.where((i) => i.entityType == entityType).toList();
  }

  String? _currentTabEntityType() {
    if (_tabController == null || _visibleTabs.isEmpty) return null;
    final index = _tabController!.index;
    if (index < 0 || index >= _visibleTabs.length) return null;
    return _visibleTabs[index].entityType;
  }

  List<TrashItem> _selectedItems() {
    return _filteredItems.where((i) => _selectedIds.contains(i.id)).toList();
  }

  List<Widget> _buildNormalActions(AuthStateNotifier authNotifier) {
    final actions = <Widget>[];
    if (_visibleTabs.isNotEmpty) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.check_circle_outlined),
          tooltip: 'Select items',
          onPressed: () => setState(() => _selectionMode = true),
        ),
      );
    }
    if (authNotifier.hasPermission('empty_trash')) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Empty Trash',
          onPressed: _emptyTrash,
        ),
      );
    }
    return actions;
  }

  List<Widget> _buildSelectionActions(AuthStateNotifier authNotifier) {
    final selected = _selectedItems();
    final canRestoreAll = selected.isNotEmpty &&
        authNotifier.hasPermission('restore_trash') &&
        selected.every((i) =>
            authNotifier.hasPermission(_viewPermissionFor(i.entityType)));
    final canDeleteAll = selected.isNotEmpty &&
        selected.every((i) =>
            authNotifier.hasPermission(_deletePermissionFor(i.entityType)));

    return [
      IconButton(
        icon: const Icon(Icons.select_all),
        tooltip: 'Select all',
        onPressed: _selectAllOnCurrentTab,
      ),
      IconButton(
        icon: const Icon(Icons.clear),
        tooltip: 'Clear selection',
        onPressed: _clearSelection,
      ),
      if (canRestoreAll)
        IconButton(
          icon: const Icon(Icons.restore),
          tooltip: 'Restore selected',
          onPressed: _restoreSelected,
        ),
      if (canDeleteAll)
        IconButton(
          icon: Icon(Icons.delete_forever,
              color: Theme.of(context).colorScheme.error),
          tooltip: 'Delete selected',
          onPressed: _deleteSelected,
        ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: _exitSelectionMode,
      ),
    ];
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _selectAllOnCurrentTab() {
    final currentType = _currentTabEntityType();
    if (currentType == null) return;
    final items = _itemsForType(currentType);
    setState(() {
      for (final item in items) {
        if (item.id != null) _selectedIds.add(item.id!);
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _startSelection(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  Future<void> _restoreSelected() async {
    final items = _selectedItems();
    if (items.isEmpty) return;

    final confirmed = await AppDialogService.restoreConfirm(
      context,
      itemName: '${items.length} selected item${items.length == 1 ? '' : 's'}',
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(trashServiceProvider)
          .bulkRestore(_selectedIds.toList());
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Restored',
            message: 'Selected items restored successfully.',
          );
          await _loadTrash();
        } else {
          AppDialogService.error(
            context,
            title: 'Restore Failed',
            message: result.message.isNotEmpty
                ? result.message
                : 'Failed to restore selected items.',
          );
        }
      }
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selectedItems();
    if (items.isEmpty) return;

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName:
          '${items.length} selected item${items.length == 1 ? '' : 's'}',
    );

    if (confirmed == true && mounted) {
      final result = await ref
          .read(trashServiceProvider)
          .bulkPermanentDelete(_selectedIds.toList());
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Deleted',
            message: 'Selected items permanently deleted.',
          );
          await _loadTrash();
        } else {
          AppDialogService.error(
            context,
            title: 'Delete Failed',
            message: result.message.isNotEmpty
                ? result.message
                : 'Failed to delete selected items.',
          );
        }
      }
    }
  }

  String _expiryText(TrashItem item) {
    final expiry = item.expiresAt;
    if (expiry == null) return 'No expiry';
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    final days = remaining.inDays;
    if (days == 0) {
      if (remaining.inHours > 1) {
        return 'Expires in ${remaining.inHours} hours';
      }
      return 'Expires in less than an hour';
    }
    return 'Expires in $days day${days == 1 ? '' : 's'}';
  }

  Future<void> _restoreItem(TrashItem item) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash') ||
        !authNotifier.hasPermission(_viewPermissionFor(item.entityType))) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.restoreConfirm(
      context,
      itemName: item.entityName ?? item.entityType,
    );

    if (confirmed == true && mounted) {
      final trashService = ref.read(trashServiceProvider);
      final result = await trashService.restoreFromTrash(item.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Restored',
            message: item.entityName != null
                ? '${item.entityName} restored successfully.'
                : 'Item restored successfully.',
          );
          _loadTrash();
        } else {
          AppDialogService.error(
            context,
            title: 'Restore Failed',
            message: result.message.isNotEmpty
                ? result.message
                : 'Failed to restore item.',
          );
        }
      }
    }
  }

  Future<void> _permanentlyDeleteItem(TrashItem item) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission(_deletePermissionFor(item.entityType))) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: item.entityName ?? item.entityType,
    );

    if (confirmed == true && mounted) {
      final trashService = ref.read(trashServiceProvider);
      final result = await trashService.permanentDelete(item.id!);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Deleted',
            message: item.entityName != null
                ? '${item.entityName} permanently deleted.'
                : 'Item permanently deleted.',
          );
          _loadTrash();
        } else {
          AppDialogService.error(
            context,
            title: 'Delete Failed',
            message: result.message.isNotEmpty
                ? result.message
                : 'Failed to permanently delete item.',
          );
        }
      }
    }
  }

  Future<void> _emptyTrash() async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('empty_trash')) {
      AppDialogService.accessDenied(context);
      return;
    }

    if (_trashItems.isEmpty) {
      AppDialogService.warning(
        context,
        title: 'Trash is Empty',
        message: 'There is nothing to delete.',
      );
      return;
    }

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: 'all items in trash',
    );

    if (confirmed == true && mounted) {
      final trashService = ref.read(trashServiceProvider);
      final result = await trashService.emptyTrash();
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Emptied',
            message: 'Trash has been emptied.',
          );
          _loadTrash();
        } else {
          AppDialogService.error(
            context,
            title: 'Error',
            message: result.message.isNotEmpty
                ? result.message
                : 'Failed to empty trash.',
          );
        }
      }
    }
  }

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

    final authNotifier = ref.read(authStateProvider.notifier);

    final appBarTitle =
        _selectionMode ? '${_selectedIds.length} selected' : 'Trash Bin';
    final appBarActions = _selectionMode
        ? _buildSelectionActions(authNotifier)
        : _buildNormalActions(authNotifier);

    return Scaffold(
      appBar: AppHeader(
        title: appBarTitle,
        showBackButton: true,
        showThemeToggle: !_selectionMode,
        showNotificationBell: !_selectionMode,
        showProfileMenu: !_selectionMode,
        bottom: TabBar(
          controller: _tabController,
          tabs: _visibleTabs
              .map((tab) => Tab(icon: Icon(tab.icon), text: tab.label))
              .toList(),
        ),
        actions: appBarActions,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search trash...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterItems();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => _filterItems(),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _visibleTabs.map((t) => t.builder(context)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    final items = _itemsForType('product');

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2,
        title: 'No Deleted Products',
        message: 'Deleted products will appear here for recovery',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final product = _parseProduct(item);
        final title = product?.name ?? item.entityName ?? 'Unknown product';
        final subtitle = product != null
            ? '${CurrencyUtils.format(product.price)} • Stock: ${product.stock} • ${_expiryText(item)}'
            : 'Deleted ${item.deletedAt} • ${_expiryText(item)}';
        return _buildEntityCard(
          item: item,
          title: title,
          subtitle: subtitle,
          leading: _selectionMode
              ? Checkbox(
                  value: _selectedIds.contains(item.id),
                  onChanged: (_) => _toggleSelection(item.id!),
                )
              : SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AppImage(
                      imagePath: product?.imageUrl,
                      placeholderIcon: Icons.inventory_2,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildEntityCard({
    required TrashItem item,
    required String title,
    required String subtitle,
    required Widget leading,
  }) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore = authNotifier.hasPermission('restore_trash') &&
        authNotifier.hasPermission(_viewPermissionFor(item.entityType));
    final canDelete =
        authNotifier.hasPermission(_deletePermissionFor(item.entityType));

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: !_selectionMode && (canRestore || canDelete)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canRestore)
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: 'Restore',
                      onPressed: () => _restoreItem(item),
                    ),
                  if (canDelete)
                    IconButton(
                      icon: Icon(Icons.delete_forever,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete Permanently',
                      onPressed: () => _permanentlyDeleteItem(item),
                    ),
                ],
              )
            : null,
        onTap: _selectionMode ? () => _toggleSelection(item.id!) : null,
        onLongPress: item.id != null ? () => _startSelection(item.id!) : null,
      ),
    );
  }

  Widget _buildCategoriesTab() {
    final items = _itemsForType('category');

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.category,
        title: 'No Deleted Categories',
        message: 'Deleted categories will appear here for recovery',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final category = _parseCategory(item);
        final title = category?.name ?? item.entityName ?? 'Unknown category';
        final description =
            (category != null && category.description.isNotEmpty)
                ? category.description
                : 'No description';
        final subtitle = '$description • ${_expiryText(item)}';
        return _buildEntityCard(
          item: item,
          title: title,
          subtitle: subtitle,
          leading: _selectionMode
              ? Checkbox(
                  value: _selectedIds.contains(item.id),
                  onChanged: (_) => _toggleSelection(item.id!),
                )
              : const CircleAvatar(
                  child: Icon(Icons.category),
                ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    final items = _itemsForType('user');

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.people,
        title: 'No Deleted Users',
        message: 'Deleted users will appear here for recovery',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final user = _parseUser(item);
        final title = user?.fullName ?? item.entityName ?? 'Unknown user';
        final subtitle = user != null
            ? '${user.username} • ${user.role.displayName} • ${_expiryText(item)}'
            : 'Deleted by: ${item.deletedByName ?? 'Unknown'} • ${_expiryText(item)}';
        return _buildEntityCard(
          item: item,
          title: title,
          subtitle: subtitle,
          leading: _selectionMode
              ? Checkbox(
                  value: _selectedIds.contains(item.id),
                  onChanged: (_) => _toggleSelection(item.id!),
                )
              : CircleAvatar(
                  child: Text(
                    user != null && user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : '?',
                  ),
                ),
        );
      },
    );
  }

  Product? _parseProduct(TrashItem item) {
    final snapshot = item.snapshotMap;
    if (snapshot == null) return null;
    try {
      return Product.fromMap(snapshot);
    } catch (e) {
      return null;
    }
  }

  Category? _parseCategory(TrashItem item) {
    final snapshot = item.snapshotMap;
    if (snapshot == null) return null;
    try {
      return Category.fromMap(snapshot);
    } catch (e) {
      return null;
    }
  }

  User? _parseUser(TrashItem item) {
    final snapshot = item.snapshotMap;
    if (snapshot == null) return null;
    try {
      return User.fromMap(snapshot);
    } catch (e) {
      return null;
    }
  }

  String _viewPermissionFor(String entityType) {
    return switch (entityType) {
      'product' => 'view_products',
      'category' => 'view_categories',
      'user' => 'view_users',
      _ => 'view_trash',
    };
  }

  String _deletePermissionFor(String entityType) {
    return switch (entityType) {
      'product' => 'delete_products',
      'category' => 'delete_categories',
      'user' => 'delete_users',
      _ => 'view_trash',
    };
  }
}
