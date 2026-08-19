import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/core/app_theme.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  List<Product> _products = [];
  final Map<int, int> _cart = {};
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

    // Read ProductService through its Riverpod provider so the UI never
    // instantiates the service directly.
    final productService = ref.read(productServiceProvider);
    final products = await productService.getActiveProducts();

    if (mounted) {
      setState(() {
        _products = products;
        _isLoading = false;
      });
    }
  }

  double get _total {
    double total = 0;
    _cart.forEach((productId, quantity) {
      try {
        final product = _products.firstWhere((p) => p.id == productId);
        total += product.price * quantity;
      } catch (e) {
        // Product not found, skip this cart item
      }
    });
    return total;
  }

  void _addToCart(Product product) {
    if (product.id == null) {
      AppDialogService.error(context, title: 'Error', message: 'Invalid product');
      return;
    }

    if (product.stock <= 0) {
      AppDialogService.error(context, title: 'Error', message: 'Product is out of stock');
      return;
    }
    
    final currentQuantity = _cart[product.id!] ?? 0;
    if (currentQuantity >= product.stock) {
      AppDialogService.error(context, title: 'Error', message: 'Not enough stock available');
      return;
    }
    
    setState(() {
      _cart[product.id!] = currentQuantity + 1;
    });
  }

  void _removeFromCart(int productId) {
    setState(() {
      if (_cart[productId] != null) {
        if (_cart[productId]! > 1) {
          _cart[productId] = _cart[productId]! - 1;
        } else {
          _cart.remove(productId);
        }
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      AppDialogService.error(context, title: 'Error', message: 'Cart is empty');
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('create_sales')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final total = _total;
    final result = await showDialog<_PaymentResult>(
      context: context,
      builder: (context) => _PaymentDialog(total: total),
    );

    if (result == null || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

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
        } catch (e) {
          // skip missing product
        }
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
          AppDialogService.success(context, title: 'Success', message: 'Sale completed successfully');
          _loadProducts();
        } else {
          setState(() {
            _isProcessing = false;
          });
          AppDialogService.error(context, title: 'Error', message: 'Failed to complete sale');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        AppDialogService.error(context, title: 'Error', message: 'Failed to complete sale');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canSell = authNotifier.hasPermission('create_sales');
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('POS'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
      ),
      body: _products.isEmpty
          ? const EmptyState(
              icon: Icons.point_of_sale,
              title: 'No Products',
              message: 'Add products to start selling',
            )
          : isTablet
              ? _buildTabletLayout(canSell)
              : _buildMobileLayout(canSell),
    );
  }

  Widget _buildMobileLayout(bool canSell) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              final quantity = _cart[product.id] ?? 0;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.inventory_2,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${product.price.toStringAsFixed(2)}',
                      style: AppTypography.titleMediumBold(context),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: quantity > 0 && product.id != null
                              ? () => _removeFromCart(product.id!)
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            quantity.toString(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: product.stock > 0 && product.id != null
                              ? () => _addToCart(product)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '₱${_total.toStringAsFixed(2)}',
                        style: AppTypography.headlineSmallBold(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: LoadingButton(
                      isLoading: _isProcessing,
                      onPressed: canSell ? _checkout : null,
                      label: 'Checkout',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabletLayout(bool canSell) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.9,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              final quantity = _cart[product.id] ?? 0;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.inventory_2,
                          size: 56,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${product.price.toStringAsFixed(2)}',
                      style: AppTypography.titleLargeBold(context),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: quantity > 0 && product.id != null
                              ? () => _removeFromCart(product.id!)
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            quantity.toString(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: product.stock > 0 && product.id != null
                              ? () => _addToCart(product)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_cart.isNotEmpty)
          Container(
            width: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Cart',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final productId = _cart.keys.elementAt(index);
                      final quantity = _cart[productId]!;
                      final product = _products.firstWhere((p) => p.id == productId);
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text('₱${product.price.toStringAsFixed(2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () => _removeFromCart(productId),
                            ),
                            Text('$quantity'),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () => _addToCart(product),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '₱${_total.toStringAsFixed(2)}',
                      style: AppTypography.headlineSmallBold(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: LoadingButton(
                    isLoading: _isProcessing,
                    onPressed: canSell ? _checkout : null,
                    label: 'Checkout',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final change = _parseCash() - widget.total;

    return AlertDialog(
      title: const Text('Payment'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total: ₱${widget.total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cashController,
                decoration: const InputDecoration(
                  labelText: 'Cash Received',
                  prefixText: '₱',
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
              const SizedBox(height: 12),
              if (_parseCash() >= widget.total)
                Text(
                  'Change: ₱${change.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
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

  double _parseCash() {
    return double.tryParse(_cashController.text.trim()) ?? 0.0;
  }
}
