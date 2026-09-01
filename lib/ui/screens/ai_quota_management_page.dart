import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/data/models/ai_quota.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/services/ai_quota_service.dart';
import 'package:pinoy_pos/services/super_admin_verification_service.dart';
import 'package:pinoy_pos/services/user_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';

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
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => const SuperAdminVerificationDialog(),
    );

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
    final controller = TextEditingController(text: _defaultQuota.toString());
    var applyToExisting = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            icon: const Icon(Icons.settings_outlined),
            iconColor: AppSemanticColors.info,
            title: const Text('Change Default AI Quota'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'New default daily quota',
                    helperText: 'Applies to new users unless overridden',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Apply to all existing users'),
                  value: applyToExisting,
                  onChanged: (value) {
                    setDialogState(() => applyToExisting = value ?? false);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    final value = int.tryParse(controller.text.trim());
    if (value == null) return;

    final result = await _aiQuotaService.setDefaultQuota(
      value: value,
      applyToExisting: applyToExisting,
      verified: _isVerified,
    );

    if (!mounted) return;

    if (result.success) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Default quota updated to $value');
      }
    } else {
      _showErrorSnackBar(result.message);
    }
  }

  Future<void> _editUserQuota(User user) async {
    final quota = _quotas[user.id!];
    final controller =
        TextEditingController(text: (quota?.dailyQuota ?? _defaultQuota).toString());

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_outline),
        iconColor: AppSemanticColors.info,
        title: Text('Edit Quota for ${user.fullName}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Daily quota',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final value = int.tryParse(controller.text.trim());
    if (value == null || user.id == null) return;

    final result = await _aiQuotaService.updateUserQuota(
      user.id!,
      value: value,
      verified: _isVerified,
    );

    if (!mounted) return;

    if (result.success) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Quota for ${user.fullName} updated to $value');
      }
    } else {
      _showErrorSnackBar(result.message);
    }
  }

  Future<void> _resetUserUsage(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt),
        iconColor: AppSemanticColors.warning,
        title: Text('Reset usage for ${user.fullName}?'),
        content: const Text(
          "This will reset today's AI usage to 0. The daily quota remains unchanged.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt),
        iconColor: AppSemanticColors.warning,
        title: const Text("Reset all users' usage?"),
        content: const Text(
          "This will reset today's AI usage to 0 for every active user.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset All'),
          ),
        ],
      ),
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
                          FilledButton.icon(
                            onPressed: _changeDefaultQuota,
                            icon: const Icon(Icons.edit),
                            label: const Text('Change Default Quota'),
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
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _resetAllUsage,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset All Usage'),
            ),
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

class SuperAdminVerificationDialog extends StatefulWidget {
  const SuperAdminVerificationDialog({super.key});

  @override
  State<SuperAdminVerificationDialog> createState() =>
      _SuperAdminVerificationDialogState();
}

class _SuperAdminVerificationDialogState
    extends State<SuperAdminVerificationDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _errorText;

  void _verify() {
    final password = _controller.text;
    final isValid = SuperAdminVerificationService()
        .verifySuperAdminPassword(password);

    if (isValid) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errorText = 'Incorrect SuperAdmin password');
    }
  }

  void _clearError() {
    if (_errorText != null) setState(() => _errorText = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      iconColor: AppSemanticColors.warning,
      title: const Text('SuperAdmin Verification'),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _verify(),
        onChanged: (_) => _clearError(),
        decoration: InputDecoration(
          labelText: 'SuperAdmin password',
          errorText: _errorText,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _verify,
          child: const Text('Verify'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
