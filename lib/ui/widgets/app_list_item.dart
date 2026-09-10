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
  final List<AppListMenuAction>? menuActions;
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
    this.menuActions,
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
        if (statusLabel != null ||
            (actions != null && actions!.isNotEmpty) ||
            (menuActions != null && menuActions!.isNotEmpty)) ...[
          const SizedBox(height: Spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (statusLabel != null && statusColor != null) ...[
                AppStatusChip(
                  label: statusLabel!,
                  color: statusColor!,
                  icon: statusIcon,
                ),
                const SizedBox(width: Spacing.sm),
              ],
              if (menuActions != null && menuActions!.isNotEmpty)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildMenuButton(context),
                  ),
                )
              else if (actions != null && actions!.isNotEmpty)
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    children: actions!.map((action) => AppIconButton(
                          icon: action.icon,
                          onPressed: action.onPressed,
                          tooltip: action.tooltip,
                          color: action.color ?? cs.onSurfaceVariant,
                        )).toList(),
                  ),
                ),
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

  Widget _buildMenuButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
      tooltip: 'Options',
      padding: EdgeInsets.zero,
      onSelected: (index) {
        final action = menuActions![index];
        action.onPressed?.call();
      },
      itemBuilder: (context) {
        return menuActions!.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          final color = action.color ?? cs.onSurfaceVariant;
          return PopupMenuItem<int>(
            value: index,
            child: Row(
              children: [
                Icon(action.icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
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

/// A labeled action for a [PopupMenuButton] inside [AppListItem].
class AppListMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  const AppListMenuAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.color,
  });
}
