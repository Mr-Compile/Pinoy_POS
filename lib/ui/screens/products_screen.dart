import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
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
      return Scaffold(
        appBar: AppBar(
          title: const Text('Products'),
        ),
        body: const LoadingState(),
      );
    }

    // Primary create action. On tablet/desktop a visible labeled
    // FilledButton.icon is placed in the AppBar; on mobile a FAB.extended
    // is used so the action is always reachable and clearly labeled.
    final Widget? createAction = canEdit
        ? (isTablet
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                  onPressed: () => _showProductDialog(),
                ),
              )
            : null)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          ?createAction,
        ],
      ),
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
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search products',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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
                    action: _products.isEmpty && canEdit
                        ? FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Product'),
                            onPressed: () => _showProductDialog(),
                          )
                        : null,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      final category = _categories.firstWhere(
                        (c) => c.id == product.categoryId,
                        orElse: () => Category(
                            id: 0,
                            name: 'Uncategorized',
                            createdAt: DateTime.now()),
                      );
                      return AppCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
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
                          title: Text(product.name),
                          subtitle: Text(
                              '${category.name} • Stock: ${product.stock}'),
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
                                    onPressed: () =>
                                        _showProductDialog(product: product),
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
          ),
        ],
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
    String? selectedImagePath = product?.imageUrl;

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
                  // ── Image section ──
                  GestureDetector(
                    onTap: () async {
                      final imageService = ImageService();
                      final result = await imageService.pickAndStoreImage();
                      if (!context.mounted) return;
                      if (result.isSuccess) {
                        setState(() {
                          selectedImagePath = result.filePath;
                          hasChanges = true;
                        });
                      } else if (result.error != 'No image selected') {
                        await AppDialogService.error(
                          context,
                          title: 'Image Error',
                          message: result.error ?? 'Failed to select image.',
                        );
                      }
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: selectedImagePath != null && selectedImagePath!.isNotEmpty
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AppImage(
                                    imagePath: selectedImagePath,
                                    borderRadius: 12,
                                    placeholderIcon: Icons.inventory_2,
                                    placeholderIconSize: 32,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo,
                                  size: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add Image',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (selectedImagePath != null && selectedImagePath!.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          selectedImagePath = null;
                          hasChanges = true;
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Remove Image'),
                    ),
                  const SizedBox(height: 12),
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
                  final discard = await AppDialogService.unsavedChanges(
                    context,
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
                selectedImagePath,
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
    String? selectedImagePath,
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
      AppDialogService.error(context, title: 'Duplicate Name', message: 'Product name already exists in this category.');
      return;
    }

    setSaving(true);

    try {
      final productData = Product(
        name: name,
        price: double.parse(priceController.text),
        stock: int.parse(stockController.text),
        categoryId: selectedCategoryId,
        imageUrl: selectedImagePath,
        createdAt: DateTime.now(),
      );

      if (product == null) {
        final productService = ref.read(productServiceProvider);
        await productService.createProduct(productData);
        if (mounted) {
          await AppDialogService.success(context, title: 'Created', message: 'Product created successfully.');
        }
      } else {
        final productService = ref.read(productServiceProvider);
        final oldImagePath = product.imageUrl;
        await productService.updateProduct(
          product.copyWith(
            name: productData.name,
            price: productData.price,
            stock: productData.stock,
            categoryId: productData.categoryId,
            imageUrl: productData.imageUrl,
          ),
        );
        // Clean up old image if it was replaced or removed
        if (oldImagePath != null &&
            oldImagePath.isNotEmpty &&
            oldImagePath != selectedImagePath) {
          await ImageService().deleteImage(oldImagePath);
        }
        if (mounted) {
          await AppDialogService.success(context, title: 'Updated', message: 'Product updated successfully.');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        AppDialogService.error(context, title: 'Save Failed', message: 'Failed to save product.');
      }
    } finally {
      setSaving(false);
    }
  }
}
