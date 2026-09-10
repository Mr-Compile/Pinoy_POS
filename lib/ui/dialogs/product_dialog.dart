import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';

import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/dialogs/category_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_messages.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Shows a responsive Add/Edit Product dialog.
///
/// Loads active categories from the service when opened, handles the empty
/// category state, and validates category assignment at both UI and service
/// layers.
Future<ModalResult<void>?> showProductDialog(
  BuildContext context,
  WidgetRef ref, {
  Product? product,
}) {
  return showDialog<ModalResult<void>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ProductDialog(product: product, ref: ref),
  );
}

class _ProductDialog extends ConsumerStatefulWidget {
  final Product? product;
  final WidgetRef ref;

  const _ProductDialog({this.product, required this.ref});

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  late Future<_CategoryList> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _loadCategories();
  }

  Future<_CategoryList> _loadCategories() async {
    final categoryService = widget.ref.read(categoryServiceProvider);
    final active = await categoryService.getActiveCategories();

    if (widget.product?.categoryId != null) {
      final current = await categoryService.getCategoryById(
        widget.product!.categoryId!,
      );
      if (current != null && !active.any((c) => c.id == current.id)) {
        return (active: active, display: [...active, current]);
      }
    }

    return (active: active, display: active);
  }

  Future<void> _refreshCategories() async {
    setState(() {
      _categoriesFuture = _loadCategories();
    });
    await _categoriesFuture;
  }

  Future<void> _createCategory() async {
    final result = await showCategoryDialog(context, widget.ref);
    if (result?.isSaved ?? false) {
      bumpCatalogRevision(widget.ref);
      await _refreshCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;
    final brightness = Theme.of(context).brightness;

    return AppDialogForm<ModalResult<void>>(
      type: isEditing ? AppDialogType.edit : AppDialogType.add,
      title: isEditing ? 'Edit Product' : 'Add Product',
      message: isEditing
          ? 'Update the details and tap Save.'
          : 'Enter the details and tap Save.',
      icon: isEditing ? Icons.edit : Icons.add,
      iconColor: isEditing
          ? AppSemanticColors.resolve(AppSemanticColors.success, brightness)
          : AppSemanticColors.resolve(AppSemanticColors.info, brightness),
      canPop: true,
      childBuilder: (context, state) => FutureBuilder<_CategoryList>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ??
              (active: <Category>[], display: <Category>[]);

          return _ProductForm(
            state: state,
            product: widget.product,
            categories: data,
            ref: widget.ref,
            onCreateCategory: _createCategory,
          );
        },
      ),
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          isLoading: state.isSaving,
          onPressed: (context) async {
            if (state.hasChanges) {
              final discard = await AppDialogService.unsavedChanges(context);
              if (discard == true && context.mounted) {
                state.pop(const ModalResult<void>.cancelled());
              }
            } else if (context.mounted) {
              state.pop(const ModalResult<void>.cancelled());
            }
          },
        ),
        AppDialogAction(
          label: 'Save',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: (context) => _save(state, context),
        ),
      ],
    );
  }

  Future<void> _save(
    AppDialogFormState<ModalResult<void>> state,
    BuildContext dialogContext,
  ) async {
    if (!state.formKey.currentState!.validate()) {
      return;
    }

    final selectedCategoryId = state.value<int?>('categoryId');
    if (selectedCategoryId == null) {
      if (dialogContext.mounted) {
        AppDialogService.validation(
          dialogContext,
          title: 'Category Required',
          message: 'Please select a category for this product.',
        );
      }
      return;
    }

    final name = state.textController('name').text.trim();
    final priceText = state.textController('price').text.trim();
    final stockText = state.textController('stock').text.trim();

    final price = double.tryParse(priceText);
    final stock = int.tryParse(stockText);

    if (name.isEmpty || price == null || price <= 0 || stock == null || stock < 0) {
      if (dialogContext.mounted) {
        AppDialogService.validation(
          dialogContext,
          title: 'Invalid Product',
          message: AppMessages.reviewFields,
        );
      }
      return;
    }

    final productService = ref.read(productServiceProvider);
    final existingProduct = widget.product;
    final existingId = existingProduct?.id;

    final existingName = await productService.getProductByName(name);
    if (existingName != null &&
        existingName.categoryId == selectedCategoryId &&
        (existingId == null || existingName.id != existingId)) {
      if (dialogContext.mounted) {
        AppDialogService.error(
          dialogContext,
          title: 'Duplicate Product',
          message: 'A product with this name already exists in the selected category.',
        );
      }
      return;
    }

    state.setSaving(true);

    try {
      final productData = Product(
        name: name,
        price: price,
        stock: stock,
        categoryId: selectedCategoryId,
        imageUrl: state.value<String?>('imagePath'),
        createdAt: existingProduct?.createdAt ?? DateTime.now(),
      );

      bool success;
      if (existingProduct == null) {
        success = await productService.createProduct(productData);
      } else {
        success = await productService.updateProduct(
          existingProduct.copyWith(
            name: productData.name,
            price: productData.price,
            stock: productData.stock,
            categoryId: productData.categoryId,
            imageUrl: productData.imageUrl,
          ),
        );
      }

      if (dialogContext.mounted) {
        if (success) {
          state.pop(const ModalResult<void>.saved());
        } else {
          state.setSaving(false);
          AppDialogService.error(
            dialogContext,
            title: 'Save Failed',
            message: AppMessages.productSaveError,
          );
        }
      }
    } catch (_) {
      if (dialogContext.mounted) {
        state.setSaving(false);
        AppDialogService.error(
          dialogContext,
          title: 'Save Failed',
          message: AppMessages.productSaveError,
        );
      }
    }
  }
}

/// Form content for the product dialog, separated from the dialog shell so
/// the dialog shell can own controller lifecycle through [AppDialogFormState].
class _ProductForm extends StatelessWidget {
  final AppDialogFormState<ModalResult<void>> state;
  final Product? product;
  final _CategoryList categories;
  final WidgetRef ref;
  final VoidCallback onCreateCategory;

  const _ProductForm({
    required this.state,
    this.product,
    required this.categories,
    required this.ref,
    required this.onCreateCategory,
  });

  @override
  Widget build(BuildContext context) {
    final nameController = state.textController('name', text: product?.name ?? '');
    final priceController = state.textController(
      'price',
      text: product?.price.toString() ?? '',
    );
    final stockController = state.textController(
      'stock',
      text: product?.stock.toString() ?? '',
    );
    final selectedImagePath = state.value<String?>('imagePath', product?.imageUrl);
    final selectedCategoryId = state.value<int?>('categoryId', product?.categoryId);

    final cs = Theme.of(context).colorScheme;

    return Form(
      key: state.formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImageSection(context, cs, selectedImagePath),
          const SizedBox(height: Spacing.lg),
          _buildNameField(context, nameController),
          const SizedBox(height: Spacing.md),
          _buildPriceField(context, priceController),
          const SizedBox(height: Spacing.md),
          _buildStockField(context, stockController),
          const SizedBox(height: Spacing.md),
          _buildCategorySection(
            context,
            selectedCategoryId,
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection(
    BuildContext context,
    ColorScheme cs,
    String? selectedImagePath,
  ) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              final imageService = ImageService();
              final result = await imageService.pickAndStoreImage();
              if (!context.mounted) return;
              if (result.isSuccess) {
                state.setValue<String?>('imagePath', result.filePath);
              } else if (result.error != 'No image selected') {
                await AppDialogService.error(
                  context,
                  title: 'Image Error',
                  message: result.error ?? 'Failed to select image.',
                );
              }
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                border: Border.all(
                  color: selectedImagePath != null && selectedImagePath.isNotEmpty
                      ? cs.outline
                      : cs.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (selectedImagePath != null && selectedImagePath.isNotEmpty)
                    AppImage(
                      imagePath: selectedImagePath,
                      borderRadius: AppRadius.control,
                      placeholderIcon: Icons.inventory_2,
                      placeholderIconSize: 40,
                      fit: BoxFit.cover,
                    )
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 42,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to change image',
                          style: AppTypography.labelSmall(context).copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selectedImagePath != null && selectedImagePath.isNotEmpty)
            TextButton.icon(
              onPressed: () => state.setValue<String?>('imagePath', null),
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              label: const Text('Remove Image'),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField(
    BuildContext context,
    TextEditingController controller,
  ) {
    return AppTextFormField(
      controller: controller,
      label: 'Product Name',
      hint: 'e.g. Pastil',
      prefixIcon: Icons.inventory_2_outlined,
      textInputAction: TextInputAction.next,
      validator: (value) => Validators.required(value, 'Product name'),
      onChanged: (_) => state.markChanged(),
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildPriceField(
    BuildContext context,
    TextEditingController controller,
  ) {
    return AppTextFormField(
      controller: controller,
      label: 'Price',
      hint: '0.00',
      prefixIcon: Icons.payments_outlined,
      prefixText: '${CurrencyUtils.symbol()} ',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      validator: (value) => Validators.compose([
        (v) => Validators.required(v, 'Price'),
        (v) => Validators.positiveNumber(v, 'Price'),
      ], value),
      onChanged: (_) => state.markChanged(),
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildStockField(
    BuildContext context,
    TextEditingController controller,
  ) {
    return AppTextFormField(
      controller: controller,
      label: 'Stock',
      hint: 'Enter quantity',
      prefixIcon: Icons.inventory_outlined,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      validator: (value) => Validators.compose([
        (v) => Validators.required(v, 'Stock'),
        (v) => Validators.nonNegativeNumber(v, 'Stock'),
      ], value),
      onChanged: (_) => state.markChanged(),
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    int? selectedCategoryId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final authNotifier = ref.read(authStateProvider.notifier);
    final canEditCategories = authNotifier.hasPermission('edit_categories');

    if (categories.active.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No categories available',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Create a category before adding products.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (canEditCategories) ...[
              const SizedBox(height: Spacing.md),
              AppButton.outlined(
                onPressed: onCreateCategory,
                label: 'Create Category',
                icon: Icons.add,
                color: AppButtonColor.info,
                fullWidth: true,
              ),
            ],
          ],
        ),
      );
    }

    return AppDropdownField<int?>(
      label: 'Category',
      hint: 'Select category',
      prefixIcon: Icons.category_outlined,
      initialValue: selectedCategoryId,
      items: categories.display.map((category) {
        final isMissing = !categories.active.any((c) => c.id == category.id);
        final suffix = _labelSuffix(category, isMissing);
        return DropdownMenuItem<int?>(
          value: category.id,
          child: Text('${category.name}$suffix'),
        );
      }).toList(),
      onChanged: (value) => state.setValue<int?>('categoryId', value),
      validator: (value) {
        if (value == null) {
          return 'Category is required';
        }
        return null;
      },
    );
  }

  String _labelSuffix(Category category, bool isMissing) {
    if (isMissing) {
      if (category.isDeleted) return ' (deleted)';
      if (!category.isActive) return ' (inactive)';
      return ' (unavailable)';
    }
    return '';
  }
}

/// Tuple returned when loading the categories for the product dialog.
typedef _CategoryList = ({List<Category> active, List<Category> display});
