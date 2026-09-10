import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';

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
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _stockFilter = StockFilter.all;
      _searchQuery = '';
    });
    _searchController.clear();
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
      appBar: const AppHeader(
        title: 'Stock',
        showBackButton: true,
      ),
      floatingActionButton: createFab,
      body: _products.isEmpty
          ? _buildNoProductsState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRoleChipBar(),
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

  // ── Role / permission bar ──────────────────────────────────────────

  Widget _buildRoleChipBar() {
    final cs = Theme.of(context).colorScheme;
    final user = ref.read(authStateProvider).user;
    final isOwner = user?.role == UserRole.owner;
    final roleColor = isOwner
        ? AppSemanticColors.resolve(AppSemanticColors.info, Theme.of(context).brightness)
        : AppSemanticColors.resolve(AppSemanticColors.success, Theme.of(context).brightness);

    final label = isOwner ? 'Owner' : 'Staff';
    final permText = isOwner
        ? 'view/add/adjust stock'
        : 'view/add stock only';

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

  // ── Toolbar: search + category filter + stock chips ────────────────

  Widget _buildToolbar(Widget? primaryAction) {
    return CrudToolbar(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      search: AppSearchField(
        controller: _searchController,
        hint: 'Search products...',
        onChanged: _onSearchChanged,
        onClear: _clearSearch,
      ),
      controls: [
        _buildCategoryFilter(),
        _buildStockFilterChip(StockFilter.all, 'All'),
        _buildStockFilterChip(StockFilter.lowStock, 'Low'),
        _buildStockFilterChip(StockFilter.outOfStock, 'Out'),
      ],
      primaryAction: primaryAction,
    );
  }

  Widget _buildCategoryFilter() {
    final cs = Theme.of(context).colorScheme;
    final selectedLabel =
        _selectedCategoryId == null ? 'Filter' : _categoryName(_selectedCategoryId);

    return PopupMenuButton<int?>(
      initialValue: _selectedCategoryId,
      onSelected: (value) => setState(() => _selectedCategoryId = value),
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
    final isSelected = _stockFilter == filter;
    return FilterChip(
      label: Text(label),
      showCheckmark: false,
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _stockFilter = filter;
        });
      },
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
            '${_filteredProducts.length} items',
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
              itemCount: _filteredProducts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
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

    return Padding(
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
    final selectedProduct = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Product', style: AppTypography.titleLargeBold(context)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  final stockColor = _stockColor(product);
                  return ListTile(
                    leading: _buildStockThumb(product),
                    title: Text(product.name),
                    subtitle: Text(
                      'Stock: ${product.stock} · ${_categoryName(product.categoryId)}',
                      style: AppTypography.bodySmall(context).copyWith(
                        color: _isOutOfStock(product)
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: _buildStockPill('${product.stock} left', stockColor),
                    onTap: () => Navigator.pop(context, product),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

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

    return AppDialogForm<_StockOperationResult?>(
      type: isAdjust ? AppDialogType.edit : AppDialogType.add,
      title: title,
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
                prefixIcon: Icons.note,
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
