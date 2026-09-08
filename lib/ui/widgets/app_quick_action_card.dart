import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/quick_action_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// A single, theme-aware quick action tile.
///
/// The visual style (background, foreground, icon and label) comes from
/// [QuickActionType] via [resolveQuickActionStyle]. Role-specific dashboards
/// only supply the [type], an optional [label]/[icon] override and the
/// [onTap] handler. The card is responsive, keeps a 64x64 touch target and
/// shows a disabled state when [enabled] is false.
class AppQuickActionCard extends StatelessWidget {
  final QuickActionType type;
  final VoidCallback? onTap;
  final String? label;
  final IconData? icon;
  final bool enabled;

  const AppQuickActionCard({
    super.key,
    required this.type,
    this.onTap,
    this.label,
    this.icon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = resolveQuickActionStyle(context, type);
    final effectiveLabel = label ?? style.label;
    final effectiveIcon = icon ?? style.icon;

    final background =
        enabled ? style.background : style.background.withValues(alpha: 0.12);
    final foreground =
        enabled ? style.foreground : style.foreground.withValues(alpha: 0.38);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  effectiveIcon,
                  size: 28,
                  color: foreground,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  effectiveLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium(context).copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
