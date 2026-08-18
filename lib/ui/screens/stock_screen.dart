import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
    });

    final productService = ref.read(productServiceProvider);
    final products = await productService.getActiveProducts();

    if (mounted) {
      setState(() {
        _products = products;
        _isLoading = false;
      });
    }
  }

  /// Performs a stock operation.
  ///
  /// Staff only have the `add_stock` permission, so an increase is routed
  /// through [StockService.addStock] (increase-only, validated > 0). A
  /// decrease requires the `adjust_stock` permission and is routed through
  /// [StockService.adjustStock]; the service layer rejects it for Staff
  /// even if this path is somehow reached.
  Future<void> _changeStock(Product product, int adjustment) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('add_stock')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final isAdd = adjustment > 0;
    final newStock = product.stock + adjustment;
    if (newStock < 0) {
      showErrorSnackbar(context, 'Insufficient stock to remove');
      return;
    }

    // Staff are allowed to add stock only. A manual decrease requires the
    // adjust_stock permission; block it at the UI layer as well so the
    // confirmation dialog is never shown for an unauthorized action.
    if (!isAdd && !authNotifier.hasPermission('adjust_stock')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isAdd ? 'Add Stock' : 'Remove Stock'),
        content: Text(isAdd
            ? 'Add $adjustment to ${product.name}? (New stock: $newStock)'
            : 'Remove ${-adjustment} from ${product.name}? (New stock: $newStock)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isProcessing = true;
      });

      try {
        final stockService = ref.read(stockServiceProvider);
        bool success;
        if (isAdd) {
          // Increase: permitted for Staff (add_stock). addStock validates
          // quantity > 0, product exists and is active, then updates stock,
          // inserts stock_history, and logs activity — all in one
          // SQLite transaction.
          success = await stockService.addStock(
            product.id!,
            adjustment,
            'Manual stock addition',
          );
        } else {
          // Decrease / absolute adjust: requires adjust_stock permission.
          // The service enforces authorization again before mutating.
          success = await stockService.adjustStock(
            product.id!,
            newStock,
            'Manual stock adjustment',
          );
        }
        if (mounted) {
          if (success) {
            showSuccessSnackbar(
              context,
              isAdd ? 'Stock added successfully' : 'Stock adjusted successfully',
            );
            _loadProducts();
          } else {
            showErrorSnackbar(context, 'Failed to update stock');
          }
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to update stock');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canAddStock = authNotifier.hasPermission('add_stock');
    final canAdjustStock = authNotifier.hasPermission('adjust_stock');
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Stock Management'),
        ),
        body: const LoadingState(),
      );
    }

    final lowStockProducts = _products.where((p) => p.isLowStock).toList();

    // Build the trailing stock action buttons based on permissions.
    // Staff: add-only (+10). Owner: add and remove (+10 / -10).
    Widget? buildStockActions(Product product) {
      if (!canAddStock) return null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add stock',
            onPressed: _isProcessing ? null : () => _changeStock(product, 10),
          ),
          if (canAdjustStock)
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: 'Remove stock',
              onPressed: _isProcessing ? null : () => _changeStock(product, -10),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Management'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lowStockProducts.isNotEmpty) ...[
              Text(
                'Low Stock Alert',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                    ),
              ),
              const SizedBox(height: 12),
              ...lowStockProducts.map((product) => AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(product.name),
                      subtitle: Text('Stock: ${product.stock} (Min: ${product.minStock})'),
                      trailing: buildStockActions(product),
                    ),
                  )),
              const SizedBox(height: 24),
            ],
            Text(
              'All Products',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _products.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2,
                    title: 'No Products',
                    message: 'Add products to manage stock',
                  )
                : Column(
                    children: _products.map((product) => AppCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(product.name),
                            subtitle: Text('Stock: ${product.stock}'),
                            trailing: buildStockActions(product),
                          ),
                        )).toList(),
                  ),
          ],
        ),
      ),
    );
  }
}
