import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/services/category_service.dart';
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
  final CategoryService _categoryService = CategoryService();
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

    final categories = await _categoryService.getActiveCategories();

    if (mounted) {
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
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
        await _categoryService.deleteCategory(category.id!);
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
        ],
      ),
      body: _categories.isEmpty
          ? const EmptyState(
              icon: Icons.category,
              title: 'No Categories',
              message: 'Add your first category to get started',
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
    
    // Check for duplicate name
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
      final categoryData = Category(
        name: name,
        createdAt: DateTime.now(),
      );

      if (category == null) {
        await _categoryService.createCategory(categoryData);
        if (mounted) {
          showSuccessSnackbar(context, 'Category created successfully');
        }
      } else {
        await _categoryService.updateCategory(
          category.copyWith(
            name: categoryData.name,
          ),
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
