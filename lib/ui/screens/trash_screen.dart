import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:intl/intl.dart';

import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/announcement.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/trash_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_circle.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/error_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashItem> _trashItems = [];
  List<TrashItem> _filteredItems = [];
  bool _isLoading = true;
  String? _loadError;
  final _searchController = TextEditingController();
  final Set<int> _selectedIds = {};
  bool _selectionMode = false;
  List<String> _allowedTypes = [];
  String _selectedType = 'all';
  final _dateFormat = DateFormat('MMM d, y h:mm a');

  @override
  void initState() {
    super.initState();
    _computeAllowedTypes();
    _loadTrash();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _computeAllowedTypes() {
    final authNotifier = ref.read(authStateProvider.notifier);
    _allowedTypes = [
      if (authNotifier.hasPermission('view_products')) 'product',
      if (authNotifier.hasPermission('view_categories')) 'category',
      if (authNotifier.hasPermission('view_users')) 'user',
      if (authNotifier.hasPermission('view_settings')) 'merchant_qr',
      if (authNotifier.hasPermission('view_announcements')) 'announcement',
    ];
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
    setState(() {
      _filteredItems = _trashItems.where((item) {
        if (!_allowedTypes.contains(item.entityType)) {
          return false;
        }
        if (_selectedType != 'all' && item.entityType != _selectedType) {
          return false;
        }
        if (query.isEmpty) return true;

        return _matchesSearch(item, query);
      }).toList();
    });
  }

  void _selectType(String type) {
    setState(() {
      _selectedType = type;
      _selectionMode = false;
      _selectedIds.clear();
    });
    _filterItems();
  }

  bool _matchesSearch(TrashItem item, String query) {
    final name = (item.entityName ?? '').toLowerCase();
    final typeLabel = _labelForType(item.entityType).toLowerCase();
    final rawType = item.entityType.toLowerCase();
    final deletedBy = (item.deletedByName ?? '').toLowerCase();
    final snapshot = item.snapshotMap;
    final snapshotText = snapshot != null
        ? snapshot.values
            .map((v) => v?.toString().toLowerCase() ?? '')
            .join(' ')
        : '';
    final haystack = '$name $typeLabel $rawType $deletedBy $snapshotText';
    return haystack.contains(query);
  }

  List<TrashItem> _selectedItems() {
    return _filteredItems.where((i) => _selectedIds.contains(i.id)).toList();
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

  void _selectAll() {
    setState(() {
      for (final item in _filteredItems) {
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
          bumpCatalogRevision(ref);
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
          bumpCatalogRevision(ref);
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

  Future<void> _restoreItem(TrashItem item) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('restore_trash') ||
        !authNotifier.hasPermission(_viewPermissionFor(item.entityType)) ||
        (item.entityType == 'merchant_qr' &&
            !SessionManager().canEditBusinessSettings())) {
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
          bumpCatalogRevision(ref);
          await _loadTrash();
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
    if (!authNotifier.hasPermission(_deletePermissionFor(item.entityType)) ||
        (item.entityType == 'merchant_qr' &&
            !SessionManager().canEditBusinessSettings())) {
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
          bumpCatalogRevision(ref);
          await _loadTrash();
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

    if (_filteredItems.isEmpty) {
      AppDialogService.warning(
        context,
        title: 'Trash is Empty',
        message: 'There is nothing to delete.',
      );
      return;
    }

    final itemName = _searchController.text.isEmpty
        ? 'all items in trash'
        : 'all visible items in trash';

    final confirmed = await AppDialogService.permanentDeleteConfirm(
      context,
      itemName: itemName,
    );

    if (confirmed == true && mounted) {
      final ids = _filteredItems
          .where((i) => _canDeleteItem(i, authNotifier))
          .map((i) => i.id!)
          .toList();
      if (ids.isEmpty) {
        AppDialogService.accessDenied(context);
        return;
      }

      final result =
          await ref.read(trashServiceProvider).bulkPermanentDelete(ids);
      if (mounted) {
        if (result.success) {
          await AppDialogService.success(
            context,
            title: 'Emptied',
            message: 'Trash has been emptied.',
          );
          bumpCatalogRevision(ref);
          await _loadTrash();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash', showBackButton: true),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash', showBackButton: true),
        body: ErrorState(
          title: 'Failed to Load Trash',
          message: _loadError,
          onRetry: _loadTrash,
        ),
      );
    }

    if (_allowedTypes.isEmpty) {
      return Scaffold(
        appBar: AppHeader(title: 'Trash', showBackButton: true),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'No Trash Items',
          message: 'You do not have access to any trash categories.',
        ),
      );
    }

    final authNotifier = ref.read(authStateProvider.notifier);

    final appBarTitle =
        _selectionMode ? '${_selectedIds.length} selected' : 'Trash';
    final appBarActions = _selectionMode
        ? [_buildSelectionActions(authNotifier)]
        : _buildNormalActions(authNotifier);

    return Scaffold(
      appBar: AppHeader(
        title: appBarTitle,
        showBackButton: true,
        showThemeToggle: !_selectionMode,
        showNotificationBell: !_selectionMode,
        showProfileMenu: !_selectionMode,
        actions: appBarActions,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppSearchField(
              controller: _searchController,
              hint: 'Search trash...',
              onChanged: (_) => _filterItems(),
              onClear: () {
                _searchController.clear();
                _filterItems();
              },
            ),
          ),
          _buildTypeFilter(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    final cs = Theme.of(context).colorScheme;

    final chips = ['all', ..._allowedTypes];
    final labels = {
      'all': 'All',
      'product': 'Products',
      'category': 'Categories',
      'user': 'Users',
      'merchant_qr': 'QR',
      'announcement': 'Announcements',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final type in chips) ...[
              ChoiceChip(
                label: Text(labels[type] ?? type),
                selected: _selectedType == type,
                onSelected: (_) => _selectType(type),
                selectedColor: cs.primary,
                backgroundColor: cs.surface,
                side: BorderSide(color: cs.outline),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                labelStyle: TextStyle(
                  color: _selectedType == type ? cs.onPrimary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_filteredItems.isEmpty) {
      final hasSearch = _searchController.text.trim().isNotEmpty;
      return EmptyState(
        icon: Icons.delete_outline,
        title: hasSearch ? 'No matching records found.' : 'Trash is empty.',
        message: hasSearch
            ? 'Try a different search term.'
            : 'Deleted products, categories, users, QR images, and '
                'announcements will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) => _buildTrashCard(_filteredItems[index]),
    );
  }

  Widget _buildTrashCard(TrashItem item) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canRestore = _canRestoreItem(item, authNotifier);
    final canDelete = _canDeleteItem(item, authNotifier);
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: _selectionMode ? () => _toggleSelection(item.id!) : null,
        onLongPress: item.id != null ? () => _startSelection(item.id!) : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeading(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleForItem(item),
                    style: AppTypography.titleSmall(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _descriptionForItem(item),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Deleted by ${item.deletedByName ?? 'Unknown'} '
                    '• ${_dateFormat.format(item.deletedAt)} '
                    '• ${_expiryText(item)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!_selectionMode && (canRestore || canDelete)) ...[
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canRestore)
                    _buildActionIcon(
                      Icons.restore,
                      AppSemanticColors.resolve(
                        AppSemanticColors.success,
                        brightness,
                      ),
                      'Restore',
                      () => _restoreItem(item),
                    ),
                  if (canRestore && canDelete) const SizedBox(width: 6),
                  if (canDelete)
                    _buildActionIcon(
                      Icons.delete_forever,
                      AppSemanticColors.resolve(
                        AppSemanticColors.error,
                        brightness,
                      ),
                      'Delete Permanently',
                      () => _permanentlyDeleteItem(item),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onPressed,
  ) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  Color _typeColor(String type, Brightness brightness) {
    return switch (type) {
      'category' || 'announcement' =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
      'user' =>
        AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      'merchant_qr' =>
        AppSemanticColors.resolve(AppSemanticColors.error, brightness),
      _ => AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
    };
  }

  Widget _buildLeading(TrashItem item) {
    if (_selectionMode) {
      return Checkbox(
        value: _selectedIds.contains(item.id),
        onChanged: (_) => _toggleSelection(item.id!),
      );
    }

    final brightness = Theme.of(context).brightness;
    final cs = Theme.of(context).colorScheme;

    switch (item.entityType) {
      case 'product':
        final product = _parseProduct(item);
        return Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppImage(
            imagePath: product?.imageUrl,
            placeholderIcon: Icons.inventory_2,
            fit: BoxFit.cover,
            cacheWidth: 512,
          ),
        );
      case 'category':
        final color = _typeColor(item.entityType, brightness);
        return Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.category, color: color, size: 19),
        );
      case 'user':
        final user = _parseUser(item);
        final initial = user != null && user.fullName.isNotEmpty
            ? user.fullName[0].toUpperCase()
            : '?';
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              color: cs.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        );
      case 'merchant_qr':
        final snapshot = item.snapshotMap;
        final path = snapshot?['path'] as String?;
        return Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppImage(
            imagePath: path,
            placeholderIcon: Icons.qr_code,
            fit: BoxFit.contain,
            cacheWidth: null,
          ),
        );
      case 'announcement':
        final color = _typeColor(item.entityType, brightness);
        return AppIconCircle.medium(
          icon: Icons.campaign,
          backgroundColor: color.withValues(alpha: 0.16),
          iconColor: color,
        );
      default:
        return AppIconCircle.medium(
          icon: Icons.delete,
          backgroundColor: cs.surfaceContainerHigh,
          iconColor: cs.onSurfaceVariant,
        );
    }
  }

  String _titleForItem(TrashItem item) {
    return switch (item.entityType) {
      'product' => _parseProduct(item)?.name ?? item.entityName ?? 'Unknown product',
      'category' => _parseCategory(item)?.name ?? item.entityName ?? 'Unknown category',
      'user' => _parseUser(item)?.fullName ?? item.entityName ?? 'Unknown user',
      'merchant_qr' => item.entityName ?? 'Merchant QR',
      'announcement' => _parseAnnouncement(item)?.title ?? item.entityName ?? 'Unknown announcement',
      _ => item.entityName ?? 'Unknown item',
    };
  }

  String _descriptionForItem(TrashItem item) {
    switch (item.entityType) {
      case 'product':
        final product = _parseProduct(item);
        if (product == null) return '';
        return '${CurrencyUtils.format(product.price)} • Stock: ${product.stock}';
      case 'category':
        final category = _parseCategory(item);
        return category?.description ?? 'No description';
      case 'user':
        final user = _parseUser(item);
        if (user == null) return '';
        return '${user.username} • ${user.role.displayName}';
      case 'merchant_qr':
        final snapshot = item.snapshotMap;
        final type = snapshot?['type'] as String?;
        return type ?? 'Merchant QR image';
      case 'announcement':
        final announcement = _parseAnnouncement(item);
        if (announcement == null) return '';
        return announcement.content;
      default:
        return '';
    }
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

  Announcement? _parseAnnouncement(TrashItem item) {
    final snapshot = item.snapshotMap;
    if (snapshot == null) return null;
    try {
      return Announcement.fromMap(snapshot);
    } catch (e) {
      return null;
    }
  }

  List<Widget> _buildNormalActions(AuthStateNotifier authNotifier) {
    return [
      if (_allowedTypes.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.check_circle_outlined),
          tooltip: 'Select items',
          onPressed: () => setState(() => _selectionMode = true),
        ),
      if (authNotifier.hasPermission('empty_trash'))
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Empty Trash',
          onPressed: _emptyTrash,
        ),
    ];
  }

  Widget _buildSelectionActions(AuthStateNotifier authNotifier) {
    final selected = _selectedItems();
    final canRestoreAll = selected.isNotEmpty &&
        selected.every((i) => _canRestoreItem(i, authNotifier));
    final canDeleteAll = selected.isNotEmpty &&
        selected.every((i) => _canDeleteItem(i, authNotifier));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 220) {
          return _buildSelectionPopupMenu(
            context,
            authNotifier,
            canRestoreAll: canRestoreAll,
            canDeleteAll: canDeleteAll,
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear selection',
              onPressed: _clearSelection,
            ),
            if (canRestoreAll)
              IconButton(
                icon: Icon(
                  Icons.restore,
                  color: AppSemanticColors.resolve(
                    AppSemanticColors.success,
                    Theme.of(context).brightness,
                  ),
                ),
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
          ],
        );
      },
    );
  }

  Widget _buildSelectionPopupMenu(
    BuildContext context,
    AuthStateNotifier authNotifier, {
    required bool canRestoreAll,
    required bool canDeleteAll,
  }) {
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Selection actions',
      onSelected: (callback) => callback(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _selectAll,
          child: Row(
            children: [
              Icon(Icons.select_all, color: cs.onSurface),
              const SizedBox(width: 12),
              const Text('Select all'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _clearSelection,
          child: Row(
            children: [
              Icon(Icons.clear, color: cs.onSurface),
              const SizedBox(width: 12),
              const Text('Clear selection'),
            ],
          ),
        ),
        if (canRestoreAll)
          PopupMenuItem(
            value: _restoreSelected,
            child: Row(
              children: [
                Icon(
                  Icons.restore,
                  color: AppSemanticColors.resolve(
                    AppSemanticColors.success,
                    Theme.of(context).brightness,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Restore selected'),
              ],
            ),
          ),
        if (canDeleteAll)
          PopupMenuItem(
            value: _deleteSelected,
            child: Row(
              children: [
                Icon(Icons.delete_forever, color: cs.error),
                const SizedBox(width: 12),
                Text('Delete selected', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
        PopupMenuItem(
          value: _exitSelectionMode,
          child: Row(
            children: [
              Icon(Icons.close, color: cs.onSurface),
              const SizedBox(width: 12),
              const Text('Cancel'),
            ],
          ),
        ),
      ],
    );
  }

  bool _canRestoreItem(TrashItem item, AuthStateNotifier authNotifier) {
    return authNotifier.hasPermission('restore_trash') &&
        authNotifier.hasPermission(_viewPermissionFor(item.entityType)) &&
        (item.entityType != 'merchant_qr' ||
            SessionManager().canEditBusinessSettings());
  }

  bool _canDeleteItem(TrashItem item, AuthStateNotifier authNotifier) {
    return authNotifier.hasPermission(_deletePermissionFor(item.entityType)) &&
        (item.entityType != 'merchant_qr' ||
            SessionManager().canEditBusinessSettings());
  }

  String _viewPermissionFor(String entityType) {
    return switch (entityType) {
      'product' => 'view_products',
      'category' => 'view_categories',
      'user' => 'view_users',
      'merchant_qr' => 'view_settings',
      'announcement' => 'view_announcements',
      _ => 'view_trash',
    };
  }

  String _deletePermissionFor(String entityType) {
    return switch (entityType) {
      'product' => 'delete_products',
      'category' => 'delete_categories',
      'user' => 'delete_users',
      'merchant_qr' => 'edit_settings',
      'announcement' => 'manage_announcements',
      _ => 'view_trash',
    };
  }

  String _labelForType(String type) {
    return switch (type) {
      'product' => 'Products',
      'category' => 'Categories',
      'user' => 'Users',
      'merchant_qr' => 'QR',
      'announcement' => 'Announcements',
      _ => 'Other',
    };
  }
}
