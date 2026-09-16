import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/providers/license_provider.dart';
import 'package:pinoy_pos/services/license_service.dart';
import 'package:pinoy_pos/ui/screens/access_denied_screen.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/empty_state.dart';
import 'package:pinoy_pos/ui/widgets/license_notice.dart';

/// Owner-facing, read-only view of the developer license.
///
/// Reached from Settings → System / Management → License. The tile is
/// gated by [SessionManager.canEditBusinessSettings] (Owner only); this
/// screen double-checks in case it is ever pushed directly.
///
/// Shows the armed term, days remaining and the deadline. The signed
/// activity log recorded inside the license blob is developer-only — it
/// surfaces in the hidden developer panel, never here, so the owner
/// cannot track the developer's actions.
///
/// Enforcement controls (arm/disarm, deadline, developer password) stay
/// in the hidden developer panel — the only action available here is
/// redeeming an unlock code.
class LicenseStatusScreen extends ConsumerWidget {
  const LicenseStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!SessionManager().canEditBusinessSettings()) {
      return const AccessDeniedScreen();
    }
    final status = ref.watch(licenseStatusProvider);

    return Scaffold(
      appBar: const AppHeader(title: 'License', showBackButton: true),
      body: switch (status.state) {
        LicenseLockState.evaluating => const Center(
          child: CircularProgressIndicator(),
        ),
        LicenseLockState.notConfigured => const EmptyState(
          icon: Icons.verified_user_outlined,
          title: 'No license configured',
          message:
              'No developer license has been set on this device. '
              'The app runs without restrictions.',
        ),
        _ => _buildBody(context, ref, status),
      },
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, LicenseStatus status) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(context, ref, status),
          ],
        ),
      ),
    );
  }

  // ── Status card ──────────────────────────────────────────────────────

  Widget _statusCard(
    BuildContext context,
    WidgetRef ref,
    LicenseStatus status,
  ) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final remaining = status.remaining;

    final (pillLabel, accent) = switch (status.state) {
      LicenseLockState.active =>
        status.isCritical
            ? ('Locks soon', AppSemanticColors.error)
            : status.isExpiringSoon
            ? ('Expiring soon', AppSemanticColors.warning)
            : ('Active', AppSemanticColors.success),
      LicenseLockState.expired => ('Expired — locked', AppSemanticColors.error),
      LicenseLockState.tampered => (
        'Integrity check failed',
        AppSemanticColors.error,
      ),
      _ => ('Enforcement off', AppSemanticColors.neutral),
    };
    final accentColor = AppSemanticColors.resolve(accent, brightness);

    final headline = switch (status.state) {
      LicenseLockState.active => LicenseNotice.formatRemaining(
        remaining ?? Duration.zero,
      ),
      LicenseLockState.expired => 'Expired',
      LicenseLockState.tampered => 'Locked',
      _ => 'Not armed',
    };

    final term = status.totalTerm;
    final progress = term != null && term.inMilliseconds > 0
        ? ((remaining ?? Duration.zero).inMilliseconds / term.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    final urgent = status.isCritical || status.isLocked;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pillLabel,
                  style: AppTypography.labelSmall(
                    context,
                  ).copyWith(color: accentColor, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              if (status.state == LicenseLockState.active)
                Text(
                  status.isTrial ? 'TRIAL' : 'LICENSE',
                  style: AppTypography.labelSmall(
                    context,
                  ).copyWith(color: cs.onSurfaceVariant, letterSpacing: 1),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(headline, style: AppTypography.headlineSmallBold(context)),
          if (status.state == LicenseLockState.active)
            Text(
              'remaining',
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: Spacing.sm),
          if (term != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.state == LicenseLockState.active ? progress : 0.0,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: accentColor,
              ),
            )
          else
            Text(
              status.state == LicenseLockState.inactive
                  ? 'Enforcement is off — the app runs without restrictions.'
                  : status.message.isNotEmpty
                  ? status.message
                  : 'License state could not be verified.',
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: Spacing.md),
          const Divider(height: 1),
          const SizedBox(height: Spacing.sm),
          _infoRow(
            context,
            'Deadline',
            status.expiresAt == null
                ? 'Not set'
                : DateFormat('MMM d, yyyy · h:mm a').format(status.expiresAt!),
          ),
          _infoRow(
            context,
            'Armed since',
            status.armedAt == null
                ? '—'
                : DateFormat('MMM d, yyyy').format(status.armedAt!),
          ),
          if (status.state == LicenseLockState.active)
            _infoRow(
              context,
              'Warning window',
              'Last ${LicenseNotice.formatRemaining(status.warningThreshold)} '
                  'of the term',
            ),
          _infoRow(
            context,
            'Developer contact',
            status.contactInfo.isNotEmpty ? status.contactInfo : '—',
          ),
          if (status.state == LicenseLockState.active || status.isLocked) ...[
            const SizedBox(height: Spacing.md),
            urgent
                ? AppButton.filled(
                    label: 'Enter unlock code',
                    icon: Icons.key_outlined,
                    fullWidth: true,
                    onPressed: () => LicenseNotice.enterCode(context, ref),
                  )
                : AppButton.outlined(
                    label: 'Enter unlock code',
                    icon: Icons.key_outlined,
                    color: AppButtonColor.neutral,
                    fullWidth: true,
                    onPressed: () => LicenseNotice.enterCode(context, ref),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: AppTypography.bodySmall(
                context,
              ).copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmallSemibold(context),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

}
