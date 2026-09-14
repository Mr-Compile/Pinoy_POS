import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/ui/dialogs/license_unlock_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Slim warning strip shown while the developer license is armed and
/// inside the proportional warning window ([LicenseStatus.isExpiringSoon]
/// — a quarter of the term, capped at [LicenseService.warningWindow]).
/// Renders nothing otherwise; before that point [LicenseCountdownChip]
/// carries the quiet countdown instead.
///
/// Mounted in two places: the login card (pre-auth) and the top of
/// [AppShell] (post-auth), so every role sees the countdown before the
/// lock engages. "Enter code" opens the shared unlock dialog; a
/// successful redemption refreshes the status provider and the banner
/// disappears on its own.
class LicenseExpiryBanner extends ConsumerWidget {
  const LicenseExpiryBanner({super.key});

  static String formatRemaining(Duration remaining) {
    final days = remaining.inDays;
    if (days >= 2) return '$days days';
    if (days == 1) return '1 day';
    final hours = remaining.inHours;
    if (hours >= 2) return '$hours hours';
    if (hours == 1) return '1 hour';
    return 'less than an hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseStatusProvider);
    if (!status.isExpiringSoon) return const SizedBox.shrink();

    final brightness = Theme.of(context).brightness;
    final warning = AppSemanticColors.resolve(
      AppSemanticColors.warning,
      brightness,
    );
    final container = AppSemanticColors.resolve(
      AppSemanticColors.warningContainer,
      brightness,
    );
    final onContainer = AppSemanticColors.resolve(
      AppSemanticColors.onWarningContainer,
      brightness,
    );
    final remaining = status.remaining ?? Duration.zero;
    final deadline = status.expiresAt == null
        ? null
        : DateFormat('MMM d, h:mm a').format(status.expiresAt!);
    final label = status.isTrial ? 'Trial' : 'License';

    return Container(
      width: double.infinity,
      color: container,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: warning),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              deadline == null
                  ? '$label expires in ${formatRemaining(remaining)}. '
                      'Please contact your developer.'
                  : '$label expires in ${formatRemaining(remaining)} '
                      '($deadline). Please contact your developer.',
              style: AppTypography.bodySmall(context).copyWith(
                color: onContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _enterCode(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: warning,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Enter code'),
          ),
        ],
      ),
    );
  }

  Future<void> _enterCode(BuildContext context, WidgetRef ref) async {
    final result = await showLicenseUnlockDialog(
      context,
      ref.read(licenseServiceProvider),
    );
    if (result == null || !context.mounted) return;

    await ref.read(licenseStatusProvider.notifier).refresh();
    if (!context.mounted) return;
    await AppDialogService.success(
      context,
      title: 'License Extended',
      message:
          'The license now runs until '
          '${DateFormat('MMM d, yyyy').format(result.newExpiry!)}.',
    );
  }
}
