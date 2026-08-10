import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/confirm_dialog.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final products = await _productService.getActiveProducts();
    final categories = await _categoryService.getActiveCategories();

    if (mounted) {
      setState(() {
        _products = products;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete Product',
      message: 'Are you sure you want to delete ${product.name}?',
    );

    if (confirmed == true) {
      await _productService.deleteProduct(product.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canEdit = authNotifier.hasPermission('edit_products');
    final canDelete = authNotifier.hasPermission('delete_products');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Products'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showProductDialog(),
            ),
        ],
      ),
      body: _products.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2,
              title: 'No Products',
              message: 'Add your first product to get started',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                final category = _categories.firstWhere(
                  (c) => c.id == product.categoryId,
                  orElse: () => Category(id: 0, name: 'Uncategorized', createdAt: DateTime.now()),
                );
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text('${category.name} • Stock: ${product.stock}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₱${product.price.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (canEdit || canDelete) ...[
                          const SizedBox(width: 8),
                          if (canEdit)
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showProductDialog(product: product),
                            ),
                          if (canDelete)
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteProduct(product),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showProductDialog({Product? product}) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product?.price.toString() ?? '');
    final stockController = TextEditingController(text: product?.stock.toString() ?? '');
    final barcodeController = TextEditingController(text: product?.barcode ?? '');
    int? selectedCategoryId = product?.categoryId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(product == null ? 'Add Product' : 'Edit Product'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Product name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Price is required';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Price must be greater than 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: stockController,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Stock is required';
                      }
                      final stock = int.tryParse(value);
                      if (stock == null || stock < 0) {
                        return 'Stock must be 0 or greater';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: barcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem<int>(
                        value: category.id,
                        child: Text(category.name),
                      );
                    }).toList(),
                    initialValue: selectedCategoryId,
                    onChanged: (value) {
                      setState(() {
                        selectedCategoryId = value;
                      });
                    },
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
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final productData = Product(
                  name: nameController.text,
                  price: double.parse(priceController.text),
                  stock: int.parse(stockController.text),
                  barcode: barcodeController.text,
                  categoryId: selectedCategoryId,
                  createdAt: DateTime.now(),
                );

                if (product == null) {
                  await _productService.createProduct(productData);
                } else {
                  await _productService.updateProduct(
                    product.copyWith(
                      name: productData.name,
                      price: productData.price,
                      stock: productData.stock,
                      barcode: productData.barcode,
                      categoryId: productData.categoryId,
                    ),
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
