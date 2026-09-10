import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/dialogs/category_dialog.dart';
import 'package:pinoy_pos/ui/dialogs/product_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_detail_row.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/pagination_bar.dart';
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

  /// Client-side pagination, matching the mockup: 10 rows per page.
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Catalog-wide counts for the stat strip. Kept separate from _products
  // so they reflect the whole inventory, not the current search results.
  ({int total, int lowStock, int outOfStock}) _stockSummary =
      (total: 0, lowStock: 0, outOfStock: 0);

  String? get _roleLabel => ref.read(authStateProvider).user?.role.displayName;

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
    _currentPage = 1;
    _loadData();
  }

  void _goToPage(int page) {
    final totalPages = (_filteredProducts.length / _pageSize).ceil();
    if (page < 1 || page > totalPages) return;
    setState(() => _currentPage = page);
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
      title: 'Delete product',
      message: 'Move ${product.name} to Trash? You can restore it later.',
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
      appBar: AppHeader(
        title: 'Products',
        subtitle: _roleLabel,
      ),
      floatingActionButton: createFab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

  /// Summary strip doubling as a stock-status filter. Tapping Low or Out
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
              onTap: () => setState(() {
                _stockFilter = _ProductStockFilter.all;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.warning_amber_outlined,
              color: warningColor,
              value: '${_stockSummary.lowStock}',
              label: 'Low stock',
              selected: _stockFilter == _ProductStockFilter.lowStock,
              onTap: () => setState(() {
                _stockFilter = _ProductStockFilter.lowStock;
                _currentPage = 1;
              }),
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
              onTap: () => setState(() {
                _stockFilter = _ProductStockFilter.outOfStock;
                _currentPage = 1;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Widget? primaryAction) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _searchController,
                  hint: 'Search products',
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              _buildCategoryFilter(),
              if (primaryAction != null) ...[
                const SizedBox(width: Spacing.sm),
                primaryAction,
              ],
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStockFilterChip(_ProductStockFilter.all, 'All'),
              const SizedBox(width: Spacing.xs),
              _buildStockFilterChip(_ProductStockFilter.lowStock, 'Low stock'),
              const SizedBox(width: Spacing.xs),
              _buildStockFilterChip(
                  _ProductStockFilter.outOfStock, 'Out of stock'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final cs = Theme.of(context).colorScheme;
    final selectedLabel =
        _selectedCategoryId == null ? 'All' : _categoryName(_selectedCategoryId);

    return PopupMenuButton<int?>(
      initialValue: _selectedCategoryId,
      onSelected: (value) => setState(() {
        _selectedCategoryId = value;
        _currentPage = 1;
      }),
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

  Widget _buildStockFilterChip(_ProductStockFilter filter, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _stockFilter == filter;

    return RawMaterialButton(
      onPressed: () {
        setState(() {
          _stockFilter = isSelected ? _ProductStockFilter.all : filter;
          _currentPage = 1;
        });
      },
      elevation: 0,
      fillColor: isSelected ? cs.primary : cs.surface,
      splashColor: cs.onPrimary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outline,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium(context).copyWith(
          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
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
                  _currentPage = 1;
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
    final brightness = Theme.of(context).brightness;
    final listAccent = AppSemanticColors.resolve(AppSemanticColors.violet, brightness);

    final filtered = _filteredProducts;
    final totalPages = (filtered.length / _pageSize).ceil();
    final effectivePage = math.min(_currentPage, math.max(totalPages, 1));
    final pageItems = filtered
        .skip((effectivePage - 1) * _pageSize)
        .take(_pageSize)
        .toList();

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
            '${filtered.length} items',
            listAccent,
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                bottomClearance + Spacing.md,
              ),
              itemCount: pageItems.length + (totalPages > 1 ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == pageItems.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.sm,
                    ),
                    child: PaginationBar(
                      totalItems: filtered.length,
                      currentPage: effectivePage,
                      pageSize: _pageSize,
                      onPageChanged: _goToPage,
                    ),
                  );
                }
                final product = pageItems[index];
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
    final brightness = Theme.of(context).brightness;
    final canView =
        ref.read(authStateProvider.notifier).hasPermission('view_products');

    final stockColor = product.stock <= 0
        ? cs.error
        : product.isLowStock
            ? AppSemanticColors.resolve(AppSemanticColors.warning, brightness)
            : cs.onSurfaceVariant;

    return InkWell(
      onTap: canView ? () => _showProductView(product, category, canEdit) : null,
      child: Padding(
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
                      _buildCategoryChip(category, brightness),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        'Stock: ${product.stock}',
                        style: AppTypography.bodySmall(context).copyWith(
                          color: stockColor,
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

  Widget _buildCategoryChip(Category category, Brightness brightness) {
    final chipColor = _categoryBadgeColor(category.name, brightness);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        category.name,
        style: AppTypography.labelSmall(context).copyWith(
          fontWeight: FontWeight.w700,
          color: chipColor,
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
            _showProductView(product, category, canEdit);
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

  /// Semantic category badge colour used for the product row category chip.
  /// Matches the category-screen palette so products and categories share one
  /// visual language.
  Color _categoryBadgeColor(String name, Brightness brightness) {
    final n = name.toLowerCase();
    if (n.contains('coffee')) {
      return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    }
    if (n.contains('drink') ||
        n.contains('beverage') ||
        n.contains('juice') ||
        n.contains('tea')) {
      return AppSemanticColors.resolve(AppSemanticColors.teal, brightness);
    }
    if (n.contains('dessert') ||
        n.contains('sweet') ||
        n.contains('cake') ||
        n.contains('bread') ||
        n.contains('baker')) {
      return AppSemanticColors.resolve(AppSemanticColors.violet, brightness);
    }
    if (n.contains('snack') || n.contains('merienda')) {
      return AppSemanticColors.resolve(AppSemanticColors.error, brightness);
    }
    if (n.contains('meal') ||
        n.contains('rice') ||
        n.contains('food') ||
        n.contains('ulam')) {
      return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    }
    return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
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

  void _showProductView(Product product, Category category, bool canEdit) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final status = product.stock <= 0
            ? 'Out of stock'
            : product.isLowStock
                ? 'Low stock'
                : 'In stock';
        final statusColor = product.stock <= 0
            ? cs.error
            : product.isLowStock
                ? AppSemanticColors.resolve(
                    AppSemanticColors.warning,
                    Theme.of(context).brightness,
                  )
                : AppSemanticColors.resolve(
                    AppSemanticColors.success,
                    Theme.of(context).brightness,
                  );
        final viewRows = [
          AppDetailRow(
            icon: Icons.label_outline,
            iconColor: _categoryBadgeColor(
              category.name,
              Theme.of(context).brightness,
            ),
            label: 'Category',
            value: category.name,
          ),
          AppDetailRow(
            icon: Icons.payments_outlined,
            iconColor: cs.primary,
            label: 'Price',
            value: CurrencyUtils.format(product.price),
          ),
          AppDetailRow(
            icon: Icons.inventory_2_outlined,
            iconColor: statusColor,
            label: 'Stock',
            value: '${product.stock} units',
          ),
          AppDetailRow(
            icon: product.stock <= 0
                ? Icons.error_outline
                : product.isLowStock
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
            iconColor: statusColor,
            label: 'Status',
            value: status,
            valueColor: statusColor,
          ),
        ];

        return AppDialog(
          type: AppDialogType.info,
          title: product.name,
          message: 'Product details',
          icon: Icons.visibility_outlined,
          iconColor: AppSemanticColors.resolve(
            AppSemanticColors.info,
            Theme.of(context).brightness,
          ),
          actions: [
            AppDialogAction(
              label: 'Close',
              onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
            ),
            if (canEdit)
              AppDialogAction(
                label: 'Edit',
                isPrimary: true,
                onPressed: (dialogContext) {
                  Navigator.of(dialogContext).pop();
                  _showProductDialog(product: product);
                },
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
              for (var i = 0; i < viewRows.length; i++) ...[
                viewRows[i],
                if (i < viewRows.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
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
