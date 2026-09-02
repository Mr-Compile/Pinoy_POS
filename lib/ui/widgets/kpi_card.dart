import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/breakpoints.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/ui/widgets/app_card.dart';

/// Visual prominence of a KPI card. Drives number size and padding so the
/// dashboard has clear hierarchy instead of every card being equally loud.
enum KpiCardTier {
  /// Large primary metric (e.g. Today's Sales).
  primary,

  /// Medium secondary metric (e.g. Low Stock count).
  secondary,

  /// Compact supporting metric.
  compact,
}

/// A KPI card with a semantic icon, label, value, and optional subtitle.
///
/// Colors come from [ColorScheme] / semantic tokens — never hardcoded.
/// The icon tint is provided by the caller so it can reflect meaning
/// (success/warning/error/primary) without this widget inventing colors.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final String? subtitle;
  final KpiCardTier tier;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor,
    this.subtitle,
    this.tier = KpiCardTier.secondary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = this.iconColor ?? cs.primary;

    final TextStyle valueStyle;
    final double iconSize;
    final EdgeInsets padding;
    switch (tier) {
      case KpiCardTier.primary:
        valueStyle = AppTypography.headlineMedium(context).copyWith(
          color: cs.onSurface,
          height: 1.1,
        );
        iconSize = 28;
        padding = const EdgeInsets.all(Spacing.lg);
      case KpiCardTier.secondary:
        valueStyle = AppTypography.titleLarge(context).copyWith(
          color: cs.onSurface,
          height: 1.1,
        );
        iconSize = 24;
        padding = const EdgeInsets.all(Spacing.md + 2);
      case KpiCardTier.compact:
        valueStyle = AppTypography.titleMedium(context).copyWith(
          color: cs.onSurface,
          height: 1.1,
        );
        iconSize = 20;
        padding = const EdgeInsets.all(Spacing.md);
    }

    return AppCard(
      padding: padding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            value,
            style: valueStyle.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// A skeleton placeholder shown while a KPI value is loading. Keeps the
/// dashboard layout stable instead of flashing "0" before data arrives.
class KpiCardSkeleton extends StatelessWidget {
  final KpiCardTier tier;

  const KpiCardSkeleton({super.key, this.tier = KpiCardTier.secondary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double valueHeight;
    final EdgeInsets padding;
    switch (tier) {
      case KpiCardTier.primary:
        valueHeight = 30;
        padding = const EdgeInsets.all(Spacing.lg);
      case KpiCardTier.secondary:
        valueHeight = 24;
        padding = const EdgeInsets.all(Spacing.md + 2);
      case KpiCardTier.compact:
        valueHeight = 20;
        padding = const EdgeInsets.all(Spacing.md);
    }

    final block = Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(child: block),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          SizedBox(height: valueHeight, child: block),
        ],
      ),
    );
  }
}

/// Helper to build a responsive KPI grid that adapts column count to width.
class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  final int tabletColumns;
  final int desktopColumns;

  const KpiGrid({
    super.key,
    required this.children,
    this.tabletColumns = 4,
    this.desktopColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final layout = layoutClassFor(width);
        final crossAxisCount = switch (layout) {
          LayoutClass.expanded => desktopColumns,
          LayoutClass.medium => tabletColumns,
          LayoutClass.compact => 2,
        };
        final aspectRatio = switch (layout) {
          LayoutClass.compact => 0.95,
          _ => 1.15,
        };

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Spacing.md,
          crossAxisSpacing: Spacing.md,
          // Wider cards on mobile so large numbers don't overflow at 320px.
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}
