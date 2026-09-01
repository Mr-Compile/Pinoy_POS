import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_button.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

enum CategoryFilter { all, active, inactive }

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  List<Category> _categories = [];
  bool _isLoading = true;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  CategoryFilter _categoryFilter = CategoryFilter.all;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
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

  List<Category> get _filteredCategories {
    var result = _categories;

    switch (_categoryFilter) {
      case CategoryFilter.active:
        result = result.where((c) => c.isActive).toList();
        break;
      case CategoryFilter.inactive:
        result = result.where((c) => !c.isActive).toList();
        break;
      case CategoryFilter.all:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((c) {
        if (c.name.toLowerCase().contains(query)) return true;
        return false;
      }).toList();
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
      _categoryFilter = CategoryFilter.all;
      _searchQuery = '';
    });
    _searchController.clear();
  }

  Future<void> _toggleCategoryStatus(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('change_category_status')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.toggleCategoryConfirm(
      context,
      categoryName: category.name,
      isActivate: !category.isActive,
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
            await AppDialogService.success(context, title: 'Done', message: category.isActive ? 'Category deactivated.' : 'Category activated.');
            _loadCategories();
          } else {
            AppDialogService.error(context, title: 'Error', message: 'Failed to update category status.');
          }
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Error', message: 'Failed to update category status.');
        }
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (!authNotifier.hasPermission('delete_categories')) {
      AppDialogService.accessDenied(context);
      return;
    }

    final confirmed = await AppDialogService.deleteConfirm(
      context,
      itemName: category.name,
    );

    if (confirmed == true && mounted) {
      try {
        final categoryService = ref.read(categoryServiceProvider);
        await categoryService.deleteCategory(category.id!);
        if (mounted) {
          await AppDialogService.success(context, title: 'Deleted', message: 'Category deleted successfully.');
          _loadCategories();
        }
      } catch (e) {
        if (mounted) {
          AppDialogService.error(context, title: 'Delete Failed', message: 'Failed to delete category.');
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Categories',
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    // Primary create action. On tablet/desktop a visible labeled
    // button is placed in the AppBar; on mobile a FAB.extended
    // is used so the action is always reachable and clearly labeled.
    final Widget? createAction = canEdit
        ? (isTablet
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AppButton.filled(
                  size: AppButtonSize.small,
                  icon: Icons.add,
                  label: 'Add Category',
                  onPressed: () => _showCategoryDialog(),
                ),
              )
            : null)
        : null;

    return Scaffold(
      appBar: AppHeader(
        title: 'Categories',
        showBackButton: true,
        actions: [
          ?createAction,
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCategories,
          ),
        ],
      ),
      floatingActionButton: canEdit && !isTablet
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
              onPressed: () => _showCategoryDialog(),
            )
          : null,
      body: _categories.isEmpty
          ? EmptyState(
              icon: Icons.category,
              title: 'No Categories Yet',
              message: 'Create a category to organize your products.',
            )
          : Column(
              children: [
                _buildSearchAndFilters(),
                Expanded(
                  child: _filteredCategories.isEmpty
                      ? _buildEmptyFilterState()
                      : _buildCategoryList(
                          canEdit,
                          canDelete,
                          canToggleStatus,
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryList(
    bool canEdit,
    bool canDelete,
    bool canToggleStatus,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _filteredCategories.length,
      itemBuilder: (context, index) {
        final category = _filteredCategories[index];
        return _buildCategoryItem(
          category,
          canEdit,
          canDelete,
          canToggleStatus,
        );
      },
    );
  }

  Widget _buildCategoryItem(
    Category category,
    bool canEdit,
    bool canDelete,
    bool canToggleStatus,
  ) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = category.isActive ? cs.primary : cs.outline;

    final actions = <AppListAction>[
      if (canToggleStatus)
        AppListAction(
          icon: category.isActive ? Icons.toggle_on : Icons.toggle_off,
          tooltip: category.isActive ? 'Deactivate' : 'Activate',
          color: statusColor,
          onPressed: () => _toggleCategoryStatus(category),
        ),
      if (canEdit)
        AppListAction(
          icon: Icons.edit,
          tooltip: 'Edit category',
          onPressed: () => _showCategoryDialog(category: category),
        ),
      if (canDelete)
        AppListAction(
          icon: Icons.delete,
          tooltip: 'Delete category',
          color: cs.error,
          onPressed: () => _deleteCategory(category),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppListItem(
        title: category.name,
        subtitle: 'Category',
        statusLabel: category.isActive ? 'Active' : 'Inactive',
        statusColor: statusColor,
        actions: actions.isNotEmpty ? actions : null,
        onTap: canEdit ? () => _showCategoryDialog(category: category) : null,
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search categories...',
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
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip(CategoryFilter.all, 'All'),
                _buildFilterChip(CategoryFilter.active, 'Active'),
                _buildFilterChip(CategoryFilter.inactive, 'Inactive'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(CategoryFilter filter, String label) {
    final isSelected = _categoryFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _categoryFilter = filter;
          });
        },
      ),
    );
  }

  Widget _buildEmptyFilterState() {
    final hasFilters = _searchQuery.isNotEmpty ||
        _categoryFilter != CategoryFilter.all;

    String title;
    String message;
    if (!hasFilters) {
      title = 'No Categories Available';
      message = 'Categories will appear here once created.';
    } else if (_searchQuery.isNotEmpty) {
      title = 'No Results Found';
      message = "No categories match '$_searchQuery'. Try a different search term.";
    } else if (_categoryFilter == CategoryFilter.active) {
      title = 'No Active Categories';
      message = 'All categories are currently inactive.';
    } else {
      title = 'No Inactive Categories';
      message = 'All categories are currently active.';
    }

    return EmptyState(
      icon: Icons.search_off,
      title: title,
      message: message,
      action: hasFilters
          ? TextButton.icon(
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              onPressed: _clearFilters,
            )
          : null,
    );
  }

  Future<void> _showCategoryDialog({Category? category}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: category?.name ?? '');
    bool hasChanges = false;
    bool isSaving = false;

    await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          void setSaving(bool value) => setState(() => isSaving = value);

          return AlertDialog(
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
                onFieldSubmitted: isSaving
                    ? null
                    : (_) => _saveCategory(
                          formKey,
                          nameController,
                          category,
                          setSaving,
                          dialogContext,
                        ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (hasChanges) {
                          final discard = await AppDialogService.unsavedChanges(
                            context,
                          );
                          if (discard == true && dialogContext.mounted) {
                            Navigator.of(dialogContext, rootNavigator: true)
                                .pop(const ModalResult<void>.cancelled());
                          }
                        } else if (dialogContext.mounted) {
                          Navigator.of(dialogContext, rootNavigator: true)
                              .pop(const ModalResult<void>.cancelled());
                        }
                      },
                child: const Text('Cancel'),
              ),
              LoadingButton(
                isLoading: isSaving,
                onPressed: isSaving
                    ? null
                    : () => _saveCategory(
                          formKey,
                          nameController,
                          category,
                          setSaving,
                          dialogContext,
                        ),
                label: 'Save',
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
  }

  Future<void> _saveCategory(
    GlobalKey<FormState> formKey,
    TextEditingController nameController,
    Category? category,
    void Function(bool) setSaving,
    BuildContext dialogContext,
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
      if (dialogContext.mounted) {
        AppDialogService.error(
          dialogContext,
          title: 'Duplicate Name',
          message: 'Category name already exists.',
        );
      }
      return;
    }

    setSaving(true);

    try {
      final categoryService = ref.read(categoryServiceProvider);
      final categoryData = Category(
        name: name,
        createdAt: DateTime.now(),
      );

      if (category == null) {
        await categoryService.createCategory(categoryData);
      } else {
        await categoryService.updateCategory(
          category.copyWith(name: categoryData.name),
        );
      }

      if (dialogContext.mounted) {
        await AppDialogService.success(
          dialogContext,
          title: category == null ? 'Created' : 'Updated',
          message: category == null
              ? 'Category created successfully.'
              : 'Category updated successfully.',
        );
      }

      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true)
            .pop(const ModalResult<void>.saved());
      }

      _loadCategories();
    } catch (e) {
      if (dialogContext.mounted) {
        AppDialogService.error(
          dialogContext,
          title: 'Save Failed',
          message: 'Failed to save category.',
        );
      }
    } finally {
      if (dialogContext.mounted) {
        setSaving(false);
      }
    }
  }
}
