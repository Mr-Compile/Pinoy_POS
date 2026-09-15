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
/// Shows the armed term, days remaining, the deadline and the signed
/// recent-activity log recorded inside the license blob itself — so it
/// survives sign-outs and stays tamper-evident. Warning-window and
/// expiry rows are derived from the deadline at display time and are
/// never stored, so they cannot be forged by replaying an old blob.
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
            const SizedBox(height: 24),
            _activitySection(context, status),
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

  // ── Activity log ─────────────────────────────────────────────────────

  /// Stored signed events plus the derived milestones (warning window
  /// entry, expiry) — merged and sorted newest first.
  List<LicenseEvent> _activityFor(LicenseStatus status) {
    final events = List<LicenseEvent>.of(status.events);
    final expiresAt = status.expiresAt;
    if (expiresAt != null) {
      final warnAt = expiresAt.subtract(status.warningThreshold);
      if (!warnAt.isAfter(status.effectiveNow) &&
          status.state != LicenseLockState.inactive) {
        events.add(
          LicenseEvent(
            type: LicenseEventType.warning,
            at: warnAt,
            detail:
                'Less than ${LicenseNotice.formatRemaining(status.warningThreshold)} '
                'left',
          ),
        );
      }
      if (status.state == LicenseLockState.expired) {
        events.add(
          LicenseEvent(
            type: LicenseEventType.expired,
            at: expiresAt,
            detail: 'All users signed out',
          ),
        );
      }
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    return events;
  }

  Widget _activitySection(BuildContext context, LicenseStatus status) {
    final cs = Theme.of(context).colorScheme;
    final events = _activityFor(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent activity',
          style: AppTypography.titleSmallBold(
            context,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: events.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No license activity recorded yet.',
                    style: AppTypography.bodySmall(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < events.length; i++) ...[
                      _eventRow(context, events[i]),
                      if (i < events.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Recorded inside the signed license store — entries cannot be '
          'edited without detection.',
          style: AppTypography.labelSmall(
            context,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, LicenseEvent event) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final (name, color) = switch (event.type) {
      LicenseEventType.armed => ('License armed', AppSemanticColors.info),
      LicenseEventType.disarmed => (
        'Enforcement turned off',
        AppSemanticColors.neutral,
      ),
      LicenseEventType.redeemed => (
        'Unlock code redeemed',
        AppSemanticColors.success,
      ),
      LicenseEventType.passwordSet => (
        'Developer password created',
        AppSemanticColors.purple,
      ),
      LicenseEventType.passwordChanged => (
        'Developer password changed',
        AppSemanticColors.purple,
      ),
      LicenseEventType.warning => (
        'Entered warning window',
        AppSemanticColors.warning,
      ),
      LicenseEventType.expired => (
        'License expired — app locked',
        AppSemanticColors.error,
      ),
    };
    final dot = AppSemanticColors.resolve(color, brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.bodySmallSemibold(context)),
                if (event.detail.isNotEmpty)
                  Text(
                    event.detail,
                    style: AppTypography.labelSmall(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            DateFormat('MMM d, h:mm a').format(event.at),
            style: AppTypography.labelSmall(
              context,
            ).copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
