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
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

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
          ? FilledButton.icon(
              icon: const Icon(Icons.inventory_2),
              label: const Text('Go to Products'),
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

    return AppCard(
      child: InkWell(
        onTap: isOutOfStock ? null : () => _addToCart(product),
        borderRadius: BorderRadius.circular(16),
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
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
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
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₱${product.price.toStringAsFixed(2)}',
                    style: AppTypography.titleMediumBold(context),
                  ),
                  const SizedBox(height: 2),
                  if (isOutOfStock)
                    Text(
                      'Out of stock',
                      style: TextStyle(fontSize: 11, color: cs.error),
                    )
                  else if (isLowStock)
                    Text(
                      'Low stock: ${product.stock} left',
                      style: TextStyle(fontSize: 11, color: cs.secondary),
                    )
                  else
                    Text(
                      '${product.stock} available',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
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
            ? TextButton.icon(
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Clear Filters'),
                onPressed: _clearFilters,
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
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: 12,
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
        label: Text('${cart.itemCount} items · ₱${cart.total.toStringAsFixed(2)}'),
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
              Text('Cart', style: Theme.of(context).textTheme.titleLarge),
              if (cart.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear'),
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
                      Text('Subtotal', style: Theme.of(context).textTheme.bodyLarge),
                      Text(
                        '₱${cart.subtotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTypography.titleLargeBold(context)),
                      Text(
                        '₱${cart.total.toStringAsFixed(2)}',
                        style: AppTypography.headlineSmallBold(context).copyWith(
                              color: cs.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  LoadingButton(
                    isLoading: cart.isProcessing,
                    onPressed: canSell ? onCheckout : null,
                    label: 'Complete Sale',
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          // Name + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₱${product.price.toStringAsFixed(2)} × ${item.quantity}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          // Quantity controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QtyButton(
                icon: Icons.remove,
                onTap: () => ref.read(cartProvider.notifier).decrement(product.id!),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Text(
                  '${item.quantity}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _QtyButton(
                icon: Icons.add,
                onTap: () => ref.read(cartProvider.notifier).increment(product.id!),
              ),
            ],
          ),
          // Subtotal
          SizedBox(
            width: 70,
            child: Text(
              '₱${item.lineTotal.toStringAsFixed(2)}',
              style: AppTypography.titleSmallBold(context),
              textAlign: TextAlign.right,
            ),
          ),
          // Remove
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => ref.read(cartProvider.notifier).remove(product.id!),
            tooltip: 'Remove item',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16),
        ),
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
      loading: () => AlertDialog(
        title: const Text('Payment'),
        content: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
      error: (error, stackTrace) => AlertDialog(
        title: const Text('Payment'),
        content: Text('Failed to load payment settings: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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

    return AlertDialog(
      title: const Text('Payment'),
      content: SingleChildScrollView(
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
                      '₱${widget.total.toStringAsFixed(2)}',
                      style: AppTypography.titleLargeBold(context)
                          .copyWith(color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
              // Payment method
              DropdownButtonFormField<String>(
                key: ValueKey(currentMethod),
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
                  decoration: const InputDecoration(
                    labelText: 'Cash Received',
                    prefixText: '₱',
                    prefixIcon: Icon(Icons.payments),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
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
                          '₱${change.toStringAsFixed(2)}',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (currentMethod == 'GCash')
          LoadingButton(
            isLoading: false,
            onPressed: () {
              Navigator.pop(
                context,
                _PaymentResult(
                  cashReceived: 0.0,
                  paymentMethod: 'GCash',
                ),
              );
            },
            label: 'Continue with GCash',
          )
        else
          LoadingButton(
            isLoading: false,
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
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
            },
            label: 'Complete Sale',
          ),
      ],
    );
  }

  double _roundUp(double value, double to) {
    return (value / to).ceil() * to;
  }

  Widget _buildQuickCashButton(double amount) {
    return ActionChip(
      label: Text('₱${amount.toStringAsFixed(0)}'),
      onPressed: () {
        _cashController.text = amount.toStringAsFixed(2);
        setState(() {});
      },
    );
  }
}
