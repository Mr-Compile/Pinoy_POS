import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/modal_result.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_form.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Hidden developer panel for the license lock.
///
/// Reachable only after [showDeveloperAccessDialog] succeeds (7-tap logo
/// gesture on the login screen, or "Developer access" on the lock screen).
/// Everything on this page maps directly to [LicenseService] — arming the
/// license, setting the deadline, the lock-screen message/contact, and the
/// offline unlock codes.
class DeveloperLicenseScreen extends ConsumerStatefulWidget {
  const DeveloperLicenseScreen({super.key});

  @override
  ConsumerState<DeveloperLicenseScreen> createState() =>
      _DeveloperLicenseScreenState();
}

class _DeveloperLicenseScreenState
    extends ConsumerState<DeveloperLicenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _contactController = TextEditingController();

  bool _armed = false;
  DateTime? _expiry;
  bool _saving = false;
  bool _populated = false;

  @override
  void dispose() {
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _populate(LicenseStatus status) {
    if (_populated) return;
    _populated = true;
    _armed = status.state == LicenseLockState.active ||
        status.state == LicenseLockState.expired;
    _expiry = status.expiresAt;
    _messageController.text = status.message.isEmpty
        ? LicenseService.defaultLockMessage
        : status.message;
    _contactController.text = status.contactInfo;
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider);
    if (!status.isEvaluating) _populate(status);

    return Scaffold(
      appBar: const AppHeader(
        title: 'License Control',
        showBackButton: true,
        showNotificationBell: false,
        showProfileMenu: false,
      ),
      body: status.isEvaluating
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusCard(status),
                        const SizedBox(height: Spacing.lg),
                        _buildConfigCard(status),
                        const SizedBox(height: Spacing.lg),
                        _buildUnlockCodesCard(status),
                        const SizedBox(height: Spacing.lg),
                        _buildSecurityCard(),
                        const SizedBox(height: Spacing.lg),
                        AppButton.gradient(
                          label: 'Save License Settings',
                          icon: Icons.save_outlined,
                          fullWidth: true,
                          isLoading: _saving,
                          onPressed: _save,
                        ),
                        const SizedBox(height: Spacing.md),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Status ───────────────────────────────────────────────────────────

  Widget _buildStatusCard(LicenseStatus status) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final (label, color, icon) = switch (status.state) {
      LicenseLockState.active => (
          'Armed — license is valid',
          AppSemanticColors.resolve(AppSemanticColors.success, brightness),
          Icons.check_circle_outline,
        ),
      LicenseLockState.expired => (
          'Expired — app is locked',
          AppSemanticColors.resolve(AppSemanticColors.error, brightness),
          Icons.lock_outline,
        ),
      LicenseLockState.tampered => (
          'Integrity check failed — app is locked',
          AppSemanticColors.resolve(AppSemanticColors.error, brightness),
          Icons.gpp_bad_outlined,
        ),
      LicenseLockState.inactive => (
          'Configured — not armed',
          AppSemanticColors.resolve(AppSemanticColors.neutral, brightness),
          Icons.pause_circle_outline,
        ),
      _ => (
          'Not configured',
          cs.onSurfaceVariant,
          Icons.info_outline,
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.titleMediumSemibold(context)
                      .copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _infoRow(
            context,
            'Deadline',
            status.expiresAt == null
                ? 'Not set'
                : DateFormat('MMM d, yyyy · h:mm a').format(status.expiresAt!),
          ),
          _infoRow(
            context,
            'Time remaining',
            _formatRemaining(status.remaining),
          ),
          _infoRow(
            context,
            'Warning window',
            _formatWarningWindow(status),
          ),
          _infoRow(
            context,
            'Effective device time',
            DateFormat('MMM d, yyyy · h:mm a').format(status.effectiveNow),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall(context)
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(value, style: AppTypography.bodySmallSemibold(context)),
        ],
      ),
    );
  }

  String _formatRemaining(Duration? remaining) {
    if (!_armed || _expiry == null) return '—';
    if (remaining == null || remaining <= Duration.zero) return 'Expired';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    if (days > 0) return '$days d $hours h';
    final minutes = remaining.inMinutes % 60;
    return '${remaining.inHours} h $minutes min';
  }

  String _formatWarningWindow(LicenseStatus status) {
    if (status.state != LicenseLockState.active &&
        status.state != LicenseLockState.expired) {
      return '—';
    }
    final t = status.warningThreshold;
    if (t.inDays >= 1) {
      return 'Last ${t.inDays} day${t.inDays == 1 ? '' : 's'} of the term';
    }
    return 'Last ${t.inHours} h of the term';
  }

  // ── Configuration ────────────────────────────────────────────────────

  Widget _buildConfigCard(LicenseStatus status) {
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('License enforcement'),
            subtitle: Text(
              _armed
                  ? 'The app locks when the deadline passes.'
                  : 'Off — the app runs without a deadline.',
            ),
            value: _armed,
            onChanged: (value) => setState(() => _armed = value),
          ),
          const Divider(height: Spacing.xl),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Deadline'),
            subtitle: Text(
              _expiry == null
                  ? 'Tap to choose date and time'
                  : DateFormat('MMM d, yyyy · h:mm a').format(_expiry!),
            ),
            trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onTap: _pickDeadline,
          ),
          const SizedBox(height: Spacing.md),
          AppTextFormField(
            controller: _messageController,
            label: 'Lock screen message',
            hint:
                'e.g. Please settle the remaining balance to reactivate the system.',
            maxLines: 2,
          ),
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final (label, text) in LicenseService.lockMessagePresets)
                ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      setState(() => _messageController.text = text),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          AppTextFormField(
            controller: _contactController,
            label: 'Developer contact',
            hint: 'e.g. Juan Dela Cruz · 0917 000 0000',
            prefixIcon: Icons.contact_phone_outlined,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final base = _expiry ?? now.add(const Duration(days: 30));

    final date = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _expiry == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_expiry!),
    );
    if (time == null || !mounted) return;

    setState(() {
      _expiry = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  // ── Unlock codes ─────────────────────────────────────────────────────

  Widget _buildUnlockCodesCard(LicenseStatus status) {
    final cs = Theme.of(context).colorScheme;
    final service = ref.read(licenseServiceProvider);
    final usedCount = status.redeemedCodes.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock codes',
            style: AppTypography.titleSmallBold(context),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Dictate a code to the client when they pay — hand out a '
            'different one per client. Each code works once on this '
            'device. Codes stack: redeeming before the deadline extends '
            'from it, never losing the remaining days. No internet needed.',
            style: AppTypography.bodySmall(context)
                .copyWith(color: cs.onSurfaceVariant),
          ),
          if (usedCount > 0) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              '$usedCount code${usedCount == 1 ? '' : 's'} already '
              'redeemed on this device.',
              style: AppTypography.bodySmall(context)
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          for (final grant in LicenseService.unlockGrants.entries)
            _buildGrantGroup(grant.key, grant.value, service, status),
        ],
      ),
    );
  }

  static String _grantLabel(int days) => switch (days) {
        30 => '1 month',
        90 => '3 months',
        365 => '1 year',
        _ => '$days days',
      };

  Widget _buildGrantGroup(
    int days,
    int count,
    LicenseService service,
    LicenseStatus status,
  ) {
    final cs = Theme.of(context).colorScheme;
    final used =
        status.redeemedCodes.where((key) => key.startsWith('$days:')).length;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: Spacing.sm),
      leading: const Icon(Icons.key_outlined),
      title: Text(
        _grantLabel(days),
        style: AppTypography.bodyMediumSemibold(context),
      ),
      subtitle: Text(
        used == 0
            ? '$count codes · extends by $days days'
            : '$count codes · $used used · extends by $days days',
        style: AppTypography.bodySmall(context)
            .copyWith(color: cs.onSurfaceVariant),
      ),
      children: [
        for (var i = 0; i < count; i++)
          _buildCodeTile(days, i, service, status),
      ],
    );
  }

  Widget _buildCodeTile(
    int days,
    int index,
    LicenseService service,
    LicenseStatus status,
  ) {
    final cs = Theme.of(context).colorScheme;
    final used = status.isCodeRedeemed(days, index);
    final code = service.unlockCode(days, index);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: Spacing.lg),
      title: Text(
        code,
        style: AppTypography.bodyMediumSemibold(context).copyWith(
          letterSpacing: 2,
          color: used ? cs.onSurfaceVariant : null,
          decoration: used ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: used ? const Text('Already redeemed') : null,
      trailing: used
          ? null
          : IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copy code',
              onPressed: () => _copyCode(code),
            ),
      onTap: used ? null : () => _copyCode(code),
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    await AppDialogService.success(
      context,
      title: 'Copied',
      message: '$code copied to clipboard.',
    );
  }

  // ── Security / danger ────────────────────────────────────────────────

  Widget _buildSecurityCard() {
    return AppCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Change developer password'),
            subtitle:
                const Text('Required to open this panel and unlock on-site'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePassword,
          ),
          const Divider(height: Spacing.xl),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.verified_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'License paid in full',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text(
              'Removes the license entirely — no deadline, codes or '
              'developer password. The app runs without restrictions.',
            ),
            onTap: _clearConfiguration,
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final service = ref.read(licenseServiceProvider);

    final result = await showDialog<ModalResult<void>>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (_) => AppDialogForm<ModalResult<void>>(
        type: AppDialogType.edit,
        title: 'Change Developer Password',
        showClose: false,
        childBuilder: (context, state) => Form(
          key: state.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPasswordField(
                controller: state.textController('current'),
                label: 'Current password',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter the current password' : null,
                onChanged: (_) => state.markChanged(),
              ),
              const SizedBox(height: Spacing.md),
              AppPasswordField(
                controller: state.textController('next'),
                label: 'New password',
                hint: 'At least 6 characters',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.length < 6)
                    ? 'Password must be at least 6 characters'
                    : null,
                onChanged: (_) => state.markChanged(),
              ),
              const SizedBox(height: Spacing.md),
              AppPasswordField(
                controller: state.textController('confirm'),
                label: 'Confirm new password',
                prefixIcon: Icons.lock_outline,
                textInputAction: TextInputAction.done,
                validator: (v) => v != state.textController('next').text
                    ? 'Passwords do not match'
                    : null,
                onChanged: (_) => state.markChanged(),
              ),
              if (state.value<String>('error') != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  state.value<String>('error')!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall(context).copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsBuilder: (context, state) => [
          AppDialogAction(
            label: 'Cancel',
            onPressed: state.isSaving
                ? null
                : (context) => state.pop(const ModalResult<void>.cancelled()),
          ),
          AppDialogAction(
            label: 'Change',
            isPrimary: true,
            isLoading: state.isSaving,
            onPressed: state.isSaving
                ? null
                : (context) async {
                    if (!state.formKey.currentState!.validate()) return;
                    state.setSaving(true);
                    final response = await service.changeDeveloperPassword(
                      state.textController('current').text,
                      state.textController('next').text,
                    );
                    if (response.isOk) {
                      state.pop(const ModalResult<void>.saved(null));
                    } else {
                      state.setSaving(false);
                      state.setValue<String>(
                        'error',
                        response.result == DevAuthResult.lockedOut
                            ? 'Too many attempts. Try again later.'
                            : 'Current password is incorrect.',
                      );
                    }
                  },
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result?.isSaved ?? false) {
      await AppDialogService.success(
        context,
        title: 'Password Updated',
        message: 'The developer password has been changed.',
      );
    }
  }

  Future<void> _clearConfiguration() async {
    final confirmed = await AppDialogService.confirmation(
      context,
      title: 'Remove License Entirely?',
      message:
          'Use this when the client has paid in full. It removes the '
          'deadline, developer password and all unlock state — the app '
          'behaves like a fresh install with no license requirement.',
      confirmLabel: 'Remove License',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    await ref.read(licenseServiceProvider).clearConfiguration();
    await ref.read(licenseStatusProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _populated = false;
      _armed = false;
      _expiry = null;
      _messageController.clear();
      _contactController.clear();
    });
    await AppDialogService.success(
      context,
      title: 'Cleared',
      message: 'License configuration has been removed.',
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_armed && _expiry == null) {
      await AppDialogService.validation(
        context,
        title: 'Deadline Required',
        message: 'Choose a deadline before arming the license.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final status = await ref.read(licenseServiceProvider).saveConfig(
            armed: _armed,
            expiresAt: _expiry,
            message: _messageController.text,
            contactInfo: _contactController.text,
          );
      ref.read(licenseStatusProvider.notifier).applyStatus(status);
      if (!mounted) return;
      await AppDialogService.success(
        context,
        title: 'Saved',
        message: _armed
            ? 'License enforcement is armed until '
                '${DateFormat('MMM d, yyyy · h:mm a').format(_expiry!)}.'
            : 'License enforcement is off.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
