import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/ui/dialogs/license_unlock_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';
import 'package:pinoy_pos/ui/widgets/license_expiry_banner.dart';

/// Quiet "days remaining" strip shown while the developer license is
/// armed and OUTSIDE the warning window ([LicenseStatus.showCountdown]).
/// Renders nothing otherwise — once the proportional warning threshold
/// is reached, [LicenseExpiryBanner] takes over.
///
/// Mounted in the same two places as the banner: the login card
/// (pre-auth) and the top of [AppShell] (post-auth). Short terms read
/// as "Trial · N days left"; longer terms read as "License · N days
/// left". "Enter code" opens the shared unlock dialog so a code can be
/// redeemed long before the warning appears.
class LicenseCountdownChip extends ConsumerWidget {
  const LicenseCountdownChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseStatusProvider);
    if (!status.showCountdown) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final remaining = status.remaining ?? Duration.zero;

    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_top_outlined,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              '${status.isTrial ? 'Trial' : 'License'} · '
              '${LicenseExpiryBanner.formatRemaining(remaining)} left',
              style: AppTypography.bodySmall(context).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _enterCode(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
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
