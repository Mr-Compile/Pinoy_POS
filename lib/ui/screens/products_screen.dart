import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/dialogs/category_dialog.dart';
import 'package:pinoy_pos/ui/dialogs/product_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
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
        children: [
          if (_stockSummary.total > 0) _buildStatsStrip(),
          CrudToolbar(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            search: AppSearchField(
              controller: _searchController,
              hint: 'Search products',
              onChanged: _onSearchChanged,
            ),
            controls: [
              SizedBox(
                width: 220,
                child: AppDropdownField<int?>(
                  initialValue: _selectedCategoryId,
                  label: 'Category',
                  isDense: true,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All'),
                    ),
                    ..._categories.map((category) => DropdownMenuItem<int?>(
                          value: category.id,
                          child: Text(category.name),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedCategoryId = value;
                    });
                  },
                ),
              ),
            ],
            primaryAction: toolbarAction,
          ),
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
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + bottomClearance,
      ),
      itemCount: _filteredProducts.length,
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
        return _buildProductItem(product, category, canEdit, canDelete);
      },
    );
  }

  Widget _buildProductItem(
    Product product,
    Category category,
    bool canEdit,
    bool canDelete,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isOutOfStock = product.stock <= 0;
    final isLowStock = !isOutOfStock && product.isLowStock;

    final String? statusLabel;
    final Color? statusColor;
    final IconData? statusIcon;
    if (isOutOfStock) {
      statusLabel = 'Out of stock';
      statusColor = cs.error;
      statusIcon = Icons.error_outline;
    } else if (isLowStock) {
      statusLabel = 'Low stock';
      statusColor = AppSemanticColors.resolve(
        AppSemanticColors.warning,
        Theme.of(context).brightness,
      );
      statusIcon = Icons.warning_amber;
    } else {
      statusLabel = null;
      statusColor = null;
      statusIcon = null;
    }

    final actions = <AppListAction>[
      if (canEdit)
        AppListAction(
          icon: Icons.edit,
          onPressed: () => _showProductDialog(product: product),
          tooltip: 'Edit product',
        ),
      if (canDelete)
        AppListAction(
          icon: Icons.delete,
          onPressed: () => _deleteProduct(product),
          tooltip: 'Delete product',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppListItem(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: AppImage(
            imagePath: product.imageUrl,
            borderRadius: 8,
            placeholderIcon: Icons.inventory_2,
            placeholderIconSize: 28,
            fit: BoxFit.cover,
          ),
        ),
        title: product.name,
        subtitle: 'Stock: ${product.stock}',
        trailing: Text(
          CurrencyUtils.format(product.price),
          style: AppTypography.titleMediumBold(context)
              .copyWith(color: cs.primary),
        ),
        chips: [
          AppStatusChip(
            label: category.name,
            color: cs.primary,
            icon: Icons.label_outline,
            filled: false,
          ),
        ],
        statusLabel: statusLabel,
        statusColor: statusColor,
        statusIcon: statusIcon,
        actions: actions.isNotEmpty ? actions : null,
        onTap: canEdit ? () => _showProductDialog(product: product) : null,
      ),
    );
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
