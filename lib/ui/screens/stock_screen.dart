import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
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

    final result = await showDialog<_StockOperationResult>(
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
          _loadData();
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

    final result = await showDialog<_StockOperationResult>(
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
          _loadData();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Management')),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Management')),
      floatingActionButton: canAddStock && _products.isNotEmpty
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Stock'),
              onPressed: _isProcessing ? null : () => _showProductPickerDialog(),
            )
          : null,
      body: _products.isEmpty
          ? _buildNoProductsState()
          : Column(
              children: [
                // Summary cards
                _buildSummaryCards(),
                // Search + filters
                _buildSearchAndFilters(),
                // Stock list
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? _buildEmptyFilterState()
                      : isTablet
                          ? _buildTabletStockList(canAddStock, canAdjustStock, canViewStock)
                          : _buildMobileStockList(canAddStock, canAdjustStock, canViewStock),
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

  // ── Summary cards ──────────────────────────────────────────────────

  Widget _buildSummaryCards() {
    final totalProducts = _products.length;
    final lowStockCount = _products.where(_isLowStock).length;
    final outOfStockCount = _products.where(_isOutOfStock).length;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              'Total',
              '$totalProducts',
              Icons.inventory_2,
              cs.primary,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: _buildSummaryCard(
              'Low Stock',
              '$lowStockCount',
              Icons.warning_amber,
              cs.secondary,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: _buildSummaryCard(
              'Out of Stock',
              '$outOfStockCount',
              Icons.error_outline,
              cs.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return AppCard(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: Spacing.xs),
          Text(
            value,
            style: AppTypography.titleLargeBold(context),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Search + filters ───────────────────────────────────────────────

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
      child: Column(
        children: [
          // Search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search products...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                      tooltip: 'Clear search',
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: Spacing.sm),
          // Stock status filter chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStockFilterChip(StockFilter.all, 'All'),
                _buildStockFilterChip(StockFilter.lowStock, 'Low Stock'),
                _buildStockFilterChip(StockFilter.outOfStock, 'Out of Stock'),
              ],
            ),
          ),
          // Category chips
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryChip(null, 'All Categories'),
                  ..._categories.map((c) => _buildCategoryChip(c.id, c.name)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStockFilterChip(StockFilter filter, String label) {
    final isSelected = _stockFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _stockFilter = filter;
          });
        },
      ),
    );
  }

  Widget _buildCategoryChip(int? categoryId, String label) {
    final isSelected = _selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedCategoryId = categoryId;
          });
        },
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

  // ── Stock status badge ─────────────────────────────────────────────

  Widget _buildStockStatusBadge(Product product) {
    final cs = Theme.of(context).colorScheme;
    if (_isOutOfStock(product)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
            const SizedBox(width: 4),
            Text(
              'Out of Stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }
    if (_isLowStock(product)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 14, color: cs.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              'Low Stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSecondaryContainer,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: cs.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            'Normal',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile stock list ──────────────────────────────────────────────

  Widget _buildMobileStockList(bool canAddStock, bool canAdjustStock, bool canViewStock) {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product header with image
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: AppImage(
                        imagePath: product.imageUrl,
                        placeholderIcon: Icons.inventory_2,
                        placeholderIconSize: 24,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _categoryName(product.categoryId),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              // Stock info
              Row(
                children: [
                  Expanded(
                    child: _buildStockInfoColumn('Stock', '${product.stock}'),
                  ),
                  Expanded(
                    child: _buildStockInfoColumn('Minimum', '${product.minStock}'),
                  ),
                  _buildStockStatusBadge(product),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              // Actions
              Wrap(
                spacing: Spacing.sm,
                children: [
                  if (canAddStock)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Stock'),
                      onPressed: _isProcessing ? null : () => _showAddStockDialog(product),
                    ),
                  if (canAdjustStock)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Adjust'),
                      onPressed: _isProcessing ? null : () => _showAdjustStockDialog(product),
                    ),
                  if (canViewStock)
                    TextButton.icon(
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('History'),
                      onPressed: () => _showStockHistory(product),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: AppTypography.titleMediumBold(context),
        ),
      ],
    );
  }

  // ── Tablet stock list ──────────────────────────────────────────────

  Widget _buildTabletStockList(bool canAddStock, bool canAdjustStock, bool canViewStock) {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: Spacing.sm),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: AppImage(
                    imagePath: product.imageUrl,
                    placeholderIcon: Icons.inventory_2,
                    placeholderIconSize: 20,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              // Product name + category
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: AppTypography.titleMediumBold(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _categoryName(product.categoryId),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              // Stock
              SizedBox(
                width: 80,
                child: Text(
                  '${product.stock}',
                  style: AppTypography.titleMediumBold(context),
                  textAlign: TextAlign.center,
                ),
              ),
              // Minimum
              SizedBox(
                width: 80,
                child: Text(
                  '${product.minStock}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              // Status badge
              SizedBox(
                width: 110,
                child: _buildStockStatusBadge(product),
              ),
              // Actions
              SizedBox(
                width: 180,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAddStock)
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add Stock',
                        onPressed: _isProcessing ? null : () => _showAddStockDialog(product),
                      ),
                    if (canAdjustStock)
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Adjust Stock',
                        onPressed: _isProcessing ? null : () => _showAdjustStockDialog(product),
                      ),
                    if (canViewStock)
                      IconButton(
                        icon: const Icon(Icons.history),
                        tooltip: 'Stock History',
                        onPressed: () => _showStockHistory(product),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Product picker dialog (for FAB Add Stock) ──────────────────────

  Future<void> _showProductPickerDialog() async {
    final selectedProduct = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
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
                    title: Text(product.name),
                    subtitle: Text(
                      'Stock: ${product.stock} · ${_categoryName(product.categoryId)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isOutOfStock(product)
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: _buildStockStatusBadge(product),
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

class _StockOperationDialog extends StatefulWidget {
  final Product product;
  final String category;
  final bool isAdjust;

  const _StockOperationDialog({
    required this.product,
    required this.category,
    required this.isAdjust,
  });

  @override
  State<_StockOperationDialog> createState() => _StockOperationDialogState();
}

class _StockOperationDialogState extends State<_StockOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  int _parseInt() {
    return int.tryParse(_quantityController.text.trim()) ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.isAdjust ? 'Adjust Stock' : 'Add Stock';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product info
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: AppImage(
                          imagePath: widget.product.imageUrl,
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
                            widget.product.name,
                            style: AppTypography.titleMediumBold(context),
                          ),
                          Text(
                            widget.category,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              // Current stock
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current Stock', style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '${widget.product.stock}',
                    style: AppTypography.titleMediumBold(context),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              // Quantity / New stock input
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: widget.isAdjust ? 'New Stock Quantity' : 'Quantity to Add',
                  prefixIcon: const Icon(Icons.inventory),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
                validator: (value) {
                  final qty = int.tryParse(value?.trim() ?? '');
                  if (qty == null) {
                    return 'Enter a valid number';
                  }
                  if (qty <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  if (widget.isAdjust && qty > 999999) {
                    return 'Value too large';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Spacing.md),
              // Preview new stock
              if (_parseInt() > 0)
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.isAdjust ? 'New Stock' : 'Stock After Adding',
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      Text(
                        widget.isAdjust
                            ? '${_parseInt()}'
                            : '${widget.product.stock + _parseInt()}',
                        style: AppTypography.titleLargeBold(context)
                            .copyWith(color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.md),
              // Reason / Remarks
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        LoadingButton(
          isLoading: false,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final qty = _parseInt();
            Navigator.pop(
              context,
              _StockOperationResult(
                quantity: widget.isAdjust ? qty - widget.product.stock : qty,
                newStock: widget.isAdjust ? qty : widget.product.stock + qty,
                reason: _reasonController.text.trim().isEmpty
                    ? null
                    : _reasonController.text.trim(),
              ),
            );
          },
          label: widget.isAdjust ? 'Continue' : 'Add Stock',
        ),
      ],
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

  Color _operationColor(StockOperationType type, ColorScheme cs) {
    switch (type) {
      case StockOperationType.add:
        return cs.tertiary;
      case StockOperationType.adjust:
        return cs.secondary;
      case StockOperationType.sale:
        return cs.primary;
      case StockOperationType.return_:
        return cs.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Stock History'),
      content: SizedBox(
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
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
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final opColor = _operationColor(entry.operation, cs);
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
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      trailing: Text(
                        diff >= 0 ? '+$diff' : '$diff',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: diff >= 0 ? cs.tertiary : cs.error,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
