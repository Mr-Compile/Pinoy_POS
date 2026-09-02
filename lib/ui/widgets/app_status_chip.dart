import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_typography.dart';

/// A compact status chip with a colored icon and label.
///
/// Use this for statuses like "confirmed", "pending", "active", or
/// "inactive". The [color] drives both the foreground and a subtle
/// background tint.
class AppStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  const AppStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: AppTypography.labelMedium(context).copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );

    if (filled) {
      return Chip(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color),
        backgroundColor: color.withValues(alpha: 0.1),
        label: content,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }
}
