import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/route_guard.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/cart_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/payment_settings_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/ui/screens/gcash_payment_screen.dart';
import 'package:pinoy_pos/ui/screens/payment_success_screen.dart';
import 'package:pinoy_pos/ui/screens/products_screen.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  String? _loadError;

  // This screen is kept alive inside the app shell's PageView, so
  // initState only runs once. Listening to catalogRevisionProvider reloads
  // the catalog whenever products, categories, or stock change elsewhere
  // in the app (product management, stock, trash restore, sales, backup
  // restore).
  ProviderSubscription<int>? _catalogSubscription;

  // Search + filter state
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryId;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _catalogSubscription = ref.listenManual<int>(
      catalogRevisionProvider,
      (previous, next) => _refreshCatalog(),
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
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    await _refreshCatalog();
  }

  /// Fetches active products and categories through the service layer and
  /// applies them to the screen. Safe to call while the tab is kept alive
  /// but not visible: it refreshes silently without flashing the loading
  /// spinner, and keeps previously loaded data if the refresh fails.
  Future<void> _refreshCatalog() async {
    try {
      final productService = ref.read(productServiceProvider);
      final categoryService = ref.read(categoryServiceProvider);

      final categories = await categoryService.getActiveCategories();
      final products = await productService.getActiveProducts();

      debugPrint(
        'POSScreen: loaded ${products.length} active products, '
        '${categories.length} active categories',
      );

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _products = products;
        _isLoading = false;
        _loadError = null;
      });
      // Keep cart items in sync with the latest product data (stock changes).
      ref.read(cartProvider.notifier).refreshProducts(products);
    } catch (e, st) {
      debugPrint('POSScreen catalog load error: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Only surface the error state when there is no data to show;
          // a failed background refresh keeps the previous catalog.
          if (_products.isEmpty) {
            _loadError = 'Unable to load products. Please try again.';
          }
        });
      }
    }
  }

  // ── Filtered products ──────────────────────────────────────────────

  List<Product> get _filteredProducts {
    var result = _products;

    // Category filter
    if (_selectedCategoryId != null) {
      result = result
          .where((p) => p.categoryId == _selectedCategoryId)
          .toList();
    }

    // Search filter (case-insensitive name match)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
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
        AppDialogService.error(context, title: 'Unable to add', message: error);
      }
    });
  }

  // ── Checkout ───────────────────────────────────────────────────────

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      AppDialogService.error(
        context,
        title: 'Empty Cart',
        message: 'Add products to the cart before checkout.',
      );
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('create_sales')) {
      AppDialogService.accessDenied(context);
      return;
    }

    // Always refresh payment settings when checkout starts so the tender
    // dialog shows the latest GCash QR, enable state, and rules.
    // Safe here: this is an event handler, not a lifecycle method.
    ref.invalidate(paymentSettingsProvider);

    final total = cart.total;
    final result = await showDialog<_PaymentResult?>(
      context: context,
      builder: (context) => _PaymentDialog(total: total),
    );

    if (result == null || !mounted) return;

    // GCash requires a dedicated flow (customer, reference, proof, review).
    if (result.paymentMethod == 'GCash') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GcashPaymentScreen(total: total)),
      );
      return;
    }

    ref.read(cartProvider.notifier).setProcessing(true);

    try {
      final saleItems = ref.read(cartProvider.notifier).toSaleItems();
      final success = await ref
          .read(salesServiceProvider)
          .createSale(
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

          // The sale decremented stock: bump the catalog revision so this
          // screen (via its listener) and every other catalog screen reload.
          bumpCatalogRevision(ref);
        } else {
          ref.read(cartProvider.notifier).setProcessing(false);
          AppDialogService.error(
            context,
            title: 'Transaction Failed',
            message: 'Failed to complete the sale. Please try again.',
          );
        }
      }
    } on PaymentValidationException catch (e) {
      if (mounted) {
        ref.read(cartProvider.notifier).setProcessing(false);
        AppDialogService.error(
          context,
          title: 'Invalid Payment',
          message: e.message,
          details: e.details,
        );
      }
    } catch (e) {
      if (mounted) {
        ref.read(cartProvider.notifier).setProcessing(false);
        AppDialogService.error(
          context,
          title: 'Transaction Failed',
          message: 'An error occurred while processing the sale.',
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  /// Minimum body width before the cart docks beside the product grid.
  /// Below this the POS uses the stacked phone layout with a sticky cart
  /// bar; at or above it the two-pane layout gives the product catalog
  /// at least ~430 px while keeping the cart within a usable 280–380 px.
  static const double _twoPaneMinWidth = 720;

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canSell = authNotifier.hasPermission('create_sales');

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(title: 'POS'),
        body: const LoadingState(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppHeader(title: 'POS'),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Unable to Load Products',
          message: _loadError,
          action: AppButton.filled(
            icon: Icons.refresh,
            label: 'Retry',
            onPressed: _loadData,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(title: 'POS'),
      body: _products.isEmpty
          ? _buildNoProductsState(canSell)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _twoPaneMinWidth;
                if (isWide) {
                  return _buildWideLayout(canSell, constraints.maxWidth);
                }
                return _buildMobileLayout(canSell);
              },
            ),
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
              onPressed: () => RouteGuard.pushIfAuthorized(
                context,
                ref,
                screen: const ProductsScreen(),
                permission: 'view_products',
                routeName: 'products',
              ),
            )
          : null,
    );
  }

  // ── Search + filter bar ────────────────────────────────────────────

  Widget _buildSearchAndFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        children: [
          // Search field
          AppSearchField(
            controller: _searchController,
            hint: 'Search products...',
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
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
        showCheckmark: false,
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
      variant: AppCardVariant.outlined,
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
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
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Out of Stock',
                        style: AppTypography.titleSmallBold(
                          context,
                        ).copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? cs.onSurface
                              : cs.error,
                          shadows: const [
                            Shadow(
                              color: Color(0x99000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
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
                  style: AppTypography.titleMediumBold(
                    context,
                  ).copyWith(color: cs.primary),
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

  Widget _buildProductGrid(List<Product> products, {required bool isWide}) {
    if (products.isEmpty) {
      return _buildEmptySearchState();
    }

    // Column count follows the grid's own width rather than the device
    // class, so phones, split panes, and desktop windows all adapt. Cards
    // keep a sensible minimum width so names, prices, and stock chips stay
    // readable instead of shrinking into clipped slivers.
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTileWidth = isWide ? 170.0 : 150.0;
        final maxColumns = isWide ? 6 : 4;
        final crossAxisCount = (constraints.maxWidth / minTileWidth)
            .floor()
            .clamp(1, maxColumns);

        return GridView.builder(
          padding: const EdgeInsets.all(Spacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: isWide ? 0.85 : 0.78,
            crossAxisSpacing: Spacing.md,
            mainAxisSpacing: Spacing.md,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) =>
              _buildProductCard(products[index], isTablet: isWide),
        );
      },
    );
  }

  Widget _buildEmptySearchState() {
    final hasFilters = _searchQuery.isNotEmpty || _selectedCategoryId != null;
    return Center(
      child: EmptyState(
        icon: Icons.search_off,
        title: hasFilters
            ? 'No Products Found'
            : 'No Products in This Category',
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

  Widget _buildCheckoutPanel(
    bool canSell, {
    ScrollController? scrollController,
  }) {
    // The checkout panel watches the cart provider so it rebuilds
    // immediately, even when displayed inside a modal bottom sheet.
    return _CheckoutPanel(
      canSell: canSell,
      onCheckout: _checkout,
      scrollController: scrollController,
    );
  }

  // ── Mobile layout ──────────────────────────────────────────────────

  /// Stacked portrait layout: search and categories on top, the product
  /// grid fills the middle, and a sticky cart bar stays pinned to the
  /// bottom so the path to checkout is always visible.
  Widget _buildMobileLayout(bool canSell) {
    return Column(
      children: [
        _buildSearchAndFilters(context),
        Expanded(child: _buildProductGrid(_filteredProducts, isWide: false)),
        _MobileCartBar(
          canSell: canSell,
          onOpenCart: _showMobileCartSheet,
          onCheckout: _checkout,
        ),
      ],
    );
  }

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CheckoutPanel(
          canSell: ref
              .read(authStateProvider.notifier)
              .hasPermission('create_sales'),
          scrollController: scrollController,
          onCheckout: () {
            Navigator.of(context).pop();
            _checkout();
          },
        ),
      ),
    );
  }

  // ── Wide layout (tablet landscape / desktop) ───────────────────────

  Widget _buildWideLayout(bool canSell, double layoutWidth) {
    // The cart column scales with the window but stays within a usable
    // range so cart rows never become too cramped or too stretched.
    // At 720 px this leaves ~430 px for the product catalog.
    final cartWidth = (layoutWidth * 0.38).clamp(280.0, 380.0);

    return Row(
      children: [
        // Left: product catalog
        Expanded(
          child: Column(
            children: [
              _buildSearchAndFilters(context),
              Expanded(
                child: _buildProductGrid(_filteredProducts, isWide: true),
              ),
            ],
          ),
        ),
        // Right: cart + checkout
        Container(
          width: cartWidth,
          color: Theme.of(context).colorScheme.surface,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          child: _buildCheckoutPanel(canSell),
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
        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        child: Text(
          '$quantity',
          style: AppTypography.labelMedium(
            context,
          ).copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Sticky cart bar (compact layout) ─────────────────────────────────

/// Pinned to the bottom of the stacked POS layout while the cart has
/// items. Tapping the summary opens the editable cart sheet; the Checkout
/// button goes straight to payment. It sits inside the layout (not an
/// overlay) so it never covers products, and SafeArea keeps it clear of
/// device navigation bars.
class _MobileCartBar extends ConsumerWidget {
  final bool canSell;
  final VoidCallback onOpenCart;
  final VoidCallback onCheckout;

  const _MobileCartBar({
    required this.canSell,
    required this.onOpenCart,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenCart,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'} · tap to review',
                          style: AppTypography.bodySmall(
                            context,
                          ).copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          CurrencyUtils.format(cart.total),
                          style: AppTypography.titleLargeBold(
                            context,
                          ).copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              AppButton.filled(
                icon: Icons.point_of_sale,
                label: 'Checkout',
                isLoading: cart.isProcessing,
                onPressed: canSell ? onCheckout : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Checkout panel ───────────────────────────────────────────────────

class _CheckoutPanel extends ConsumerWidget {
  final bool canSell;
  final VoidCallback onCheckout;

  /// When the panel lives inside a [DraggableScrollableSheet], this is the
  /// sheet's scroll controller so the cart list drives the drag gesture.
  final ScrollController? scrollController;

  const _CheckoutPanel({
    required this.canSell,
    required this.onCheckout,
    this.scrollController,
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
                  icon: Icons.clear_all,
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
                  controller: scrollController,
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
                        style: AppTypography.bodyLarge(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: AppTypography.titleLargeBold(context),
                      ),
                      Text(
                        CurrencyUtils.format(cart.total),
                        style: AppTypography.headlineSmallBold(
                          context,
                        ).copyWith(color: cs.primary),
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
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Clear Cart?',
      message: 'Clear all items from the cart?',
      confirmLabel: 'Clear Cart',
      cancelLabel: 'Cancel',
      destructive: true,
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
    final notifier = ref.read(cartProvider.notifier);

    // Two-section layout: the thumbnail, name, and remove action sit in
    // the top row; quantity controls and the line subtotal sit in the
    // bottom row. Splitting the controls onto their own row keeps every
    // element reachable on narrow phones — long product names ellipsize
    // instead of pushing the buttons off screen.
    return AppCard(
      variant: AppCardVariant.outlined,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product thumbnail. The fixed 56px box keeps every cart row
          // identically sized whether the product has an image or falls
          // back to the icon — AppImage handles missing/corrupted files.
          SizedBox(
            width: 56,
            height: 56,
            child: AppImage(
              imagePath: product.imageUrl,
              placeholderIcon: Icons.inventory_2_outlined,
              placeholderIconSize: 24,
              borderRadius: 10,
              fit: BoxFit.cover,
              cacheWidth: 128,
              semanticLabel: product.name,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: AppTypography.bodyLarge(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.highlight_remove,
                      onPressed: () => notifier.remove(product.id!),
                      tooltip: 'Remove item',
                      color: cs.error,
                    ),
                  ],
                ),
                Text(
                  '${CurrencyUtils.format(product.price)} each',
                  style: AppTypography.bodySmall(
                    context,
                  ).copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.xs),
                Row(
                  children: [
                    AppIconButton(
                      icon: Icons.remove,
                      onPressed: () => notifier.decrement(product.id!),
                      tooltip: 'Decrease quantity',
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${item.quantity}',
                        style: AppTypography.titleMedium(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.add,
                      onPressed: () => notifier.increment(product.id!),
                      tooltip: 'Increase quantity',
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        CurrencyUtils.format(item.lineTotal),
                        style: AppTypography.titleSmallBold(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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

class _PaymentDialog extends ConsumerWidget {
  final double total;

  const _PaymentDialog({required this.total});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentSettingsAsync = ref.watch(paymentSettingsProvider);

    return paymentSettingsAsync.when(
      loading: () => AppDialog(
        type: AppDialogType.loading,
        title: 'Payment',
        actions: [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
        child: Center(
          child: CircularProgressIndicator(
            color: AppSemanticColors.resolve(
              AppSemanticColors.primary,
              Theme.of(context).brightness,
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
            label: 'Close',
            onPressed: (context) =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
      data: (settings) => AppDialogForm<_PaymentResult?>(
        type: AppDialogType.payment,
        title: 'Payment',
        showClose: false,
        childBuilder: (context, state) => _buildForm(context, state, settings),
        actionsBuilder: (context, state) =>
            _buildActions(context, state, settings),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppDialogFormState<_PaymentResult?> state,
    PaymentSettings settings,
  ) {
    final cs = Theme.of(context).colorScheme;
    final methods = _availableMethods(settings.gcashEnabled);
    final currentMethod = _currentMethod(state, settings);
    final cash = _currentCash(state);
    final change = cash - total;

    return Form(
      key: state.formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total display
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                'Total Due',
                style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.9)),
              ),
                Text(
                  CurrencyUtils.format(total),
                  style: AppTypography.titleLargeBold(
                    context,
                  ).copyWith(color: cs.onPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // Payment method — large tappable tiles instead of a
          // dropdown so the choices are visible at a glance and easy
          // to hit on a phone. Two columns on compact widths, one row
          // when there is room for every method side by side.
          Text(
            'Payment Method',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.sm),
          LayoutBuilder(
            key: const ValueKey('pos_payment_method'),
            builder: (context, constraints) {
              final columns =
                  layoutClassFor(constraints.maxWidth).isAtLeastMedium
                      ? methods.length
                      : 2;
              final tileWidth =
                  (constraints.maxWidth - Spacing.sm * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final method in methods)
                    SizedBox(
                      width: tileWidth,
                      child: _PaymentMethodTile(
                        label: method,
                        icon: _paymentMethodIcon(method),
                        selected: method == currentMethod,
                        onTap: () => state.setValue<String>('method', method),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: Spacing.lg),
          // Cash received (Cash only)
          if (currentMethod == 'Cash') ...[
            AppTextFormField(
              controller: state.textController('cash', text: ''),
              label: 'Cash Received',
              hint: '0.00',
              prefixText: CurrencyUtils.symbol(),
              prefixIcon: Icons.payments,
              keyboardType: TextInputType.number,
              validator: (value) {
                final cash = double.tryParse(value?.trim() ?? '');
                if (cash == null) {
                  return 'Enter a valid amount';
                }
                if (cash < total) {
                  return 'Insufficient cash received';
                }
                return null;
              },
              onChanged: (value) {
                final parsed = double.tryParse(value.trim()) ?? 0.0;
                state.setValue<double>('cash', parsed);
              },
            ),
            const SizedBox(height: Spacing.md),
            // Change display
            if (cash >= total)
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Change',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      CurrencyUtils.format(change),
                      style: AppTypography.titleLargeBold(
                        context,
                      ).copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.md),
            // Quick cash buttons
            Wrap(
              spacing: Spacing.sm,
              children: [
                _buildQuickCashButton(state, total),
                _buildQuickCashButton(state, _roundUp(total, 50)),
                _buildQuickCashButton(state, _roundUp(total, 100)),
                _buildQuickCashButton(state, _roundUp(total, 500)),
              ],
            ),
            const SizedBox(height: Spacing.md),
          ],

          // Customer name for non-GCash methods, driven by Payment Settings.
          if (currentMethod != 'GCash' && settings.customerNameVisible) ...[
            AppTextFormField(
              controller: state.textController('customerName', text: 'GUEST'),
              label: _customerNameLabel(settings),
              hint: 'Customer name',
              prefixIcon: Icons.person,
              textCapitalization: TextCapitalization.words,
              validator: (value) => _validateCustomerName(settings, value),
            ),
            const SizedBox(height: Spacing.md),
          ],
          // Notes
          AppTextFormField(
            controller: state.textController('notes', text: ''),
            label: 'Notes (optional)',
            hint: 'e.g. Order instructions',
            prefixIcon: Icons.note,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  List<AppDialogAction> _buildActions(
    BuildContext context,
    AppDialogFormState<_PaymentResult?> state,
    PaymentSettings settings,
  ) {
    final currentMethod = _currentMethod(state, settings);
    final primaryLabel = currentMethod == 'GCash'
        ? 'Continue with GCash'
        : 'Complete Sale';

    return [
      AppDialogAction(
        label: 'Cancel',
        onPressed: (_) => state.pop(null),
      ),
      AppDialogAction(
        label: primaryLabel,
        isPrimary: true,
        onPressed: (_) {
          if (currentMethod == 'GCash') {
            state.pop(
              _PaymentResult(
                cashReceived: 0.0,
                paymentMethod: 'GCash',
              ),
            );
            return;
          }

          if (!state.formKey.currentState!.validate()) return;

          state.pop(
            _PaymentResult(
              cashReceived: currentMethod == 'Cash'
                  ? (state.value<double>('cash') ?? 0.0)
                  : total,
              paymentMethod: currentMethod,
              notes: state.textController('notes').text.trim().isEmpty
                  ? null
                  : state.textController('notes').text.trim(),
              referenceNumber: null,
              customerName:
                  settings.customerNameVisible &&
                          state.textController('customerName').text.trim().isNotEmpty
                      ? state.textController('customerName').text.trim()
                      : null,
            ),
          );
        },
      ),
    ];
  }

  List<String> _availableMethods(bool gcashEnabled) {
    if (gcashEnabled) {
      return const ['Cash', 'GCash'];
    }
    return const ['Cash'];
  }

  String _currentMethod(
    AppDialogFormState<_PaymentResult?> state,
    PaymentSettings settings,
  ) {
    final methods = _availableMethods(settings.gcashEnabled);
    final method = state.value<String>('method', 'Cash') ?? 'Cash';
    return methods.contains(method) ? method : 'Cash';
  }

  double _currentCash(AppDialogFormState<_PaymentResult?> state) =>
      state.value<double>('cash') ?? 0.0;

  IconData _paymentMethodIcon(String method) {
    return switch (method) {
      'Cash' => Icons.payments_outlined,
      'GCash' => Icons.qr_code_2,
      _ => Icons.payments_outlined,
    };
  }

  String _customerNameLabel(PaymentSettings settings) {
    if (!settings.customerNameVisible) return 'Customer Name';
    if (settings.customerNameRequired) return 'Customer Name (required)';
    return 'Customer Name (optional)';
  }

  String? _validateCustomerName(PaymentSettings settings, String? value) {
    if (!settings.customerNameRequired) return null;
    if ((value?.trim() ?? '').isEmpty) {
      return 'Customer name is required';
    }
    return null;
  }

  double _roundUp(double value, double to) {
    return (value / to).ceil() * to;
  }

  Widget _buildQuickCashButton(
    AppDialogFormState<_PaymentResult?> state,
    double amount,
  ) {
    return ActionChip(
      label: Text(CurrencyUtils.formatWhole(amount)),
      onPressed: () {
        state.textController('cash').text = amount.toStringAsFixed(2);
        state.setValue<double>('cash', amount);
      },
    );
  }
}

// ── Payment method tile ──────────────────────────────────────────────

/// A single tappable payment-method option used by the payment dialog.
/// 56px minimum height keeps it a comfortable touch target; colors come
/// entirely from the color scheme so light and dark modes both work.
class _PaymentMethodTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? cs.primary : foreground,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.titleSmall(context).copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
