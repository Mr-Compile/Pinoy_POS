import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_detail_row.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
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

/// Stock status filter options.
enum StockFilter { all, lowStock, outOfStock }

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  // Search + filter state
  final _searchController = TextEditingController();
  String _searchQuery = '';
  StockFilter _stockFilter = StockFilter.all;
  int? _selectedCategoryId;
  Timer? _debounce;

  /// Client-side pagination, matching the mockup: 10 rows per page.
  int _currentPage = 1;
  static const int _pageSize = 10;

  String? get _roleLabel => ref.read(authStateProvider).user?.role.displayName;

  // Kept alive inside the app shell's PageView: reload whenever catalog
  // data changes elsewhere (product save, POS sale, trash restore).
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
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final productService = ref.read(productServiceProvider);
    final categoryService = ref.read(categoryServiceProvider);

    final categories = await categoryService.getActiveCategories();
    final products = await productService.getActiveProducts();

    if (mounted) {
      setState(() {
        _categories = categories;
        _products = products;
        _isLoading = false;
      });
    }
  }

  // ── Filtered products ──────────────────────────────────────────────

  List<Product> get _filteredProducts {
    var result = _products;

    // Category filter
    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId).toList();
    }

    // Stock status filter
    switch (_stockFilter) {
      case StockFilter.lowStock:
        result = result.where((p) => p.stock > 0 && p.isLowStock).toList();
        break;
      case StockFilter.outOfStock:
        result = result.where((p) => p.stock <= 0).toList();
        break;
      case StockFilter.all:
        break;
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) => p.name.toLowerCase().contains(query)).toList();
    }

    return result;
  }

  // ── Stock status helpers ───────────────────────────────────────────

  bool _isOutOfStock(Product p) => p.stock <= 0;
  bool _isLowStock(Product p) => p.stock > 0 && p.isLowStock;

  String _categoryName(int? categoryId) {
    if (categoryId == null) return 'Uncategorized';
    try {
      return _categories.firstWhere((c) => c.id == categoryId).name;
    } catch (_) {
      return 'Uncategorized';
    }
  }

  Color _stockColor(Product product) {
    if (_isOutOfStock(product)) {
      return Theme.of(context).colorScheme.error;
    }
    if (_isLowStock(product)) {
      return AppSemanticColors.resolve(
        AppSemanticColors.warning,
        Theme.of(context).brightness,
      );
    }
    return AppSemanticColors.resolve(
      AppSemanticColors.success,
      Theme.of(context).brightness,
    );
  }

  // ── Search ─────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value.trim();
          _currentPage = 1;
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _currentPage = 1;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _stockFilter = StockFilter.all;
      _searchQuery = '';
      _currentPage = 1;
    });
    _searchController.clear();
  }

  void _goToPage(int page) {
    final totalPages = (_filteredProducts.length / _pageSize).ceil();
    if (page < 1 || page > totalPages) return;
    setState(() => _currentPage = page);
  }

  // ── Stock operations ───────────────────────────────────────────────

  Future<void> _showAddStockDialog(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('add_stock')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final result = await showDialog<_StockOperationResult?>(
      context: context,
      builder: (context) => _StockOperationDialog(
        product: product,
        category: _categoryName(product.categoryId),
        isAdjust: false,
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final stockService = ref.read(stockServiceProvider);
      final success = await stockService.addStock(
        product.id!,
        result.quantity,
        result.reason,
      );

      if (mounted) {
        if (success) {
          await AppDialogService.success(
            context,
            title: 'Stock Added',
            message: '${product.name} stock updated from ${product.stock} to ${product.stock + result.quantity} units.',
          );
          bumpCatalogRevision(ref);
        } else {
          AppDialogService.error(context,
              title: 'Operation Failed',
              message: 'Failed to add stock. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Operation Failed',
            message: 'An error occurred while adding stock.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showAdjustStockDialog(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('adjust_stock')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final result = await showDialog<_StockOperationResult?>(
      context: context,
      builder: (context) => _StockOperationDialog(
        product: product,
        category: _categoryName(product.categoryId),
        isAdjust: true,
      ),
    );

    if (result == null || !mounted) return;

    // Confirm adjustment
    final difference = result.newStock - product.stock;
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Confirm Stock Adjustment',
      message:
          '${product.name} will change from ${product.stock} to ${result.newStock} units (difference: ${difference >= 0 ? '+' : ''}$difference).',
      confirmLabel: 'Confirm Adjustment',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final stockService = ref.read(stockServiceProvider);
      final success = await stockService.adjustStock(
        product.id!,
        result.newStock,
        result.reason ?? 'Manual adjustment',
      );

      if (mounted) {
        if (success) {
          await AppDialogService.success(
            context,
            title: 'Stock Adjusted',
            message: '${product.name} stock updated from ${product.stock} to ${result.newStock} units.',
          );
          bumpCatalogRevision(ref);
        } else {
          AppDialogService.error(context,
              title: 'Operation Failed',
              message: 'Failed to adjust stock. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context,
            title: 'Operation Failed',
            message: 'An error occurred while adjusting stock.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showStockView(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_stock')) {
      AppDialogService.accessDenied(context);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => _StockViewDialog(
        product: product,
        categoryName: _categoryName(product.categoryId),
        onAdd: () {
          Navigator.of(context, rootNavigator: true).pop();
          _showAddStockDialog(product);
        },
        onAdjust: () {
          Navigator.of(context, rootNavigator: true).pop();
          _showAdjustStockDialog(product);
        },
        canAddStock: authNotifier.hasPermission('add_stock'),
        canAdjustStock: authNotifier.hasPermission('adjust_stock'),
      ),
    );
  }

  Future<void> _showStockHistory(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('view_stock')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final stockService = ref.read(stockServiceProvider);
    final history = await stockService.getStockHistory(product.id!);

    if (!mounted) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => _StockHistoryDialog(
        product: product,
        history: history,
        categoryName: _categoryName(product.categoryId),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canAddStock = authNotifier.hasPermission('add_stock');
    final canAdjustStock = authNotifier.hasPermission('adjust_stock');
    final canViewStock = authNotifier.hasPermission('view_stock');

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Stock',
          subtitle: _roleLabel,
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    final createAction = canAddStock && _products.isNotEmpty
        ? ResponsiveCreateAction(
            label: 'Add Stock',
            icon: Icons.add,
            onPressed: _isProcessing ? null : _showProductPickerDialog,
          )
        : null;

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;

    return Scaffold(
      appBar: AppHeader(
        title: 'Stock',
        subtitle: _roleLabel,
        showBackButton: true,
      ),
      floatingActionButton: createFab,
      body: _products.isEmpty
          ? _buildNoProductsState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatsStrip(),
                _buildToolbar(toolbarAction),
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? _buildEmptyFilterState()
                      : _buildStockList(
                          canAddStock,
                          canAdjustStock,
                          canViewStock,
                          bottomClearance,
                        ),
                ),
              ],
            ),
    );
  }

  // ── No products state ──────────────────────────────────────────────

  Widget _buildNoProductsState() {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManageProducts = authNotifier.hasPermission('edit_products');
    return EmptyState(
      icon: Icons.inventory_2,
      title: 'No Products Available',
      message: canManageProducts
          ? 'Add products first to manage their stock.'
          : 'Please ask an administrator to add products.',
    );
  }

  // ── Stats strip: catalog-wide stock counts ─────────────────────────

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

    final lowStockCount = _products.where(_isLowStock).length;
    final outOfStockCount = _products.where(_isOutOfStock).length;

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
              value: '${_products.length}',
              label: 'Products',
              selected: _stockFilter == StockFilter.all,
              onTap: () => setState(() {
                _stockFilter = StockFilter.all;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.warning_amber_outlined,
              color: warningColor,
              value: '$lowStockCount',
              label: 'Low stock',
              selected: _stockFilter == StockFilter.lowStock,
              onTap: () => setState(() {
                _stockFilter = StockFilter.lowStock;
                _currentPage = 1;
              }),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.error_outline,
              color: errorColor,
              value: '$outOfStockCount',
              label: 'Out of stock',
              selected: _stockFilter == StockFilter.outOfStock,
              onTap: () => setState(() {
                _stockFilter = StockFilter.outOfStock;
                _currentPage = 1;
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar: search + category filter + stock chips ────────────────

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
                  onClear: _clearSearch,
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
              _buildStockFilterChip(StockFilter.all, 'All'),
              const SizedBox(width: Spacing.xs),
              _buildStockFilterChip(StockFilter.lowStock, 'Low'),
              const SizedBox(width: Spacing.xs),
              _buildStockFilterChip(StockFilter.outOfStock, 'Out'),
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
              Icon(Icons.filter_list, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              const Text('All Categories'),
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

  Widget _buildStockFilterChip(StockFilter filter, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _stockFilter == filter;

    return RawMaterialButton(
      onPressed: () {
        setState(() {
          _stockFilter = isSelected ? StockFilter.all : filter;
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

  // ── Empty filter state ─────────────────────────────────────────────

  Widget _buildEmptyFilterState() {
    final hasFilters = _searchQuery.isNotEmpty ||
        _selectedCategoryId != null ||
        _stockFilter != StockFilter.all;

    String title;
    String message;
    if (!hasFilters) {
      title = 'No Products Available';
      message = 'Products will appear here once added.';
    } else if (_searchQuery.isNotEmpty) {
      title = 'No Products Found';
      message = "No products match '$_searchQuery'. Try a different search term.";
    } else if (_stockFilter == StockFilter.lowStock) {
      title = 'No Low-Stock Products';
      message = 'All products are above their minimum stock level.';
    } else if (_stockFilter == StockFilter.outOfStock) {
      title = 'No Out-of-Stock Products';
      message = 'All products have stock available.';
    } else {
      title = 'No Products in This Category';
      message = 'No products found for the selected category.';
    }

    return EmptyState(
      icon: Icons.search_off,
      title: title,
      message: message,
      action: hasFilters
          ? TextButton.icon(
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              onPressed: _clearFilters,
            )
          : null,
    );
  }

  // ── Stock list ─────────────────────────────────────────────────────

  Widget _buildStockList(
    bool canAddStock,
    bool canAdjustStock,
    bool canViewStock,
    double bottomClearance,
  ) {
    final brightness = Theme.of(context).brightness;
    final headColor = AppSemanticColors.resolve(
      AppSemanticColors.warning,
      brightness,
    );

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
            'Inventory',
            Icons.inventory_2_outlined,
            '${filtered.length} items',
            headColor,
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
                return _buildStockRow(
                  product,
                  canAddStock,
                  canAdjustStock,
                  canViewStock,
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
            color: Theme.of(context).colorScheme.primary,
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStockRow(
    Product product,
    bool canAddStock,
    bool canAdjustStock,
    bool canViewStock,
  ) {
    final cs = Theme.of(context).colorScheme;
    final stockColor = _stockColor(product);

    return InkWell(
      onTap: canViewStock ? () => _showStockView(product) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildStockThumb(product),
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
                  Text(
                    '${_categoryName(product.categoryId)} · Min ${product.minStock}',
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            _buildStockPill('${product.stock} left', stockColor),
            const SizedBox(width: Spacing.sm),
            _buildStockActions(
              product,
              canAddStock,
              canAdjustStock,
              canViewStock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockThumb(Product product) {
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

  Widget _buildStockPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall(context).copyWith(
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStockActions(
    Product product,
    bool canAddStock,
    bool canAdjustStock,
    bool canViewStock,
  ) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final successColor = AppSemanticColors.resolve(
      AppSemanticColors.success,
      brightness,
    );
    final warningColor = AppSemanticColors.resolve(
      AppSemanticColors.warning,
      brightness,
    );
    final infoColor = AppSemanticColors.resolve(
      AppSemanticColors.info,
      brightness,
    );

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
      tooltip: 'Stock options',
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case 'view':
            _showStockView(product);
            break;
          case 'add':
            _showAddStockDialog(product);
            break;
          case 'adjust':
            _showAdjustStockDialog(product);
            break;
          case 'history':
            _showStockHistory(product);
            break;
        }
      },
      itemBuilder: (context) => [
        if (canViewStock)
          PopupMenuItem<String>(
            value: 'view',
            child: _buildMenuItem(
              Icons.visibility_outlined,
              'View',
              infoColor,
            ),
          ),
        if (canAddStock)
          PopupMenuItem<String>(
            value: 'add',
            child: _buildMenuItem(
              Icons.add,
              'Add stock',
              successColor,
            ),
          ),
        if (canAdjustStock)
          PopupMenuItem<String>(
            value: 'adjust',
            child: _buildMenuItem(
              Icons.edit,
              'Adjust',
              warningColor,
            ),
          ),
        if (canViewStock)
          PopupMenuItem<String>(
            value: 'history',
            child: _buildMenuItem(
              Icons.history,
              'History',
              infoColor,
            ),
          ),
      ],
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

  // ── Product picker dialog (for FAB Add Stock) ──────────────────────

  Future<void> _showProductPickerDialog() async {
    final searchController = TextEditingController();
    final selectedProduct = await showDialog<Product>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final query = searchController.text.toLowerCase();
            final filtered = query.isEmpty
                ? _products
                : _products
                    .where((p) => p.name.toLowerCase().contains(query))
                    .toList();

            final brightness = Theme.of(context).brightness;

            return AppDialog(
              type: AppDialogType.add,
              title: 'Select Product',
              message: 'Choose the product to add stock to.',
              icon: Icons.add,
              iconColor: AppSemanticColors.resolve(
                AppSemanticColors.warning,
                brightness,
              ),
              actions: [
                AppDialogAction(
                  label: 'Cancel',
                  onPressed: (context) => Navigator.of(context, rootNavigator: true).pop(),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSearchField(
                    controller: searchController,
                    hint: 'Search products',
                    onChanged: (_) => setState(() {}),
                    onClear: () {
                      searchController.clear();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: Spacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No products found.'),
                          )
                        : ListView.builder(
                            physics: const ClampingScrollPhysics(),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              final stockColor = _stockColor(product);
                              return InkWell(
                                onTap: () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(product),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Spacing.sm,
                                  ),
                                  child: Row(
                                    children: [
                                      _buildStockThumb(product),
                                      const SizedBox(width: Spacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              product.name,
                                              style: AppTypography
                                                  .titleMediumSemibold(context),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: Spacing.xs),
                                            Text(
                                              'Stock: ${product.stock} · ${_categoryName(product.categoryId)}',
                                              style: AppTypography.bodySmall(
                                                      context)
                                                  .copyWith(
                                                color: _isOutOfStock(product)
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: Spacing.sm),
                                      _buildStockPill(
                                        '${product.stock} left',
                                        stockColor,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    searchController.dispose();

    if (selectedProduct == null || !mounted) return;

    // Show the add stock dialog for the selected product
    _showAddStockDialog(selectedProduct);
  }
}

// ── Stock operation result ───────────────────────────────────────────

class _StockOperationResult {
  final int quantity;
  final int newStock;
  final String? reason;

  _StockOperationResult({
    required this.quantity,
    required this.newStock,
    this.reason,
  });
}

// ── Stock operation dialog (Add / Adjust) ────────────────────────────

class _StockOperationDialog extends StatelessWidget {
  final Product product;
  final String category;
  final bool isAdjust;

  const _StockOperationDialog({
    required this.product,
    required this.category,
    required this.isAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAdjust ? 'Adjust Stock' : 'Add Stock';
    final message = isAdjust
        ? 'Set the new stock quantity.'
        : 'Enter the quantity to add.';
    final brightness = Theme.of(context).brightness;

    return AppDialogForm<_StockOperationResult?>(
      type: isAdjust ? AppDialogType.edit : AppDialogType.add,
      title: title,
      message: message,
      icon: isAdjust ? Icons.tune : Icons.add,
      iconColor: AppSemanticColors.resolve(
        AppSemanticColors.warning,
        brightness,
      ),
      childBuilder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final quantityController = state.textController(
          'quantity',
          text: isAdjust ? product.stock.toString() : '',
        );
        final reasonController = state.textController('reason');
        final qtyValue =
            state.value<int>('quantity', isAdjust ? product.stock : 0) ?? 0;

        return Form(
          key: state.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductInfo(context, cs),
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Stock',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${product.stock}',
                    style: AppTypography.titleMediumBold(context),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              AppTextFormField(
                controller: quantityController,
                label: isAdjust ? 'New Stock Quantity' : 'Quantity to Add',
                hint: 'Enter quantity',
                prefixIcon: Icons.inventory,
                keyboardType: TextInputType.number,
                validator: (value) {
                  final q = int.tryParse(value?.trim() ?? '');
                  if (q == null) return 'Enter a valid number';
                  if (q <= 0) return 'Quantity must be greater than 0';
                  if (isAdjust && q > 999999) return 'Value too large';
                  return null;
                },
                onChanged: (value) {
                  state.setValue<int>(
                    'quantity',
                    int.tryParse(value.trim()) ?? 0,
                  );
                },
                onFieldSubmitted: (_) => _save(state),
              ),
              const SizedBox(height: Spacing.md),
              if (qtyValue > 0)
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAdjust ? 'New Stock' : 'Stock After Adding',
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      Text(
                        isAdjust ? '$qtyValue' : '${product.stock + qtyValue}',
                        style: AppTypography.titleLargeBold(context)
                            .copyWith(color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.md),
              AppTextFormField(
                controller: reasonController,
                label: 'Remarks (optional)',
                hint: 'e.g. Restock / Adjustment',
                maxLines: 2,
                onChanged: (_) => state.markChanged(),
              ),
            ],
          ),
        );
      },
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          onPressed: state.isSaving
              ? null
              : (context) => state.pop(null),
        ),
        AppDialogAction(
          label: isAdjust ? 'Continue' : 'Add Stock',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving ? null : (context) => _save(state),
        ),
      ],
    );
  }

  Widget _buildProductInfo(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 40,
              height: 40,
              child: AppImage(
                imagePath: product.imageUrl,
                placeholderIcon: Icons.inventory_2,
                placeholderIconSize: 18,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.titleMediumBold(context),
                ),
                Text(
                  category,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _save(AppDialogFormState<_StockOperationResult?> state) {
    if (!state.formKey.currentState!.validate()) return;

    final qty = int.parse(state.textController('quantity').text.trim());
    final reason = state.textController('reason').text.trim();

    state.pop(
      _StockOperationResult(
        quantity: isAdjust ? qty - product.stock : qty,
        newStock: isAdjust ? qty : product.stock + qty,
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }
}

// ── Stock view dialog ────────────────────────────────────────────────

class _StockViewDialog extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback onAdd;
  final VoidCallback onAdjust;
  final bool canAddStock;
  final bool canAdjustStock;

  const _StockViewDialog({
    required this.product,
    required this.categoryName,
    required this.onAdd,
    required this.onAdjust,
    required this.canAddStock,
    required this.canAdjustStock,
  });

  Color _stockColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (product.stock <= 0) return cs.error;
    if (product.isLowStock) {
      return AppSemanticColors.resolve(
        AppSemanticColors.warning,
        Theme.of(context).brightness,
      );
    }
    return AppSemanticColors.resolve(
      AppSemanticColors.success,
      Theme.of(context).brightness,
    );
  }

  String _stockStatus() {
    if (product.stock <= 0) return 'Out of stock';
    if (product.isLowStock) return 'Low stock';
    return 'In stock';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final stockColor = _stockColor(context);

    final statusIcon = product.stock <= 0
        ? Icons.error_outline
        : product.isLowStock
            ? Icons.warning_amber_outlined
            : Icons.check_circle_outline;

    final viewRows = [
      AppDetailRow(
        icon: Icons.inventory_2_outlined,
        iconColor: stockColor,
        label: 'Current Stock',
        value: '${product.stock} units',
      ),
      AppDetailRow(
        icon: Icons.production_quantity_limits,
        iconColor: cs.primary,
        label: 'Minimum Level',
        value: '${product.minStock}',
      ),
      AppDetailRow(
        icon: statusIcon,
        iconColor: stockColor,
        label: 'Status',
        value: _stockStatus(),
        valueColor: stockColor,
      ),
    ];

    return AppDialog(
      type: AppDialogType.info,
      title: product.name,
      message: 'Stock details',
      icon: Icons.inventory_2,
      iconColor: AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        if (canAddStock)
          AppDialogAction(
            label: 'Add Stock',
            isPrimary: true,
            onPressed: (_) => onAdd(),
          ),
        if (canAdjustStock)
          AppDialogAction(
            label: 'Adjust',
            onPressed: (_) => onAdjust(),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductInfo(context, cs),
          const SizedBox(height: Spacing.lg),
          for (var i = 0; i < viewRows.length; i++) ...[
            viewRows[i],
            if (i < viewRows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildProductInfo(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 40,
              height: 40,
              child: AppImage(
                imagePath: product.imageUrl,
                placeholderIcon: Icons.inventory_2,
                placeholderIconSize: 18,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.titleMediumBold(context),
                ),
                Text(
                  categoryName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}

// ── Stock history dialog ─────────────────────────────────────────────

class _StockHistoryDialog extends StatelessWidget {
  final Product product;
  final List<StockHistory> history;
  final String categoryName;

  const _StockHistoryDialog({
    required this.product,
    required this.history,
    required this.categoryName,
  });

  String _operationLabel(StockOperationType type) {
    switch (type) {
      case StockOperationType.add:
        return 'Added';
      case StockOperationType.adjust:
        return 'Adjusted';
      case StockOperationType.sale:
        return 'Sold';
      case StockOperationType.return_:
        return 'Returned';
    }
  }

  Color _operationColor(
    StockOperationType type,
    Brightness brightness,
    ColorScheme cs,
  ) {
    return switch (type) {
      StockOperationType.add =>
        AppSemanticColors.resolve(AppSemanticColors.success, brightness),
      StockOperationType.adjust =>
        AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      StockOperationType.sale =>
        cs.primary,
      StockOperationType.return_ =>
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return AppDialog(
      type: AppDialogType.info,
      title: 'Stock History',
      message: history.isEmpty
          ? null
          : '${history.length} operation${history.length == 1 ? '' : 's'}',
      actions: [
        AppDialogAction(
          label: 'Close',
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      child: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product info
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: AppImage(
                        imagePath: product.imageUrl,
                        placeholderIcon: Icons.inventory_2,
                        placeholderIconSize: 18,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.titleMediumBold(context),
                        ),
                        Text(
                          'Current stock: ${product.stock}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Spacing.lg),
                child: Center(
                  child: Text('No stock history available.'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: history.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = history[index];
                  final opColor = _operationColor(
                    entry.operation,
                    brightness,
                    cs,
                  );
                  final diff = entry.newStock - entry.previousStock;

                  return ListTile(
                    leading: Icon(
                      entry.operation == StockOperationType.add
                          ? Icons.add_circle
                          : entry.operation == StockOperationType.sale
                              ? Icons.shopping_cart
                              : entry.operation == StockOperationType.adjust
                                  ? Icons.tune
                                  : Icons.undo,
                      color: opColor,
                      size: 28,
                    ),
                    title: Text(
                      '${_operationLabel(entry.operation)} ${entry.quantity > 0 ? '+' : ''}${entry.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${entry.previousStock} → ${entry.newStock} · ${_formatDate(entry.createdAt)}'
                      '${entry.reason != null && entry.reason!.isNotEmpty ? '\n${entry.reason}' : ''}',
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: Text(
                      diff >= 0 ? '+$diff' : '$diff',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: diff >= 0
                            ? AppSemanticColors.resolve(
                                AppSemanticColors.success,
                                brightness,
                              )
                            : cs.error,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
