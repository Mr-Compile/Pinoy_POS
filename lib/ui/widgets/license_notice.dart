import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/dialogs/license_unlock_dialog.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog_service.dart';

/// Severity of the [LicenseNotice] strip, driven by how much of the
/// armed term is left.
enum LicenseNoticeTier {
  /// Outside the warning window — quiet grey countdown.
  calm,

  /// Inside the proportional warning window — amber warning.
  warn,

  /// Inside [LicenseService.criticalWindow] (last 48h) — red alarm.
  critical,
}

/// The single license-countdown strip for the whole app, replacing the
/// old separate calm countdown chip and warning banner. It escalates
/// through three tiers as the deadline approaches:
///
/// - [LicenseNoticeTier.calm] — grey `N days left` strip while the term
///   is comfortably ahead ([LicenseStatus.showCountdown]).
/// - [LicenseNoticeTier.warn] — amber `expires in N days` strip inside
///   the proportional warning window ([LicenseStatus.isExpiringSoon]).
/// - [LicenseNoticeTier.critical] — red `locks in N hours` strip for the
///   final 48 hours ([LicenseStatus.isCritical]), with the developer
///   contact inline.
///
/// Renders nothing when the license is not armed, expired (the lock
/// screen takes over) or still evaluating. Mounted at the top of the
/// login page (pre-auth) and the top of [AppShell] (post-auth) so every
/// role sees the countdown before the lock engages. "Enter code" opens
/// the shared unlock dialog; a successful redemption refreshes the
/// status provider and the strip settles back to calm on its own.
class LicenseNotice extends ConsumerWidget {
  const LicenseNotice({super.key});

  static String formatRemaining(Duration remaining) {
    final days = remaining.inDays;
    if (days >= 2) return '$days days';
    if (days == 1) return '1 day';
    final hours = remaining.inHours;
    if (hours >= 2) return '$hours hours';
    if (hours == 1) return '1 hour';
    return 'less than an hour';
  }

  /// Resolves the current severity tier for [status], or `null` when the
  /// strip should render nothing.
  static LicenseNoticeTier? tierFor(LicenseStatus status) {
    if (status.isCritical) return LicenseNoticeTier.critical;
    if (status.isExpiringSoon) return LicenseNoticeTier.warn;
    if (status.showCountdown) return LicenseNoticeTier.calm;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseStatusProvider);
    final tier = tierFor(status);
    if (tier == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final remaining = status.remaining ?? Duration.zero;
    final label = status.isTrial ? 'Trial' : 'License';

    final Color container;
    final Color accent;
    final Color onContainer;
    final IconData icon;
    final String title;
    final String sub;
    switch (tier) {
      case LicenseNoticeTier.calm:
        container = cs.surfaceContainerHigh;
        accent = cs.onSurfaceVariant;
        onContainer = cs.onSurfaceVariant;
        icon = Icons.hourglass_top_outlined;
        title = '$label · ${formatRemaining(remaining)} left';
        final deadline = status.expiresAt;
        sub = deadline == null
            ? 'Enter a code to extend'
            : 'Renews ${DateFormat('MMM d, h:mm a').format(deadline)}';
      case LicenseNoticeTier.warn:
        container = AppSemanticColors.resolve(
          AppSemanticColors.warningContainer,
          brightness,
        );
        accent = AppSemanticColors.resolve(
          AppSemanticColors.warning,
          brightness,
        );
        onContainer = AppSemanticColors.resolve(
          AppSemanticColors.onWarningContainer,
          brightness,
        );
        icon = Icons.schedule_outlined;
        title = '$label expires in ${formatRemaining(remaining)}';
        final deadline = status.expiresAt;
        sub = deadline == null
            ? 'Enter a code to extend'
            : 'Locks ${DateFormat('MMM d, h:mm a').format(deadline)} · '
                  'Enter a code to extend';
      case LicenseNoticeTier.critical:
        container = AppSemanticColors.resolve(
          AppSemanticColors.errorContainer,
          brightness,
        );
        accent = AppSemanticColors.resolve(AppSemanticColors.error, brightness);
        onContainer = AppSemanticColors.resolve(
          AppSemanticColors.onErrorContainer,
          brightness,
        );
        icon = Icons.alarm;
        title = '$label locks in ${formatRemaining(remaining)}';
        final contact = status.contactInfo.isNotEmpty
            ? status.contactInfo
            : 'your developer';
        sub = '${_deadlineLabel(status)} · Enter a code or contact $contact';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: container,
        border: tier == LicenseNoticeTier.calm
            ? null
            : Border(left: BorderSide(color: accent, width: 4)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmallSemibold(
                    context,
                  ).copyWith(color: onContainer),
                ),
                Text(
                  sub,
                  style: AppTypography.bodySmall(
                    context,
                  ).copyWith(color: onContainer.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _noticeButton(tier, accent, () => _enterCode(context, ref)),
        ],
      ),
    );
  }

  /// Short deadline phrasing for the critical tier: `Today, 2:30 PM`,
  /// `Tomorrow, 2:30 PM`, or the date for anything further out.
  static String _deadlineLabel(LicenseStatus status) {
    final deadline = status.expiresAt;
    if (deadline == null) return 'Soon';
    final now = status.effectiveNow;
    final time = DateFormat('h:mm a').format(deadline);
    if (deadline.year == now.year &&
        deadline.month == now.month &&
        deadline.day == now.day) {
      return 'Today, $time';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (deadline.year == tomorrow.year &&
        deadline.month == tomorrow.month &&
        deadline.day == tomorrow.day) {
      return 'Tomorrow, $time';
    }
    return DateFormat('MMM d, h:mm a').format(deadline);
  }

  static Widget _noticeButton(
    LicenseNoticeTier tier,
    Color accent,
    VoidCallback onPressed,
  ) {
    const padding = EdgeInsets.symmetric(horizontal: 14);
    const minimumSize = Size(0, 40);
    const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    if (tier == LicenseNoticeTier.calm) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
          padding: padding,
          minimumSize: minimumSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: textStyle,
        ),
        child: const Text('Enter code'),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: padding,
        minimumSize: minimumSize,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: textStyle,
      ),
      child: const Text('Enter code'),
    );
  }

  /// Shared unlock-code flow used by the notice strip, the owner license
  /// status page and the Settings "Unlock Code" tile — opens the shared
  /// dialog, refreshes the status provider on success and shows the
  /// extended-until confirmation.
  static Future<void> enterCode(BuildContext context, WidgetRef ref) async {
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

  Future<void> _enterCode(BuildContext context, WidgetRef ref) =>
      enterCode(context, ref);
}
