import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// A compact, tappable summary tile used in stat strips on list screens
/// (Products, Categories). Shows a solid colored icon badge, a bold value,
/// and a small label.
///
/// When [onTap] is provided the tile acts as a filter shortcut; [selected]
/// draws the border in [color] so the active filter is visible.
class SummaryStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color onColor;
  final String value;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const SummaryStatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.onColor = Colors.white,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: selected ? color.withValues(alpha: 0.08) : cs.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? color : cs.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: onColor),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                value,
                style: AppTypography.titleLarge(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.labelSmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
