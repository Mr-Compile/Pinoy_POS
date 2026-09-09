import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_quota_service.dart';
import 'package:pinoy_pos/services/super_admin_verification_service.dart';
import 'package:pinoy_pos/services/user_service.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';
import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';

/// Admin page for managing per-user AI quotas and the default daily quota.
///
/// The SuperAdmin password is verified once when the page is opened. All
/// privileged actions inside the page reuse that verification and do not ask
/// for the password again. The password itself is never persisted, logged, or
/// exposed beyond the verification dialog.
class AIQuotaManagementPage extends StatefulWidget {
  final bool verified;

  const AIQuotaManagementPage({super.key, this.verified = false});

  @override
  State<AIQuotaManagementPage> createState() => _AIQuotaManagementPageState();
}

class _AIQuotaManagementPageState extends State<AIQuotaManagementPage> {
  final AIQuotaService _aiQuotaService = AIQuotaService();
  final UserService _userService = UserService();

  List<User> _users = [];
  Map<int, AIQuota> _quotas = {};
  int _defaultQuota = 0;
  bool _isLoading = true;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _isVerified = widget.verified;
    if (_isVerified) {
      _loadData();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyOnEntry());
    }
  }

  Future<void> _verifyOnEntry() async {
    final result = await showSuperAdminVerificationDialog(context);

    if (result == true) {
      if (mounted) {
        setState(() => _isVerified = true);
      }
      await _loadData();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final users = await _userService.getAllUsers();
    final defaultQuota = await _aiQuotaService.getDefaultQuota();
    final quotas = <int, AIQuota>{};

    for (final user in users) {
      if (user.id == null) continue;
      final quota = await _aiQuotaService.getQuotaForUser(user.id!);
      quotas[user.id!] = quota;
    }

    if (mounted) {
      setState(() {
        _users = users;
        _quotas = quotas;
        _defaultQuota = defaultQuota;
        _isLoading = false;
      });
    }
  }

  Future<void> _changeDefaultQuota() async {
    final result =
        await showDialog<ModalResult<({int value, bool applyToExisting})>>(
      context: context,
      useRootNavigator: true,
      builder: (context) =>
          AppDialogForm<ModalResult<({int value, bool applyToExisting})>>(
        type: AppDialogType.edit,
        title: 'Change Default AI Quota',
        childBuilder: (context, state) {
          final controller =
              state.textController('quota', text: _defaultQuota.toString());
          final applyToExisting =
              state.value<bool>('applyToExisting', false);

          return Form(
            key: state.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  label: 'New default daily quota',
                  prefixIcon: Icons.auto_awesome,
                  helperText: 'Applies to new users unless overridden',
                ),
                const SizedBox(height: Spacing.sm),
                CheckboxListTile(
                  title: const Text('Apply to all existing users'),
                  value: applyToExisting,
                  onChanged: (value) {
                    state.setValue<bool>('applyToExisting', value ?? false);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) => state.pop(
              const ModalResult<({int value, bool applyToExisting})>
                  .cancelled(),
            ),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            onPressed: (context) {
              final value =
                  int.tryParse(state.textController('quota').text.trim());
              if (value == null) return;

              state.pop(
                ModalResult<({int value, bool applyToExisting})>.saved(
                  (
                    value: value,
                    applyToExisting:
                        state.value<bool>('applyToExisting') ?? false,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result case final saved? when saved.isSaved) {
      final (:value, :applyToExisting) = saved.value!;
      final serviceResult = await _aiQuotaService.setDefaultQuota(
        value: value,
        applyToExisting: applyToExisting,
        verified: _isVerified,
      );

      if (!mounted) return;

      if (serviceResult.success) {
        await _loadData();
        if (mounted) {
          _showSnackBar('Default quota updated to $value');
        }
      } else {
        _showErrorSnackBar(serviceResult.message);
      }
    }
  }

  Future<void> _editUserQuota(User user) async {
    final quota = _quotas[user.id!];

    final result = await showDialog<ModalResult<int>>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AppDialogForm<ModalResult<int>>(
        type: AppDialogType.edit,
        title: 'Edit Quota for ${user.fullName}',
        childBuilder: (context, state) {
          final controller = state.textController(
            'quota',
            text: (quota?.dailyQuota ?? _defaultQuota).toString(),
          );

          return Form(
            key: state.formKey,
            child: AppTextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              label: 'Daily quota',
              prefixIcon: Icons.auto_awesome,
            ),
          );
        },
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: (context) => state.pop(
              const ModalResult<int>.cancelled(),
            ),
          ),
          AppDialogAction(
            label: 'Save',
            isPrimary: true,
            onPressed: (context) {
              final value =
                  int.tryParse(state.textController('quota').text.trim());
              if (value == null) return;

              state.pop(ModalResult<int>.saved(value));
            },
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (user.id == null) return;

    if (result case final saved? when saved.isSaved) {
      final value = saved.value!;
      final serviceResult = await _aiQuotaService.updateUserQuota(
        user.id!,
        value: value,
        verified: _isVerified,
      );

      if (!mounted) return;

      if (serviceResult.success) {
        await _loadData();
        if (mounted) {
          _showSnackBar('Quota for ${user.fullName} updated to $value');
        }
      } else {
        _showErrorSnackBar(serviceResult.message);
      }
    }
  }

  Future<void> _resetUserUsage(User user) async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Reset usage for ${user.fullName}?',
      message:
          "This will reset today's AI usage to 0. The daily quota remains unchanged.",
      confirmLabel: 'Reset',
      cancelLabel: 'Cancel',
    );

    if (confirmed != true || user.id == null) return;

    final result = await _aiQuotaService.resetUserUsage(
      user.id!,
      verified: _isVerified,
    );

    if (!mounted) return;

    if (result.success) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Usage reset for ${user.fullName}');
      }
    } else {
      _showErrorSnackBar(result.message);
    }
  }

  Future<void> _resetAllUsage() async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: "Reset all users' usage?",
      message:
          "This will reset today's AI usage to 0 for every active user.",
      confirmLabel: 'Reset All',
      cancelLabel: 'Cancel',
    );

    if (confirmed != true) return;

    final result = await _aiQuotaService.resetAllUserUsage(verified: _isVerified);

    if (!mounted) return;

    if (result.success) {
      await _loadData();
      if (mounted) {
        _showSnackBar(result.message);
      }
    } else {
      _showErrorSnackBar(result.message);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final totalUsers = _users.length;
    final totalRemaining = _quotas.values.fold<int>(
      0,
      (sum, q) => sum + (q.dailyQuota - q.dailyUsage).clamp(0, q.dailyQuota),
    );

    // Page-level primary action: FAB on compact portrait, toolbar button
    // in the content area on every other layout.
    final resetAction = ResponsiveCreateAction(
      label: 'Reset All Usage',
      icon: Icons.restart_alt,
      onPressed: _isLoading ? null : _resetAllUsage,
      color: AppButtonColor.warning,
      tooltip: "Reset all users' usage",
    );

    return Scaffold(
      appBar: const AppHeader(title: 'AI Quota Management'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'Default Quota',
                                  value: _defaultQuota.toString(),
                                  icon: Icons.settings_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  label: 'Total Users',
                                  value: totalUsers.toString(),
                                  icon: Icons.people_outline,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  label: 'Remaining Today',
                                  value: totalRemaining.toString(),
                                  icon: Icons.hourglass_empty,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: _changeDefaultQuota,
                                icon: const Icon(Icons.edit),
                                label: const Text('Change Default Quota'),
                              ),
                              const Spacer(),
                              ?resetAction.contentAction(context),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Per-user quotas',
                            style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = _users[index];
                        final quota = _quotas[user.id!];
                        final used = quota?.dailyUsage ?? 0;
                        final limit = quota?.dailyQuota ?? _defaultQuota;
                        final remaining = (limit - used).clamp(0, limit);

                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(user.fullName.isNotEmpty
                                ? user.fullName[0]
                                : '?'),
                          ),
                          title: Text(user.fullName),
                          subtitle: Text(
                            '${user.role.name} · $remaining / $limit remaining',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit quota',
                                onPressed: () => _editUserQuota(user),
                              ),
                              IconButton(
                                icon: const Icon(Icons.restart_alt),
                                tooltip: "Reset today's usage",
                                onPressed: () => _resetUserUsage(user),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _users.length,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),
      floatingActionButton: resetAction.fab(context),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showSuperAdminVerificationDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) => AppDialogForm<bool>(
      type: AppDialogType.confirmation,
      title: 'SuperAdmin Verification',
      message: 'Enter the SuperAdmin password to continue.',
      canPop: false,
      childBuilder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final error = state.value<String?>('error');

        return Form(
          key: state.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPasswordField(
                controller: state.textController('password'),
                label: 'Password',
                onChanged: (_) {
                  state.setValue<String?>('error', null);
                  state.markChanged();
                },
                onFieldSubmitted: (_) => _verifySuperAdmin(state),
                textInputAction: TextInputAction.done,
              ),
              if (error != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  error,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
      actionsBuilder: (context, state) => [
        AppDialogAction(
          label: 'Cancel',
          onPressed: state.isSaving
              ? null
              : (context) => state.pop(false),
        ),
        AppDialogAction(
          label: 'Verify',
          isPrimary: true,
          isLoading: state.isSaving,
          onPressed: state.isSaving ? null : (context) => _verifySuperAdmin(state),
        ),
      ],
    ),
  ).then((result) => result ?? false);
}

void _verifySuperAdmin(AppDialogFormState<bool> state) {
  final password = state.textController('password').text;
  final isValid = SuperAdminVerificationService()
      .verifySuperAdminPassword(password);

  if (isValid) {
    state.pop(true);
  } else {
    state.setValue<String?>('error', 'Incorrect SuperAdmin password');
  }
}
