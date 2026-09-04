import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/dialogs/product_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final productService = ref.read(productServiceProvider);
    final categoryService = ref.read(categoryServiceProvider);
    final categories = await categoryService.getActiveCategories();

    // When a search query is active, run the search at the DAO level;
    // otherwise load all active products.
    final products = _searchQuery.isEmpty
        ? await productService.getActiveProducts()
        : await productService.searchProducts(_searchQuery);

    if (mounted) {
      setState(() {
        _products = products;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  /// Products after applying the optional category filter. The category
  /// filter is applied to the already-authorized product list, so it never
  /// bypasses the service-layer read permission.
  List<Product> get _filteredProducts {
    if (_selectedCategoryId == null) return _products;
    return _products.where((p) => p.categoryId == _selectedCategoryId).toList();
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
          _loadData();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (_isLoading) {
      return const Scaffold(
        appBar: AppHeader(title: 'Products'),
        body: LoadingState(),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Products'),
      floatingActionButton: canEdit && !isTablet
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
              onPressed: () => _showProductDialog(),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    hint: 'Search products',
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                if (canEdit && isTablet) ...[
                  const SizedBox(width: 12),
                  AppButton.filled(
                    size: AppButtonSize.small,
                    icon: Icons.add,
                    label: 'Add Product',
                    onPressed: _showProductDialog,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _filteredProducts.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2,
                    title: _products.isEmpty ? 'No Products Yet' : 'No Products Found',
                    message: _products.isEmpty
                        ? 'Add your first product to start building your inventory.'
                        : 'No products match your search.',
                    // No create button here — the FAB (mobile) / AppBar
                    // action (tablet) is the single primary create action.
                  )
                : _buildProductList(canEdit, canDelete),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(bool canEdit, bool canDelete) {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
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
        subtitle: '${category.name} • Stock: ${product.stock}',
        trailing: Text(
          CurrencyUtils.format(product.price),
          style: AppTypography.titleMediumBold(context)
              .copyWith(color: cs.primary),
        ),
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
      await _loadData();
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
}
