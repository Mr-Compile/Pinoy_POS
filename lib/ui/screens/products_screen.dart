import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/enhanced_dialogs.dart';
import 'package:pinoy_pos/ui/widgets/success_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/error_snackbar.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
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

    final productService = ref.read(productServiceProvider);
    final categoryService = ref.read(categoryServiceProvider);
    final products = await productService.getActiveProducts();
    final categories = await categoryService.getActiveCategories();

    if (mounted) {
      setState(() {
        _products = products;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_products')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await EnhancedDialogs.showDeleteDialog(
      context: context,
      itemName: product.name,
    );

    if (confirmed == true && mounted) {
      try {
        final productService = ref.read(productServiceProvider);
      await productService.deleteProduct(product.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'Product deleted successfully');
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to delete product');
        }
      }
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
    int? selectedCategoryId = product?.categoryId;
    bool hasChanges = false;
    bool isSaving = false;

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
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.required(value, 'Product name'),
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.compose([
                      (v) => Validators.required(v, 'Price'),
                      (v) => Validators.positiveNumber(v, 'Price'),
                    ], value),
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: stockController,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.compose([
                      (v) => Validators.required(v, 'Stock'),
                      (v) => Validators.nonNegativeNumber(v, 'Stock'),
                    ], value),
                    onChanged: (value) {
                      if (!hasChanges) {
                        setState(() {
                          hasChanges = true;
                        });
                      }
                    },
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
                        hasChanges = true;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Category is required';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (hasChanges) {
                  final discard = await EnhancedDialogs.showUnsavedChangesDialog(
                    context: context,
                  );
                  if (discard == true && context.mounted) {
                    Navigator.pop(context);
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Cancel'),
            ),
            LoadingButton(
              isLoading: isSaving,
              onPressed: () => _saveProduct(
                formKey,
                nameController,
                priceController,
                stockController,
                selectedCategoryId,
                product,
                setState,
                (value) => setState(() => isSaving = value),
              ),
              label: 'Save',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct(
    GlobalKey<FormState> formKey,
    TextEditingController nameController,
    TextEditingController priceController,
    TextEditingController stockController,
    int? selectedCategoryId,
    Product? product,
    StateSetter setState,
    ValueChanged<bool> setSaving,
  ) async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final name = nameController.text.trim();
    
    // Check for duplicate product name within same category
    final isDuplicate = _products.any((p) => 
      p.name.toLowerCase() == name.toLowerCase() && 
      p.categoryId == selectedCategoryId &&
      (product == null || p.id != product.id)
    );
    
    if (isDuplicate) {
      showErrorSnackbar(context, 'Product name already exists in this category');
      return;
    }

    setSaving(true);

    try {
      final productData = Product(
        name: name,
        price: double.parse(priceController.text),
        stock: int.parse(stockController.text),
        categoryId: selectedCategoryId,
        createdAt: DateTime.now(),
      );

      if (product == null) {
        final productService = ref.read(productServiceProvider);
        await productService.createProduct(productData);
        if (mounted) {
          showSuccessSnackbar(context, 'Product created successfully');
        }
      } else {
        final productService = ref.read(productServiceProvider);
        await productService.updateProduct(
          product.copyWith(
            name: productData.name,
            price: productData.price,
            stock: productData.stock,
            categoryId: productData.categoryId,
          ),
        );
        if (mounted) {
          showSuccessSnackbar(context, 'Product updated successfully');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to save product');
      }
    } finally {
      setSaving(false);
    }
  }
}
