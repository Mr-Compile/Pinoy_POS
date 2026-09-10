import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/dialogs/category_dialog.dart';
import 'package:pinoy_pos/ui/dialogs/product_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';
import 'package:pinoy_pos/ui/widgets/summary_stat_card.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

/// Stock-status filter driven by the summary stat strip.
enum _ProductStockFilter { all, lowStock, outOfStock }

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;

  // Search + filter state (view-only operations, allowed for all roles with
  // view_products). Search delegates to ProductService.searchProducts so the
  // query runs at the DAO/SQLite level; category filter is applied to the
  // already-authorized list loaded from the service.
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryId;
  _ProductStockFilter _stockFilter = _ProductStockFilter.all;

  // Catalog-wide counts for the stat strip. Kept separate from _products
  // so they reflect the whole inventory, not the current search results.
  ({int total, int lowStock, int outOfStock}) _stockSummary =
      (total: 0, lowStock: 0, outOfStock: 0);

  // Kept alive inside the app shell's PageView: reload whenever catalog
  // data changes elsewhere (POS sale, stock adjustment, trash restore).
  ProviderSubscription<int>? _catalogSubscription;

  @override
  void initState() {
    super.initState();
    _catalogSubscription = ref.listenManual<int>(
      catalogRevisionProvider,
      (previous, next) => _loadData(),
    );
    _loadData();
  }

  @override
  void dispose() {
    _catalogSubscription?.close();
    _catalogSubscription = null;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final productService = ref.read(productServiceProvider);
      final categoryService = ref.read(categoryServiceProvider);
      final categories = await categoryService.getActiveCategories();
      final stockSummary = await productService.getStockSummary();

      // When a search query is active, run the search at the DAO level;
      // otherwise load all active products.
      final products = _searchQuery.isEmpty
          ? await productService.getActiveProducts()
          : await productService.searchProducts(_searchQuery);

      if (mounted) {
        setState(() {
          _products = products;
          _categories = categories;
          _stockSummary = stockSummary;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('ProductsScreen _loadData error: $e');
      debugPrint(st.toString());
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Products after applying the optional category and stock-status
  /// filters. Both are applied to the already-authorized product list, so
  /// they never bypass the service-layer read permission.
  List<Product> get _filteredProducts {
    var result = _products;
    if (_selectedCategoryId != null) {
      result =
          result.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    switch (_stockFilter) {
      case _ProductStockFilter.lowStock:
        result =
            result.where((p) => p.stock > 0 && p.isLowStock).toList();
      case _ProductStockFilter.outOfStock:
        result = result.where((p) => p.stock <= 0).toList();
      case _ProductStockFilter.all:
        break;
    }
    return result;
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    if (query == _searchQuery) return;
    _searchQuery = query;
    _loadData();
  }

  Future<void> _deleteProduct(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_products')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: product.name,
    );

    if (confirmed == true && mounted) {
      try {
        final productService = ref.read(productServiceProvider);
        await productService.deleteProduct(product.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Deleted', message: 'Product deleted successfully.');
          bumpCatalogRevision(ref);
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to delete product.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canEdit = authNotifier.hasPermission('edit_products');
    final canDelete = authNotifier.hasPermission('delete_products');

    final createAction = canEdit
        ? ResponsiveCreateAction(
            label: 'Add Product',
            icon: Icons.add,
            onPressed: _showProductDialog,
          )
        : null;

    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Products'),
        body: LoadingState(),
      );
    }

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;

    return Scaffold(
      appBar: const AppHeader(title: 'Products'),
      floatingActionButton: createFab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRoleChipBar(),
          if (_stockSummary.total > 0) _buildStatsStrip(),
          _buildToolbar(toolbarAction),
          Expanded(
            child: _filteredProducts.isEmpty
                ? _buildEmptyState()
                : _buildProductList(canEdit, canDelete, bottomClearance),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChipBar() {
    final cs = Theme.of(context).colorScheme;
    final user = ref.read(authStateProvider).user;
    final isOwner = user?.role == UserRole.owner;
    final roleColor = isOwner
        ? AppSemanticColors.resolve(AppSemanticColors.info, Theme.of(context).brightness)
        : AppSemanticColors.resolve(AppSemanticColors.success, Theme.of(context).brightness);

    final label = isOwner ? 'Owner' : 'Staff';
    final permText = isOwner
        ? 'view/edit/delete products'
        : 'view products only';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.16),
              border: Border.all(color: roleColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_outline,
                  size: 12,
                  color: roleColor,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.labelSmall(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: roleColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              permText,
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Summary strip doubling as a stock-status filter. Tapping Low or Out
  /// of Stock toggles that filter; tapping it again (or Products) resets
  /// to the full list.
  Widget _buildStatsStrip() {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final warningColor = AppSemanticColors.resolve(
      AppSemanticColors.warning,
      brightness,
    );
    final errorColor = AppSemanticColors.resolve(
      AppSemanticColors.error,
      brightness,
    );

    void select(_ProductStockFilter filter) {
      setState(() {
        _stockFilter = _stockFilter == filter
            ? _ProductStockFilter.all
            : filter;
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: SummaryStatCard(
              icon: Icons.inventory_2_outlined,
              color: cs.primary,
              value: '${_stockSummary.total}',
              label: 'Products',
              selected: _stockFilter == _ProductStockFilter.all,
              onTap: () => select(_ProductStockFilter.all),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.warning_amber,
              color: warningColor,
              value: '${_stockSummary.lowStock}',
              label: 'Low stock',
              selected: _stockFilter == _ProductStockFilter.lowStock,
              onTap: () => select(_ProductStockFilter.lowStock),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.error_outline,
              color: errorColor,
              value: '${_stockSummary.outOfStock}',
              label: 'Out of stock',
              selected: _stockFilter == _ProductStockFilter.outOfStock,
              onTap: () => select(_ProductStockFilter.outOfStock),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Widget? primaryAction) {
    return CrudToolbar(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      search: AppSearchField(
        controller: _searchController,
        hint: 'Search products',
        onChanged: _onSearchChanged,
      ),
      controls: [
        _buildCategoryFilter(),
      ],
      primaryAction: primaryAction,
    );
  }

  Widget _buildCategoryFilter() {
    final cs = Theme.of(context).colorScheme;
    final selectedLabel =
        _selectedCategoryId == null ? 'All' : _categoryName(_selectedCategoryId);

    return PopupMenuButton<int?>(
      initialValue: _selectedCategoryId,
      onSelected: (value) => setState(() => _selectedCategoryId = value),
      offset: const Offset(0, 40),
      itemBuilder: (context) => [
        PopupMenuItem<int?>(
          value: null,
          child: Row(
            children: [
              Icon(Icons.all_inbox, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              const Text('All'),
            ],
          ),
        ),
        ..._categories.map((category) {
          return PopupMenuItem<int?>(
            value: category.id,
            child: Row(
              children: [
                Icon(Icons.label_outline, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(category.name),
              ],
            ),
          );
        }),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              selectedLabel,
              style: AppTypography.bodySmall(context),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canEditCategories = authNotifier.hasPermission('edit_categories');
    final hasFilters = _searchQuery.isNotEmpty ||
        _selectedCategoryId != null ||
        _stockFilter != _ProductStockFilter.all;

    if (_products.isEmpty && _categories.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2,
        title: 'Set up your inventory',
        message: canEditCategories
            ? 'Start with Step 1: create a category. Then add your first product.'
            : 'No products or categories exist. Ask an administrator to create a category first.',
        action: canEditCategories
            ? AppButton.outlined(
                icon: Icons.category,
                label: 'Create Category',
                onPressed: _showCreateCategoryDialog,
                fullWidth: true,
              )
            : null,
      );
    }

    return EmptyState(
      icon: _products.isEmpty ? Icons.inventory_2 : Icons.search_off,
      title: _products.isEmpty ? 'No Products Yet' : 'No Products Found',
      message: _products.isEmpty
          ? 'Add your first product to start building your inventory.'
          : _searchQuery.isNotEmpty
              ? 'No products match your search.'
              : 'No products match the selected filters.',
      action: hasFilters && _products.isNotEmpty
          ? TextButton.icon(
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategoryId = null;
                  _stockFilter = _ProductStockFilter.all;
                });
                _loadData();
              },
            )
          : null,
    );
  }

  Widget _buildProductList(
    bool canEdit,
    bool canDelete,
    double bottomClearance,
  ) {
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
      ),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCardHead(
            'All Products',
            Icons.inventory_2_outlined,
            '${_filteredProducts.length} items',
            Theme.of(context).colorScheme.primary,
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                bottomClearance + Spacing.md,
              ),
              itemCount: _filteredProducts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                final category = _categories.firstWhere(
                  (c) => c.id == product.categoryId,
                  orElse: () => Category(
                    id: 0,
                    name: 'Uncategorized',
                    createdAt: DateTime.now(),
                  ),
                );
                return _buildProductRow(
                  product,
                  category,
                  canEdit,
                  canDelete,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHead(
    String title,
    IconData icon,
    String pill,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            title,
            style: AppTypography.titleMediumBold(context),
          ),
          const Spacer(),
          AppStatusChip(
            label: pill,
            color: color,
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(
    Product product,
    Category category,
    bool canEdit,
    bool canDelete,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildProductThumb(product),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: AppTypography.titleMediumSemibold(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMiniChip(category.name),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      'Stock: ${product.stock}',
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            CurrencyUtils.format(product.price),
            style: AppTypography.titleMediumBold(context).copyWith(
              color: cs.primary,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _buildProductActions(product, category, canEdit, canDelete),
        ],
      ),
    );
  }

  Widget _buildProductThumb(Product product) {
    final cs = Theme.of(context).colorScheme;
    final initials = _initials(product.name);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppImage(
        imagePath: product.imageUrl,
        placeholderIcon: Icons.inventory_2,
        placeholderIconSize: 24,
        borderRadius: AppRadius.md,
        fit: BoxFit.cover,
        placeholderBuilder: (context) => Center(
          child: Text(
            initials,
            style: AppTypography.labelMedium(context).copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall(context).copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildProductActions(
    Product product,
    Category category,
    bool canEdit,
    bool canDelete,
  ) {
    final cs = Theme.of(context).colorScheme;
    final canView =
        ref.read(authStateProvider.notifier).hasPermission('view_products');
    final neutralColor = cs.onSurfaceVariant;
    final editColor = cs.primary;
    final deleteColor = cs.error;

    final items = <PopupMenuEntry<String>>[
      if (canView)
        PopupMenuItem<String>(
          value: 'view',
          child: _buildMenuItem(
            Icons.visibility_outlined,
            'View',
            neutralColor,
          ),
        ),
      if (canEdit)
        PopupMenuItem<String>(
          value: 'edit',
          child: _buildMenuItem(
            Icons.edit,
            'Edit',
            editColor,
          ),
        ),
      if (canDelete)
        PopupMenuItem<String>(
          value: 'delete',
          child: _buildMenuItem(
            Icons.delete,
            'Delete',
            deleteColor,
          ),
        ),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
      tooltip: 'Product options',
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case 'view':
            _showProductView(product, category);
            break;
          case 'edit':
            _showProductDialog(product: product);
            break;
          case 'delete':
            _deleteProduct(product);
            break;
        }
      },
      itemBuilder: (context) => items,
    );
  }

  Widget _buildMenuItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final buffer = StringBuffer();
    final parts = name.trim().split(RegExp(r'\s+'));
    for (final part in parts) {
      if (part.isNotEmpty) {
        buffer.write(part[0].toUpperCase());
      }
      if (buffer.length == 2) break;
    }
    return buffer.isEmpty ? '?' : buffer.toString();
  }

  String _categoryName(int? categoryId) {
    if (categoryId == null) return 'All';
    try {
      return _categories.firstWhere((c) => c.id == categoryId).name;
    } catch (_) {
      return 'Uncategorized';
    }
  }

  Future<void> _showProductDialog({Product? product}) async {
    final result = await showProductDialog(context, ref, product: product);

    if (!mounted) return;

    if (result?.isSaved ?? false) {
      // The catalog-revision listener reloads this screen and the POS.
      bumpCatalogRevision(ref);
      if (mounted) {
        await AppDialogService.success(
          context,
          title: product == null ? 'Created' : 'Updated',
          message: product == null
              ? 'Product created successfully.'
              : 'Product updated successfully.',
        );
      }
    }
  }

  void _showProductView(Product product, Category category) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AppDialog(
          type: AppDialogType.info,
          title: product.name,
          message: 'Product details',
          actions: [
            AppDialogAction(
              label: 'Close',
              onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: AppImage(
                      imagePath: product.imageUrl,
                      placeholderIcon: Icons.inventory_2,
                      placeholderIconSize: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              _buildViewRow('Category', category.name),
              _buildViewRow('Price', CurrencyUtils.format(product.price)),
              _buildViewRow('Stock', '${product.stock}'),
              _buildViewRow('Minimum Stock', '${product.minStock}'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMedium(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: AppTypography.titleSmall(context).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCategoryDialog() async {
    final result = await showCategoryDialog(context, ref);

    if (!mounted) return;

    if (result?.isSaved ?? false) {
      bumpCatalogRevision(ref);
      if (mounted) {
        await AppDialogService.success(
          context,
          title: 'Category Created',
          message: 'You can now add your first product.',
        );
      }
    }
  }
}
