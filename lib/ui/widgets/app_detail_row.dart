import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/app_typography.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_square.dart';

/// A read-only detail row with a leading tinted icon, label, and value.
///
/// Matches the mockup `.view-row` with `.isquare` pattern used in
/// category, product, and stock view dialogs.
class AppDetailRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final Color? valueColor;

  const AppDetailRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIconSquare(
            icon: icon,
            backgroundColor: effectiveIconColor.withValues(alpha: 0.16),
            iconColor: effectiveIconColor,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium(context).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall(context).copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
