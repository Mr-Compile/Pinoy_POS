import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/validators.dart';

/// Shows a reusable Add/Edit Category dialog.
///
/// Uses [CategoryService] so the validation/duplicate logic lives in the
/// service layer and is not duplicated in callers.
Future<ModalResult<void>?> showCategoryDialog(
  BuildContext context,
  WidgetRef ref, {
  Category? category,
}) {
  return showDialog<ModalResult<void>>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _CategoryDialog(category: category, ref: ref),
  );
}

class _CategoryDialog extends ConsumerWidget {
  final Category? category;
  final WidgetRef ref;

  const _CategoryDialog({this.category, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppDialogForm<ModalResult<void>>(
      type: AppDialogType.info,
      title: category == null ? 'Add Category' : 'Edit Category',
      childBuilder: (context, state) {
        final nameController = state.textController(
          'name',
          text: category?.name ?? '',
        );

        return Form(
          key: state.formKey,
          child: AppTextFormField(
            controller: nameController,
            label: 'Category Name',
            prefixIcon: Icons.category_outlined,
            textInputAction: TextInputAction.done,
            validator: (value) => Validators.required(value, 'Category name'),
            onChanged: (_) => state.markChanged(),
            onFieldSubmitted: (_) => _save(state, context),
          ),
        );
      },
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          isLoading: state.isSaving,
          onPressed: state.isSaving
              ? null
              : (context) => state.pop(const ModalResult<void>.cancelled()),
        ),
        AppDialogAction(
          label: 'Save',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving ? null : (context) => _save(state, context),
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

    final authNotifier = ref.read(authStateProvider.notifier);
    if (category == null && !authNotifier.hasPermission('edit_categories')) {
      if (dialogContext.mounted) {
        AppDialogService.accessDenied(dialogContext);
      }
      return;
    }
    if (category != null && !authNotifier.hasPermission('edit_categories')) {
      if (dialogContext.mounted) {
        AppDialogService.accessDenied(dialogContext);
      }
      return;
    }

    final name = state.textController('name').text.trim();
    final categoryService = ref.read(categoryServiceProvider);

    final existing = await categoryService.getCategoryByName(name);
    if (existing != null && (category == null || existing.id != category!.id)) {
      if (dialogContext.mounted) {
        AppDialogService.error(
          dialogContext,
          title: 'Duplicate Name',
          message: 'A category with this name already exists.',
        );
      }
      return;
    }

    state.setSaving(true);

    try {
      final categoryData = Category(
        name: name,
        createdAt: DateTime.now(),
      );

      bool success;
      if (category == null) {
        success = await categoryService.createCategory(categoryData);
      } else {
        success = await categoryService.updateCategory(
          category!.copyWith(name: categoryData.name),
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
            message: 'Could not save the category.',
          );
        }
      }
    } catch (_) {
      if (dialogContext.mounted) {
        state.setSaving(false);
        AppDialogService.error(
          dialogContext,
          title: 'Save Failed',
          message: 'Could not save the category.',
        );
      }
    }
  }
}
