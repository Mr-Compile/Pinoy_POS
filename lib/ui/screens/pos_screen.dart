import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/ui/screens/gcash_payment_screen.dart';
import 'package:pinoy_pos/ui/screens/payment_success_screen.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;

  // Search + filter state
  final _searchController = TextEditingController();
  String _searchQuery = '';
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

    // Search filter (case-insensitive name match)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) => p.name.toLowerCase().contains(query)).toList();
    }

    return result;
  }

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
      _searchQuery = '';
    });
    _searchController.clear();
  }

  // ── Cart operations ────────────────────────────────────────────────

  void _addToCart(Product product) {
    ref.read(cartProvider.notifier).addProduct(product).then((error) {
      if (error != null && mounted) {
        AppDialogService.error(context,
            title: 'Unable to add', message: error);
      }
    });
  }

  // ── Checkout ───────────────────────────────────────────────────────

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      AppDialogService.error(context,
          title: 'Empty Cart', message: 'Add products to the cart before checkout.');
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('create_sales')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final total = cart.total;
    final result = await showDialog<_PaymentResult>(
      context: context,
      builder: (context) => _PaymentDialog(total: total),
    );

    if (result == null || !mounted) return;

    // GCash requires a dedicated flow (customer, reference, proof, review).
    if (result.paymentMethod == 'GCash') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GcashPaymentScreen(total: total),
        ),
      );
      return;
    }

    ref.read(cartProvider.notifier).setProcessing(true);

    try {
      final saleItems = ref.read(cartProvider.notifier).toSaleItems();
      final success = await ref.read(salesServiceProvider).createSale(
            items: saleItems,
            totalAmount: total,
            cashReceived: result.cashReceived,
            notes: result.notes,
            paymentMethod: result.paymentMethod,
            referenceNumber: result.referenceNumber,
            customerName: result.customerName,
          );

      if (mounted) {
        if (success) {
          // Cart is only cleared after the sale has been persisted.
          ref.read(cartProvider.notifier).clear();
          ref.read(cartProvider.notifier).setProcessing(false);

          final sales = await ref.read(salesServiceProvider).getSales();
          final sale = sales.isNotEmpty ? sales.first : null;

          if (!mounted) return;

          if (sale != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentSuccessScreen(sale: sale),
              ),
            );
          } else {
            await AppDialogService.success(
              context,
              title: 'Sale Completed',
              message: 'Transaction completed successfully.',
            );
          }

          await _loadProducts();
        } else {
          ref.read(cartProvider.notifier).setProcessing(false);
          AppDialogService.error(context,
              title: 'Transaction Failed',
              message: 'Failed to complete the sale. Please try again.');
        }
      }
    } on PaymentValidationException catch (e) {
      if (mounted) {
        ref.read(cartProvider.notifier).setProcessing(false);
        AppDialogService.error(context,
            title: 'Invalid Payment',
            message: e.message,
            details: e.details);
      }
    } catch (e) {
      if (mounted) {
        ref.read(cartProvider.notifier).setProcessing(false);
        AppDialogService.error(context,
            title: 'Transaction Failed',
            message: 'An error occurred while processing the sale.');
      }
    }
  }

  Future<void> _loadProducts() async {
    final productService = ref.read(productServiceProvider);
    final products = await productService.getActiveProducts();
    if (mounted) {
      setState(() {
        _products = products;
      });
      // Keep cart items in sync with the latest product data (stock changes).
      ref.read(cartProvider.notifier).refreshProducts(products);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canSell = authNotifier.hasPermission('create_sales');
    final layout = layoutClassFor(MediaQuery.of(context).size.width);
    final isTablet = layout.isAtLeastMedium;

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'POS'),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppHeader(title: 'POS'),
      body: _products.isEmpty
          ? _buildNoProductsState(canSell)
          : isTablet
              ? _buildTabletLayout(canSell)
              : _buildMobileLayout(canSell),
    );
  }

  // ── No products state ──────────────────────────────────────────────

  Widget _buildNoProductsState(bool canSell) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canManageProducts = authNotifier.hasPermission('edit_products');
    return EmptyState(
      icon: Icons.point_of_sale,
      title: 'No Products Available',
      message: canManageProducts
          ? 'Add active products before starting a transaction.'
          : 'Please ask an administrator to add products.',
      action: canManageProducts
          ? AppButton.filled(
              icon: Icons.inventory_2,
              label: 'Go to Products',
              onPressed: () {
                // Navigate to products tab — the AppShell handles routing.
              },
            )
          : null,
    );
  }

  // ── Search + filter bar ────────────────────────────────────────────

  Widget _buildSearchAndFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
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
          // Category chips
          if (_categories.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryChip(null, 'All'),
                  ..._categories.map((c) => _buildCategoryChip(c.id, c.name)),
                ],
              ),
            ),
        ],
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

  // ── Product card ───────────────────────────────────────────────────

  Widget _buildProductCard(Product product, {bool isTablet = false}) {
    final isOutOfStock = product.stock <= 0;
    final isLowStock = !isOutOfStock && product.isLowStock;
    final cs = Theme.of(context).colorScheme;

    final String stockLabel;
    final Color stockColor;
    final IconData? stockIcon;
    if (isOutOfStock) {
      stockLabel = 'Out of stock';
      stockColor = cs.error;
      stockIcon = Icons.error_outline;
    } else if (isLowStock) {
      stockLabel = 'Low stock: ${product.stock}';
      stockColor = AppSemanticColors.resolve(
        AppSemanticColors.warning,
        Theme.of(context).brightness,
      );
      stockIcon = Icons.warning_amber;
    } else {
      stockLabel = '${product.stock} available';
      stockColor = cs.onSurfaceVariant;
      stockIcon = null;
    }

    return AppCard(
      onTap: isOutOfStock ? null : () => _addToCart(product),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Product image
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AppImage(
                    imagePath: product.imageUrl,
                    placeholderIcon: Icons.inventory_2,
                    placeholderIconSize: isTablet ? 40 : 32,
                    fit: BoxFit.cover,
                  ),
                ),
                if (isOutOfStock)
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Center(
                      child: Text(
                        'Out of Stock',
                        style: AppTypography.titleSmallBold(context)
                            .copyWith(color: cs.error),
                      ),
                    ),
                  ),
                _ProductQuantityBadge(productId: product.id!),
              ],
            ),
          ),
          // Product info
          Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.titleSmall(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  CurrencyUtils.format(product.price),
                  style: AppTypography.titleMediumBold(context)
                      .copyWith(color: cs.primary),
                ),
                const SizedBox(height: Spacing.xs),
                AppStatusChip(
                  label: stockLabel,
                  color: stockColor,
                  icon: stockIcon,
                  filled: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Product grid ───────────────────────────────────────────────────

  Widget _buildProductGrid(List<Product> products, {required bool isTablet}) {
    if (products.isEmpty) {
      return _buildEmptySearchState();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    // Determine cross-axis count based on available width.
    // Mobile: 2 columns. Tablet: 3-5 depending on width.
    int crossAxisCount;
    double childAspectRatio;
    if (isTablet) {
      if (screenWidth >= 1200) {
        crossAxisCount = 5;
      } else if (screenWidth >= 900) {
        crossAxisCount = 4;
      } else {
        crossAxisCount = 3;
      }
      childAspectRatio = 0.85;
    } else {
      // Mobile
      crossAxisCount = 2;
      childAspectRatio = 0.78;
    }

    return GridView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: Spacing.md,
        mainAxisSpacing: Spacing.md,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) => _buildProductCard(products[index], isTablet: isTablet),
    );
  }

  Widget _buildEmptySearchState() {
    final hasFilters = _searchQuery.isNotEmpty || _selectedCategoryId != null;
    return Center(
      child: EmptyState(
        icon: Icons.search_off,
        title: hasFilters ? 'No Products Found' : 'No Products in This Category',
        message: hasFilters
            ? _searchQuery.isNotEmpty
                ? "No products match '$_searchQuery'."
                : 'No products in this category.'
            : 'No products available in this category.',
        action: hasFilters
            ? AppButton.text(
                icon: Icons.filter_alt_off,
                label: 'Clear Filters',
                onPressed: _clearFilters,
                size: AppButtonSize.small,
              )
            : null,
      ),
    );
  }

  // ── Cart summary + checkout ────────────────────────────────────────

  Widget _buildCheckoutPanel(bool canSell, {bool isTablet = false}) {
    // The checkout panel watches the cart provider so it rebuilds
    // immediately, even when displayed inside a modal bottom sheet.
    return _CheckoutPanel(
      canSell: canSell,
      onCheckout: _checkout,
    );
  }

  // ── Mobile layout ──────────────────────────────────────────────────

  Widget _buildMobileLayout(bool canSell) {
    return Stack(
      children: [
        Column(
          children: [
            _buildSearchAndFilters(context),
            Expanded(
              child: _buildProductGrid(_filteredProducts, isTablet: false),
            ),
          ],
        ),
        // Floating cart button
        _FloatingCartButton(onOpenCart: _showMobileCartSheet),
      ],
    );
  }

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CheckoutPanel(
          canSell: ref.read(authStateProvider.notifier).hasPermission('create_sales'),
          onCheckout: () {
            Navigator.of(context).pop();
            _checkout();
          },
        ),
      ),
    );
  }

  // ── Tablet layout ──────────────────────────────────────────────────

  Widget _buildTabletLayout(bool canSell) {
    return Row(
      children: [
        // Left: product catalog
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildSearchAndFilters(context),
              Expanded(
                child: _buildProductGrid(_filteredProducts, isTablet: true),
              ),
            ],
          ),
        ),
        // Right: cart + checkout
        Container(
          width: 360,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          child: _buildCheckoutPanel(canSell, isTablet: true),
        ),
      ],
    );
  }
}

// ── Quantity badge on product card ───────────────────────────────────

class _ProductQuantityBadge extends ConsumerWidget {
  final int productId;

  const _ProductQuantityBadge({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(
      cartProvider.select((cart) => cart.quantityFor(productId) ?? 0),
    );
    if (quantity <= 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$quantity',
          style: AppTypography.labelMedium(context).copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Floating cart button (mobile) ───────────────────────────────────

class _FloatingCartButton extends ConsumerWidget {
  final VoidCallback onOpenCart;

  const _FloatingCartButton({required this.onOpenCart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: Spacing.lg,
      right: Spacing.lg,
      child: FloatingActionButton.extended(
        icon: const Icon(Icons.shopping_cart),
        label: Text('${cart.itemCount} items · ${CurrencyUtils.format(cart.total)}'),
        onPressed: onOpenCart,
      ),
    );
  }
}

// ── Checkout panel ───────────────────────────────────────────────────

class _CheckoutPanel extends ConsumerWidget {
  final bool canSell;
  final VoidCallback onCheckout;

  const _CheckoutPanel({
    required this.canSell,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Cart header
        Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cart', style: AppTypography.titleLargeBold(context)),
              if (cart.isNotEmpty)
                AppButton.text(
                  icon: Icons.delete_sweep,
                  label: 'Clear',
                  size: AppButtonSize.small,
                  onPressed: () => _confirmClear(context, ref),
                ),
            ],
          ),
        ),
        // Cart items
        Expanded(
          child: cart.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Your cart is empty',
                  message: 'Select a product to start a transaction.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) =>
                      _CartItemRow(item: cart.items[index]),
                ),
        ),
        // Totals + checkout
        if (cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 1),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal', style: AppTypography.bodyLarge(context)),
                      Text(
                        CurrencyUtils.format(cart.subtotal),
                        style: AppTypography.bodyLarge(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTypography.titleLargeBold(context)),
                      Text(
                        CurrencyUtils.format(cart.total),
                        style: AppTypography.headlineSmallBold(context).copyWith(
                              color: cs.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  AppButton.filled(
                    isLoading: cart.isProcessing,
                    onPressed: canSell ? onCheckout : null,
                    label: 'Complete Sale',
                    icon: Icons.point_of_sale,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: 'all cart items',
    );
    if (confirmed == true) {
      ref.read(cartProvider.notifier).clear();
    }
  }
}

// ── Cart item row ────────────────────────────────────────────────────

class _CartItemRow extends ConsumerWidget {
  final CartItem item;

  const _CartItemRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = item.product;
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      variant: AppCardVariant.filled,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Name + price/qty
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.bodyLarge(context)
                      .copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${CurrencyUtils.format(product.price)} × ${item.quantity}',
                  style: AppTypography.bodySmall(context)
                      .copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Quantity controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.remove,
                onPressed: () =>
                  ref.read(cartProvider.notifier).decrement(product.id!),
                tooltip: 'Decrease quantity',
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${item.quantity}',
                  style: AppTypography.titleMedium(context),
                  textAlign: TextAlign.center,
                ),
              ),
              AppIconButton(
                icon: Icons.add,
                onPressed: () =>
                  ref.read(cartProvider.notifier).increment(product.id!),
                tooltip: 'Increase quantity',
              ),
            ],
          ),
          const SizedBox(width: Spacing.sm),
          // Subtotal
          SizedBox(
            width: 72,
            child: Text(
              CurrencyUtils.format(item.lineTotal),
              style: AppTypography.titleSmallBold(context),
              textAlign: TextAlign.right,
            ),
          ),
          // Remove
          AppIconButton(
            icon: Icons.delete_outline,
            onPressed: () =>
              ref.read(cartProvider.notifier).remove(product.id!),
            tooltip: 'Remove item',
            color: cs.error,
          ),
        ],
      ),
    );
  }
}

// ── Payment dialog ────────────────────────────────────────────────────

class _PaymentResult {
  final double cashReceived;
  final String paymentMethod;
  final String? notes;
  final String? referenceNumber;
  final String? customerName;

  _PaymentResult({
    required this.cashReceived,
    this.paymentMethod = 'Cash',
    this.notes,
    this.referenceNumber,
    this.customerName,
  });
}

class _PaymentDialog extends ConsumerStatefulWidget {
  final double total;

  const _PaymentDialog({required this.total});

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();
  final _referenceController = TextEditingController();
  final _customerNameController = TextEditingController();

  String _paymentMethod = 'Cash';

  @override
  void initState() {
    super.initState();
    // Always refresh payment settings when the tender dialog opens so the
    // staff sees the latest GCash QR, enable state, and rules.
    ref.invalidate(paymentSettingsProvider);
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }

  double _parseCash() {
    return double.tryParse(_cashController.text.trim()) ?? 0.0;
  }

  List<String> _availableMethods(bool gcashEnabled) {
    if (gcashEnabled) {
      return const ['Cash', 'GCash', 'Card', 'Other'];
    }
    return const ['Cash', 'Card', 'Other'];
  }

  @override
  Widget build(BuildContext context) {
    final paymentSettingsAsync = ref.watch(paymentSettingsProvider);

    return paymentSettingsAsync.when(
      loading: () => AppDialog(
        type: AppDialogType.info,
        title: 'Payment',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
        child: SizedBox(
          height: 120,
          child: Center(
            child: CircularProgressIndicator(
              color: AppSemanticColors.resolve(
                AppSemanticColors.info,
                Theme.of(context).brightness,
              ),
            ),
          ),
        ),
      ),
      error: (error, stackTrace) => AppDialog(
        type: AppDialogType.error,
        title: 'Payment',
        message: 'Failed to load payment settings: $error',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
      data: (settings) => _buildContent(context, settings),
    );
  }

  Widget _buildContent(BuildContext context, PaymentSettings settings) {
    final cs = Theme.of(context).colorScheme;
    final methods = _availableMethods(settings.gcashEnabled);
    final currentMethod =
        methods.contains(_paymentMethod) ? _paymentMethod : 'Cash';
    final cash = currentMethod == 'Cash' ? _parseCash() : widget.total;
    final change = cash - widget.total;

    if (currentMethod != _paymentMethod) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _paymentMethod = currentMethod);
      });
    }

    final primaryLabel =
        currentMethod == 'GCash' ? 'Continue with GCash' : 'Complete Sale';

    void completePayment(BuildContext context) {
      if (currentMethod == 'GCash') {
        Navigator.of(context, rootNavigator: true).pop(
          _PaymentResult(
            cashReceived: 0.0,
            paymentMethod: 'GCash',
          ),
        );
        return;
      }

      if (!_formKey.currentState!.validate()) return;
      Navigator.of(context, rootNavigator: true).pop(
        _PaymentResult(
          cashReceived: currentMethod == 'Cash'
              ? _parseCash()
              : widget.total,
          paymentMethod: currentMethod,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          referenceNumber:
              (currentMethod == 'Card' || currentMethod == 'Other') &&
                      _referenceController.text.trim().isNotEmpty
                  ? _referenceController.text.trim()
                  : null,
          customerName:
              (currentMethod == 'Card' || currentMethod == 'Other') &&
                      _customerNameController.text.trim().isNotEmpty
                  ? _customerNameController.text.trim()
                  : null,
        ),
      );
    }

    return AppDialog(
      type: AppDialogType.info,
      title: 'Payment',
      showIcon: false,
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: (context) =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
        AppDialogAction(
          label: primaryLabel,
          isPrimary: true,
          onPressed: (context) => completePayment(context),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total display
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Due',
                        style: TextStyle(color: cs.onPrimaryContainer)),
                    Text(
                      CurrencyUtils.format(widget.total),
                      style: AppTypography.titleLargeBold(context)
                          .copyWith(color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
              // Payment method
              DropdownButtonFormField<String>(
                key: const ValueKey('pos_payment_method'),
                initialValue: currentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  prefixIcon: Icon(Icons.payment),
                  border: OutlineInputBorder(),
                ),
                items: methods
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: Spacing.lg),
              // Cash received (Cash only)
              if (currentMethod == 'Cash') ...[
                TextFormField(
                  controller: _cashController,
                  decoration: InputDecoration(
                    labelText: 'Cash Received',
                    prefixText: CurrencyUtils.symbol(),
                    prefixIcon: const Icon(Icons.payments),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final cash = double.tryParse(value?.trim() ?? '');
                    if (cash == null) {
                      return 'Enter a valid amount';
                    }
                    if (cash < widget.total) {
                      return 'Insufficient cash received';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Spacing.md),
                // Change display
                if (cash >= widget.total)
                  Container(
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Change',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        Text(
                          CurrencyUtils.format(change),
                          style: AppTypography.titleLargeBold(context)
                              .copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Spacing.md),
                // Quick cash buttons
                Wrap(
                  spacing: Spacing.sm,
                  children: [
                    _buildQuickCashButton(widget.total),
                    _buildQuickCashButton(_roundUp(widget.total, 50)),
                    _buildQuickCashButton(_roundUp(widget.total, 100)),
                    _buildQuickCashButton(_roundUp(widget.total, 500)),
                  ],
                ),
                const SizedBox(height: Spacing.md),
              ],
              // Reference and customer (Card/Other only)
              if (currentMethod == 'Card' || currentMethod == 'Other') ...[
                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number (optional)',
                    prefixIcon: Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  controller: _customerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name (optional)',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
              ],
              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      );
  }

  double _roundUp(double value, double to) {
    return (value / to).ceil() * to;
  }

  Widget _buildQuickCashButton(double amount) {
    return ActionChip(
      label: Text(CurrencyUtils.formatWhole(amount)),
      onPressed: () {
        _cashController.text = amount.toStringAsFixed(2);
        setState(() {});
      },
    );
  }
}
