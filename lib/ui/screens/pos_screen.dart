import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/category.dart';
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

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  final Map<int, int> _cart = {}; // productId → quantity
  bool _isLoading = true;
  bool _isProcessing = false;

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

  double get _subtotal {
    double total = 0;
    _cart.forEach((productId, quantity) {
      try {
        final product = _products.firstWhere((p) => p.id == productId);
        total += product.price * quantity;
      } catch (_) {}
    });
    return total;
  }

  int get _cartItemCount => _cart.values.fold(0, (sum, qty) => sum + qty);

  void _addToCart(Product product) {
    if (product.id == null) return;

    if (product.stock <= 0) {
      AppDialogService.error(context,
          title: 'Out of Stock',
          message: '${product.name} is currently out of stock.');
      return;
    }

    final currentQty = _cart[product.id!] ?? 0;
    if (currentQty >= product.stock) {
      AppDialogService.error(context,
          title: 'Insufficient Stock',
          message: 'Only ${product.stock} units of ${product.name} are available.');
      return;
    }

    setState(() {
      _cart[product.id!] = currentQty + 1;
    });
  }

  void _incrementCart(int productId) {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      final currentQty = _cart[productId] ?? 0;
      if (currentQty >= product.stock) {
        AppDialogService.error(context,
            title: 'Insufficient Stock',
            message: 'Only ${product.stock} units of ${product.name} are available.');
        return;
      }
      setState(() {
        _cart[productId] = currentQty + 1;
      });
    } catch (_) {}
  }

  void _decrementCart(int productId) {
    setState(() {
      final currentQty = _cart[productId] ?? 0;
      if (currentQty <= 1) {
        _cart.remove(productId);
      } else {
        _cart[productId] = currentQty - 1;
      }
    });
  }

  void _removeFromCart(int productId) {
    setState(() {
      _cart.remove(productId);
    });
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty) return;
    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: 'all cart items',
    );
    if (confirmed == true && mounted) {
      setState(() {
        _cart.clear();
      });
    }
  }

  // ── Checkout ───────────────────────────────────────────────────────

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      AppDialogService.error(context,
          title: 'Empty Cart', message: 'Add products to the cart before checkout.');
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('create_sales')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final total = _subtotal;
    final result = await showDialog<_PaymentResult>(
      context: context,
      builder: (context) => _PaymentDialog(total: total),
    );

    if (result == null || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final saleItems = <SaleItem>[];
      _cart.forEach((productId, quantity) {
        try {
          final product = _products.firstWhere((p) => p.id == productId);
          saleItems.add(SaleItem(
            saleId: 0,
            productId: productId,
            quantity: quantity,
            unitPrice: product.price,
            totalPrice: product.price * quantity,
          ));
        } catch (_) {}
      });

      final success = await ref.read(salesServiceProvider).createSale(
            items: saleItems,
            totalAmount: total,
            cashReceived: result.cashReceived,
            notes: result.notes,
          );

      if (mounted) {
        if (success) {
          setState(() {
            _cart.clear();
            _isProcessing = false;
          });
          await AppDialogService.success(
            context,
            title: 'Sale Completed',
            message: 'Transaction completed successfully.',
          );
          _loadProducts();
        } else {
          setState(() => _isProcessing = false);
          AppDialogService.error(context,
              title: 'Transaction Failed',
              message: 'Failed to complete the sale. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
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
        appBar: AppBar(title: const Text('POS')),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('POS')),
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
                // Staff won't see this button because canManageProducts is false.
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
    final quantity = _cart[product.id] ?? 0;
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
                  if (quantity > 0)
                    Positioned(
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
                    ),
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

  // ── Cart item row ──────────────────────────────────────────────────

  Widget _buildCartItemRow(int productId, int quantity) {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
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
                    '₱${product.price.toStringAsFixed(2)} × $quantity',
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
                _buildQtyButton(
                  icon: Icons.remove,
                  onTap: () => _decrementCart(productId),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Text(
                    '$quantity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildQtyButton(
                  icon: Icons.add,
                  onTap: () => _incrementCart(productId),
                ),
              ],
            ),
            // Subtotal
            SizedBox(
              width: 70,
              child: Text(
                '₱${(product.price * quantity).toStringAsFixed(2)}',
                style: AppTypography.titleSmallBold(context),
                textAlign: TextAlign.right,
              ),
            ),
            // Remove
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _removeFromCart(productId),
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildQtyButton({required IconData icon, required VoidCallback onTap}) {
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

  // ── Cart summary + checkout ────────────────────────────────────────

  Widget _buildCheckoutPanel(bool canSell, {bool isTablet = false}) {
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
              if (_cart.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear'),
                  onPressed: _clearCart,
                ),
            ],
          ),
        ),
        // Cart items
        Expanded(
          child: _cart.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Your cart is empty',
                  message: 'Select a product to start a transaction.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  itemCount: _cart.length,
                  itemBuilder: (context, index) {
                    final productId = _cart.keys.elementAt(index);
                    return _buildCartItemRow(productId, _cart[productId]!);
                  },
                ),
        ),
        // Totals + checkout
        if (_cart.isNotEmpty)
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
                        '₱${_subtotal.toStringAsFixed(2)}',
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
                        '₱${_subtotal.toStringAsFixed(2)}',
                        style: AppTypography.headlineSmallBold(context).copyWith(
                              color: cs.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  LoadingButton(
                    isLoading: _isProcessing,
                    onPressed: canSell ? _checkout : null,
                    label: 'Complete Sale',
                  ),
                ],
              ),
            ),
          ),
      ],
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
        if (_cart.isNotEmpty)
          Positioned(
            bottom: Spacing.lg,
            right: Spacing.lg,
            child: FloatingActionButton.extended(
              icon: const Icon(Icons.shopping_cart),
              label: Text('$_cartItemCount items · ₱${_subtotal.toStringAsFixed(2)}'),
              onPressed: () => _showMobileCartSheet(canSell),
            ),
          ),
      ],
    );
  }

  void _showMobileCartSheet(bool canSell) {
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
        builder: (context, scrollController) => _buildCheckoutPanel(canSell),
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

// ── Payment dialog ────────────────────────────────────────────────────

class _PaymentResult {
  final double cashReceived;
  final String? notes;

  _PaymentResult({required this.cashReceived, this.notes});
}

class _PaymentDialog extends StatefulWidget {
  final double total;

  const _PaymentDialog({required this.total});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _parseCash() {
    return double.tryParse(_cashController.text.trim()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final cash = _parseCash();
    final change = cash - widget.total;
    final cs = Theme.of(context).colorScheme;

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
              // Cash received
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
        LoadingButton(
          isLoading: false,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PaymentResult(
                cashReceived: _parseCash(),
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
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
