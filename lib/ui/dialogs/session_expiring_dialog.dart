import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';
import 'package:pinoy_pos/ui/widgets/app_countdown_ring.dart';
import 'package:pinoy_pos/ui/widgets/app_dialog.dart';

/// "Session Expiring" warning modal.
///
/// Shown by [SessionGuard] when the inactivity deadline enters the warning
/// window. A single ticker recomputes the remaining time from the absolute
/// [deadline] on every tick, so both the number and the circular progress
/// ring stay accurate if the app is suspended and resumed while the dialog
/// is open.
///
/// The dialog is display-only: it never decides whether the session ends.
/// The owning [SessionTimeoutService] fires its own timeout at [deadline],
/// which is the single source of truth for automatic logout/lock.
class SessionExpiringDialog extends StatefulWidget {
  const SessionExpiringDialog({
    super.key,
    required this.deadline,
    required this.warningDuration,
    required this.onContinue,
    required this.onLogout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The absolute inactivity deadline — the moment the countdown reaches
  /// zero and the session ends.
  final DateTime deadline;

  /// The full warning-window length (the configured
  /// `session_warning_seconds`). Used to derive the ring's starting
  /// fraction so the countdown always sweeps a full circle.
  final Duration warningDuration;

  /// "Continue Session" — dismisses the dialog and resets the inactivity
  /// timer to the full configured timeout.
  final VoidCallback onContinue;

  /// "Log Out" — ends the session immediately.
  final VoidCallback onLogout;

  /// Clock used to compute the remaining countdown. Injectable for tests;
  /// defaults to [DateTime.now].
  final DateTime Function() _clock;

  @override
  State<SessionExpiringDialog> createState() => _SessionExpiringDialogState();
}

class _SessionExpiringDialogState extends State<SessionExpiringDialog> {
  Timer? _ticker;
  late int _remainingMilliseconds = _computeRemainingMs();

  int _computeRemainingMs() {
    final ms = widget.deadline.difference(widget._clock()).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  @override
  void initState() {
    super.initState();
    // One ticker drives both the number and the ring. A sub-second period
    // keeps the ring smooth; the displayed second count still changes only
    // once per second because it is derived by ceiling the milliseconds.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final remainingMs = _computeRemainingMs();
      if (remainingMs <= 0) {
        // The service's own timer fires the timeout at the same instant;
        // close the dialog defensively so it cannot linger.
        _ticker?.cancel();
        Navigator.of(context, rootNavigator: true).maybePop();
        return;
      }
      setState(() => _remainingMilliseconds = remainingMs);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final remainingSeconds = (_remainingMilliseconds + 999) ~/ 1000;
    final totalMs = widget.warningDuration.inMilliseconds;
    final fraction =
        totalMs <= 0 ? 0.0 : _remainingMilliseconds / totalMs;
    final unit = remainingSeconds == 1 ? 'second' : 'seconds';

    return AppDialog(
      type: AppDialogType.warning,
      title: 'Session Expiring',
      message: 'Are you still there?',
      dismissible: false,
      showClose: false,
      actions: [
        AppDialogAction(
          label: 'Log Out',
          color: AppButtonColor.error,
          onPressed: (dialogContext) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
            widget.onLogout();
          },
        ),
        AppDialogAction(
          label: 'Continue Session',
          isPrimary: true,
          color: AppButtonColor.success,
          onPressed: (dialogContext) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
            widget.onContinue();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: '$remainingSeconds $unit remaining',
            child: ExcludeSemantics(
              child: AppCountdownRing(
                value: fraction,
                size: 100,
                center: Text(
                  '$remainingSeconds',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$remainingSeconds $unit',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
