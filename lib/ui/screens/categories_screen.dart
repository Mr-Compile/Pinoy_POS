import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/catalog_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/dialogs/category_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/app_list_item.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';
import 'package:pinoy_pos/ui/widgets/summary_stat_card.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

enum CategoryFilter { all, active, inactive }

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  List<Category> _categories = [];
  Map<int, int> _productCounts = {};
  bool _isLoading = true;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  CategoryFilter _categoryFilter = CategoryFilter.all;
  Timer? _debounce;

  // Kept alive inside the app shell's PageView: reload whenever catalog
  // data changes elsewhere (product dialog, POS, trash restore).
  ProviderSubscription<int>? _catalogSubscription;

  @override
  void initState() {
    super.initState();
    _catalogSubscription = ref.listenManual<int>(
      catalogRevisionProvider,
      (previous, next) => _loadCategories(),
    );
    _loadCategories();
  }

  @override
  void dispose() {
    _catalogSubscription?.close();
    _catalogSubscription = null;
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });

    final categoryService = ref.read(categoryServiceProvider);
    final productService = ref.read(productServiceProvider);
    final categories = await categoryService.getAllCategories();
    final productCounts = await productService.getProductCountsByCategory();

    if (mounted) {
      setState(() {
        _categories = categories.where((c) => !c.isDeleted).toList();
        _productCounts = productCounts;
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
            bumpCatalogRevision(ref);
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
          bumpCatalogRevision(ref);
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

    final createAction = canEdit
        ? ResponsiveCreateAction(
            label: 'Add Category',
            icon: Icons.add,
            onPressed: _showCategoryDialog,
          )
        : null;

    if (_isLoading) {
      return Scaffold(
        appBar: AppHeader(
          title: 'Categories',
          showBackButton: true,
        ),
        body: const LoadingState(),
      );
    }

    final toolbarAction = createAction?.contentAction(context);
    final createFab = createAction?.fab(context);
    final bottomClearance =
        createAction?.contentBottomClearance(context) ?? 0;

    return Scaffold(
      appBar: AppHeader(
        title: 'Categories',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadCategories,
          ),
        ],
      ),
      floatingActionButton: createFab,
      body: Column(
        children: [
          if (_categories.isNotEmpty) ...[
            _buildStatsStrip(),
            _buildToolbar(toolbarAction),
          ] else if (toolbarAction != null)
            // Keep the single create action reachable on layouts where it
            // lives in the content toolbar even when the list is empty.
            CrudToolbar(primaryAction: toolbarAction),
          Expanded(
            child: _categories.isEmpty
                ? EmptyState(
                    icon: Icons.category,
                    title: 'No Categories Yet',
                    message: 'Create a category to organize your products.',
                  )
                : _filteredCategories.isEmpty
                    ? _buildEmptyFilterState()
                    : _buildCategoryList(
                        canEdit,
                        canDelete,
                        canToggleStatus,
                        bottomClearance,
                      ),
          ),
        ],
      ),
    );
  }

  /// Summary strip mirroring the All/Active/Inactive filter chips.
  /// Tapping a tile applies the same filter.
  Widget _buildStatsStrip() {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final activeCount = _categories.where((c) => c.isActive).length;
    final successColor = AppSemanticColors.resolve(
      AppSemanticColors.success,
      brightness,
    );
    final neutralColor = cs.outline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: SummaryStatCard(
              icon: Icons.label_outline,
              color: cs.primary,
              value: '${_categories.length}',
              label: 'Total',
              selected: _categoryFilter == CategoryFilter.all,
              onTap: () =>
                  setState(() => _categoryFilter = CategoryFilter.all),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.check_circle_outline,
              color: successColor,
              value: '$activeCount',
              label: 'Active',
              selected: _categoryFilter == CategoryFilter.active,
              onTap: () =>
                  setState(() => _categoryFilter = CategoryFilter.active),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: SummaryStatCard(
              icon: Icons.pause_circle_outline,
              color: neutralColor,
              value: '${_categories.length - activeCount}',
              label: 'Inactive',
              selected: _categoryFilter == CategoryFilter.inactive,
              onTap: () =>
                  setState(() => _categoryFilter = CategoryFilter.inactive),
            ),
          ),
        ],
      ),
    );
  }

  /// Semantic category badge color that matches the mockup's icon badge
  /// palette. Drinks are teal, desserts/baked goods are violet, snacks are
  /// pink-red, meals/coffee are amber/orange, and generic categories are
  /// blue.
  Color _categoryBadgeColor(Category category, Brightness brightness) {
    final n = category.name.toLowerCase();
    if (n.contains('coffee')) {
      return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    }
    if (n.contains('drink') ||
        n.contains('beverage') ||
        n.contains('juice') ||
        n.contains('tea')) {
      return AppSemanticColors.resolve(AppSemanticColors.teal, brightness);
    }
    if (n.contains('dessert') ||
        n.contains('sweet') ||
        n.contains('cake') ||
        n.contains('bread') ||
        n.contains('baker')) {
      return AppSemanticColors.resolve(AppSemanticColors.violet, brightness);
    }
    if (n.contains('snack') || n.contains('merienda')) {
      return AppSemanticColors.resolve(AppSemanticColors.error, brightness);
    }
    if (n.contains('meal') ||
        n.contains('rice') ||
        n.contains('food') ||
        n.contains('ulam')) {
      return AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    }
    return AppSemanticColors.resolve(AppSemanticColors.info, brightness);
  }

  /// Best-guess icon for common category names; falls back to a label.
  IconData _categoryIcon(Category category) {
    final n = category.name.toLowerCase();
    if (n.contains('coffee')) return Icons.coffee_outlined;
    if (n.contains('drink') ||
        n.contains('beverage') ||
        n.contains('juice') ||
        n.contains('tea')) {
      return Icons.local_drink_outlined;
    }
    if (n.contains('dessert') ||
        n.contains('sweet') ||
        n.contains('cake')) {
      return Icons.cake_outlined;
    }
    if (n.contains('bread') || n.contains('baker')) {
      return Icons.bakery_dining_outlined;
    }
    if (n.contains('snack') || n.contains('merienda')) {
      return Icons.fastfood_outlined;
    }
    if (n.contains('meal') ||
        n.contains('rice') ||
        n.contains('food') ||
        n.contains('ulam')) {
      return Icons.restaurant_outlined;
    }
    return Icons.label_outline;
  }

  Widget _buildToolbar(Widget? primaryAction) {
    return CrudToolbar(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      search: AppSearchField(
        controller: _searchController,
        hint: 'Search categories...',
        onChanged: _onSearchChanged,
        onClear: _clearSearch,
      ),
      controls: [
        _buildFilterChip(CategoryFilter.all, 'All'),
        _buildFilterChip(CategoryFilter.active, 'Active'),
        _buildFilterChip(CategoryFilter.inactive, 'Inactive'),
      ],
      primaryAction: primaryAction,
    );
  }

  Widget _buildCategoryList(
    bool canEdit,
    bool canDelete,
    bool canToggleStatus,
    double bottomClearance,
  ) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + bottomClearance,
      ),
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
    final canView =
        ref.read(authStateProvider.notifier).hasPermission('view_categories');
    final count = _productCounts[category.id] ?? 0;

    final actions = <AppListAction>[
      if (canView)
        AppListAction(
          icon: Icons.visibility_outlined,
          tooltip: 'View category',
          onPressed: () => _showCategoryView(category, count),
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
      if (!canEdit && canToggleStatus)
        AppListAction(
          icon: category.isActive ? Icons.toggle_on : Icons.toggle_off,
          tooltip: category.isActive ? 'Deactivate' : 'Activate',
          color: statusColor,
          onPressed: () => _toggleCategoryStatus(category),
        ),
    ];

    final badgeColor = _categoryBadgeColor(category, Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppListItem(
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            _categoryIcon(category),
            color: badgeColor,
            size: 24,
          ),
        ),
        title: category.name,
        subtitle: '$count product${count == 1 ? '' : 's'}',
        trailing: AppStatusChip(
          label: category.isActive ? 'Active' : 'Inactive',
          color: statusColor,
        ),
        actions: actions.isNotEmpty ? actions : null,
        onTap: canView ? () => _showCategoryView(category, count) : null,
      ),
    );
  }

  Widget _buildFilterChip(CategoryFilter filter, String label) {
    final isSelected = _categoryFilter == filter;
    return FilterChip(
      label: Text(label),
      showCheckmark: false,
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _categoryFilter = filter;
        });
      },
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

  void _showCategoryView(Category category, int count) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AppDialog(
          type: AppDialogType.info,
          title: category.name,
          message: 'Category details',
          actions: [
            AppDialogAction(
              label: 'Close',
              onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _categoryBadgeColor(category, Theme.of(context).brightness)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color: _categoryBadgeColor(category, Theme.of(context).brightness),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: AppTypography.titleMediumSemibold(context),
                        ),
                        Text(
                          '$count product${count == 1 ? '' : 's'}',
                          style: AppTypography.bodySmall(context).copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppStatusChip(
                    label: category.isActive ? 'Active' : 'Inactive',
                    color: category.isActive ? cs.primary : cs.outline,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              _buildViewRow('Status', category.isActive ? 'Active' : 'Inactive'),
              _buildViewRow('Products', '$count'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMedium(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: AppTypography.titleSmall(context).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryDialog({Category? category}) async {
    final result = await showCategoryDialog(context, ref, category: category);

    if (!mounted) return;

    if (result?.isSaved ?? false) {
      await AppDialogService.success(
        context,
        title: category == null ? 'Created' : 'Updated',
        message: category == null
            ? 'Category created successfully.'
            : 'Category updated successfully.',
      );
      if (mounted) bumpCatalogRevision(ref);
    }
  }
}
