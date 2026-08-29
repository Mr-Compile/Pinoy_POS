import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_icon_button.dart';
import 'package:pinoy_pos/ui/widgets/app_status_chip.dart';

/// A high-scannability list row with a clear F-pattern:
///
///   - left column: leading image/avatar, title, subtitle
///   - right side: primary value / trailing
///   - bottom row: status chip + quick actions
///
/// Use this for products, sales, categories, users, and any other
/// scrollable list of entities.
class AppListItem extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? statusLabel;
  final Color? statusColor;
  final IconData? statusIcon;
  final List<AppListAction>? actions;
  final List<Widget>? chips;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry margin;
  final AppCardVariant cardVariant;

  const AppListItem({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.statusLabel,
    this.statusColor,
    this.statusIcon,
    this.actions,
    this.chips,
    this.padding,
    this.margin = EdgeInsets.zero,
    this.cardVariant = AppCardVariant.elevated,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: Spacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleMediumSemibold(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      subtitle!,
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Spacing.md),
              trailing!,
            ],
          ],
        ),
        if (chips != null && chips!.isNotEmpty) ...[
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: chips!,
          ),
        ],
        if (statusLabel != null || (actions != null && actions!.isNotEmpty)) ...[
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              if (statusLabel != null && statusColor != null)
                AppStatusChip(
                  label: statusLabel!,
                  color: statusColor!,
                  icon: statusIcon,
                ),
              if (actions != null && actions!.isNotEmpty) ...[
                const Spacer(),
                ...actions!.map((action) => AppIconButton(
                      icon: action.icon,
                      onPressed: action.onPressed,
                      tooltip: action.tooltip,
                      color: action.color ?? cs.onSurfaceVariant,
                    )),
              ],
            ],
          ),
        ],
      ],
    );

    return AppCard(
      onTap: onTap,
      padding: padding ?? const EdgeInsets.all(Spacing.md + 2),
      margin: margin,
      variant: cardVariant,
      child: content,
    );
  }
}

/// A single icon action for [AppListItem].
class AppListAction {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  const AppListAction({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
  });
}
