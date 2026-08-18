import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  List<Category> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });

    final categoryService = ref.read(categoryServiceProvider);
    final categories = await categoryService.getAllCategories();

    if (mounted) {
      setState(() {
        _categories = categories.where((c) => !c.isDeleted).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleCategoryStatus(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('change_category_status')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category.isActive ? 'Deactivate Category' : 'Activate Category'),
        content: Text('${category.isActive ? "Deactivate" : "Activate"} "${category.name}"?'),
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
      try {
        final categoryService = ref.read(categoryServiceProvider);
        final success = await categoryService.changeCategoryStatus(
          category.id!,
          !category.isActive,
        );
        if (mounted) {
          if (success) {
            showSuccessSnackbar(
              context,
              category.isActive ? 'Category deactivated' : 'Category activated',
            );
            _loadCategories();
          } else {
            showErrorSnackbar(context, 'Failed to update category status');
          }
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to update category status');
        }
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_categories')) {
      EnhancedDialogs.showAccessDeniedDialog(context: context);
      return;
    }

    final confirmed = await EnhancedDialogs.showDeleteDialog(
      context: context,
      itemName: category.name,
    );

    if (confirmed == true && mounted) {
      try {
        final categoryService = ref.read(categoryServiceProvider);
        await categoryService.deleteCategory(category.id!);
        if (mounted) {
          showSuccessSnackbar(context, 'Category deleted successfully');
          _loadCategories();
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(context, 'Failed to delete category');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authStateProvider.notifier);
    final canEdit = authNotifier.hasPermission('edit_categories');
    final canDelete = authNotifier.hasPermission('delete_categories');
    final canToggleStatus = authNotifier.hasPermission('change_category_status');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
        ),
        body: const LoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showCategoryDialog(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCategories,
          ),
        ],
      ),
      body: _categories.isEmpty
          ? const EmptyState(
              icon: Icons.category,
              title: 'No Categories',
              message: 'No categories available',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(category.name),
                    subtitle: Text(category.isActive ? 'Active' : 'Inactive'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canToggleStatus)
                          IconButton(
                            icon: Icon(
                              category.isActive ? Icons.toggle_on : Icons.toggle_off,
                              color: category.isActive ? Colors.green : Colors.grey,
                            ),
                            tooltip: category.isActive ? 'Deactivate' : 'Activate',
                            onPressed: () => _toggleCategoryStatus(category),
                          ),
                        if (canEdit)
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showCategoryDialog(category: category),
                          ),
                        if (canDelete)
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteCategory(category),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showCategoryDialog({Category? category}) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: category?.name ?? '');
    bool hasChanges = false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(category == null ? 'Add Category' : 'Edit Category'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              validator: (value) => Validators.required(value, 'Category name'),
              onChanged: (value) {
                if (!hasChanges) {
                  setState(() {
                    hasChanges = true;
                  });
                }
              },
              onFieldSubmitted: (_) => _saveCategory(
                formKey,
                nameController,
                category,
                setState,
                isSaving,
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
              onPressed: () => _saveCategory(
                formKey,
                nameController,
                category,
                setState,
                isSaving,
              ),
              label: 'Save',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCategory(
    GlobalKey<FormState> formKey,
    TextEditingController nameController,
    Category? category,
    StateSetter setState,
    bool isSaving,
  ) async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final name = nameController.text.trim();

    final isDuplicate = _categories.any((c) =>
      c.name.toLowerCase() == name.toLowerCase() &&
      (category == null || c.id != category.id)
    );

    if (isDuplicate) {
      showErrorSnackbar(context, 'Category name already exists');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final categoryService = ref.read(categoryServiceProvider);
      final categoryData = Category(
        name: name,
        createdAt: DateTime.now(),
      );

      if (category == null) {
        await categoryService.createCategory(categoryData);
        if (mounted) {
          showSuccessSnackbar(context, 'Category created successfully');
        }
      } else {
        await categoryService.updateCategory(
          category.copyWith(name: categoryData.name),
        );
        if (mounted) {
          showSuccessSnackbar(context, 'Category updated successfully');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        _loadCategories();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Failed to save category');
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }
}
