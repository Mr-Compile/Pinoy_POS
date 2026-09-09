import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/ui/widgets/app_button.dart';

/// Accent palette used by dashboard cards, icon badges and quick actions.
enum DashAccent {
  blue,
  teal,
  green,
  amber,
  deep,
  grey,
  red,
  purple,
}

/// Resolves a [DashAccent] to a theme-aware color.
Color dashAccentColor(BuildContext context, DashAccent accent) {
  final b = Theme.of(context).brightness;
  return switch (accent) {
    DashAccent.blue => AppSemanticColors.resolve(AppSemanticColors.info, b),
    DashAccent.teal => AppSemanticColors.resolve(AppSemanticColors.teal, b),
    DashAccent.green => AppSemanticColors.resolve(AppSemanticColors.success, b),
    DashAccent.amber => AppSemanticColors.resolve(AppSemanticColors.warning, b),
    DashAccent.deep => AppSemanticColors.resolve(AppSemanticColors.violet, b),
    DashAccent.grey => AppSemanticColors.resolve(AppSemanticColors.neutral, b),
    DashAccent.red => AppSemanticColors.resolve(AppSemanticColors.error, b),
    DashAccent.purple => AppSemanticColors.resolve(AppSemanticColors.purple, b),
  };
}

class _Contrast {
  static Color onColor(BuildContext context, Color color) {
    return AppSemanticColors.contrastFor(color, Theme.of(context).brightness);
  }
}

/// Welcome header shown at the top of the dashboard.
class DashboardWelcome extends StatelessWidget {
  final User? user;
  final String? greeting;

  const DashboardWelcome({
    super.key,
    this.user,
    this.greeting,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = user?.fullName ?? '';
    final title = greeting ?? 'Welcome back';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.titleMedium(context).copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        if (name.isNotEmpty)
          Text(
            name,
            style: AppTypography.headlineSmallBold(context).copyWith(
              color: cs.onSurface,
            ),
          ),
      ],
    );
  }
}

/// Large hero KPI card with an optional sparkline and foot stats.
class HeroKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final double? deltaPercent;
  final String? deltaSuffix;
  final List<double>? sparkValues;
  final List<Widget>? footStats;

  const HeroKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.amount,
    this.deltaPercent,
    this.deltaSuffix,
    this.sparkValues,
    this.footStats,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;

    final delta = deltaPercent;
    final Widget? deltaWidget = delta != null
        ? Text(
            '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}% ${deltaSuffix ?? ''}',
            style: AppTypography.bodySmall(context).copyWith(
              color: delta >= 0
                  ? AppSemanticColors.resolve(AppSemanticColors.success, b)
                  : AppSemanticColors.resolve(AppSemanticColors.error, b),
              fontWeight: FontWeight.w600,
            ),
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 20),
              const SizedBox(width: Spacing.sm),
              Text(
                label,
                style: AppTypography.bodySmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: AppTypography.headlineSmallBold(context).copyWith(
                  color: cs.onSurface,
                ),
              ),
              if (deltaWidget != null) ...[
                const SizedBox(width: Spacing.sm),
                deltaWidget,
              ],
            ],
          ),
          if (sparkValues != null && sparkValues!.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _Sparkline(values: sparkValues!),
          ],
          if (footStats != null && footStats!.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            const Divider(height: 1),
            const SizedBox(height: Spacing.md),
            Row(
              children: footStats!
                  .map((s) => Expanded(child: s))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<double> values;

  const _Sparkline({required this.values});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final max = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);
    final safeMax = max <= 0 ? 1.0 : max;

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: (values[i] / safeMax) * 40,
                  decoration: BoxDecoration(
                    color: i == values.length - 1 ? cs.tertiary : cs.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single foot-stat shown below the hero KPI value.
class HeroFootStat extends StatelessWidget {
  final String value;
  final String label;

  const HeroFootStat(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.titleSmallBold(context).copyWith(
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: AppTypography.bodySmall(context).copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A responsive row of [StatItem] widgets.
class StatStrip extends StatelessWidget {
  final List<Widget> items;
  final int? columns;

  const StatStrip({
    super.key,
    required this.items,
    this.columns,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns ?? 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.md,
      crossAxisSpacing: Spacing.md,
      childAspectRatio: 2.6,
      children: items,
    );
  }
}

/// A single statistic item with an icon, value and label.
class StatItem extends StatelessWidget {
  final IconData icon;
  final DashAccent accent;
  final String value;
  final String label;

  const StatItem({
    super.key,
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = dashAccentColor(context, accent);

    return Row(
      children: [
        IconBadge(
          icon: icon,
          color: color,
          small: true,
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: AppTypography.titleMediumBold(context),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: AppTypography.bodySmall(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A card used throughout the dashboard for grouping related content.
class DashCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final DashAccent? iconAccent;
  final Widget? trailing;
  final bool alert;
  final bool elevated;
  final List<Widget> children;

  const DashCard({
    super.key,
    required this.title,
    this.icon,
    this.iconAccent,
    this.trailing,
    this.alert = false,
    this.elevated = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = alert
        ? Color.lerp(cs.surface, cs.errorContainer, 0.12) ?? cs.surface
        : cs.surface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: alert ? cs.error : cs.outlineVariant.withValues(alpha: 0.5),
          width: alert ? 1.5 : 1,
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, 0),
            child: Row(
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: IconBadge(
                      icon: icon!,
                      color: dashAccentColor(
                        context,
                        iconAccent ?? DashAccent.blue,
                      ),
                      small: true,
                    ),
                  ),
                Text(
                  title,
                  style: AppTypography.titleMediumBold(context).copyWith(
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single quick-action tile used in dashboard grids and the More screen.
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final DashAccent? accent;
  final int? maxLines;
  final Color? labelColor;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.accent,
    this.maxLines,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    final Widget iconWidget;

    if (primary) {
      bg = cs.primary;
      fg = cs.onPrimary;
      iconWidget = Icon(icon, color: fg, size: 28);
    } else if (accent != null) {
      final accentColor = dashAccentColor(context, accent!);
      bg = accentColor.withValues(alpha: 0.12);
      fg = labelColor ?? accentColor;
      iconWidget = IconBadge(
        icon: icon,
        color: accentColor,
        small: true,
      );
    } else {
      bg = cs.surface;
      fg = labelColor ?? cs.onSurface;
      iconWidget = Icon(icon, color: fg, size: 28);
    }

    final borderColor = primary
        ? Colors.transparent
        : accent != null
            ? dashAccentColor(context, accent!).withValues(alpha: 0.3)
            : cs.outlineVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: Spacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: maxLines ?? 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmallSemibold(context).copyWith(
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A panel that lays [QuickActionTile] children out in a grid.
class QuickActionPanel extends StatelessWidget {
  final List<Widget> children;
  final int? columns;

  const QuickActionPanel({
    super.key,
    required this.children,
    this.columns,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns ?? 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.md,
      crossAxisSpacing: Spacing.md,
      childAspectRatio: 1.15,
      children: children,
    );
  }
}

/// A dashboard list row with a leading widget, title, subtitle and trailing.
class DashRow extends StatelessWidget {
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final bool showDivider;
  final Widget? trailing;

  const DashRow({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.showDivider = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (showDivider)
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          child: Row(
            children: [
              leading ?? const SizedBox.shrink(),
              leading != null
                  ? const SizedBox(width: Spacing.sm)
                  : const SizedBox.shrink(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: AppTypography.bodyMediumSemibold(context).copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTypography.bodySmall(context).copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Spacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A small product thumbnail placeholder for dashboard rows.
class DashThumb extends StatelessWidget {
  final String label;

  const DashThumb({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTypography.titleSmallBold(context).copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A circular avatar with initials for dashboard rows.
class DashAvatar extends StatelessWidget {
  final String name;
  final Color? color;

  const DashAvatar({
    super.key,
    required this.name,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.primary;
    final fg = _Contrast.onColor(context, bg);
    final initials = _initials(name);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTypography.bodySmallSemibold(context).copyWith(
          color: fg,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '';
  if (parts.length == 1) {
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '';
  }
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

/// A coloured icon badge used by dashboard cards and rows.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool square;
  final bool small;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.square = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = _Contrast.onColor(context, color);
    final size = small ? 32.0 : 40.0;
    final iconSize = small ? 16.0 : 20.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: square ? BorderRadius.circular(10) : BorderRadius.circular(size / 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: iconSize),
    );
  }
}

/// A small coloured status pill, optionally with a leading icon.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.bodySmallSemibold(context).copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A right-aligned amount and optional pill used in dashboard rows.
class DashRowEnd extends StatelessWidget {
  final String amount;
  final Widget? pill;

  const DashRowEnd({
    super.key,
    required this.amount,
    this.pill,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          amount,
          style: AppTypography.titleSmallBold(context).copyWith(
            color: cs.onSurface,
          ),
        ),
        if (pill != null) ...[
          const SizedBox(height: 2),
          pill!,
        ],
      ],
    );
  }
}

/// Returns a very light tint of [color] for use behind text in the same color.
Color dashAccentTint(Color color) {
  return color.withValues(alpha: 0.12);
}

/// A wide, prominent CTA button used on dashboard screens.
class BigCtaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const BigCtaButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton.filled(
      label: label,
      icon: icon,
      onPressed: onTap,
      fullWidth: true,
      size: AppButtonSize.large,
    );
  }
}

/// A banner that promotes the AI advisor feature.
class AdvisorBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const AdvisorBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              IconBadge(
                icon: icon,
                color: dashAccentColor(context, DashAccent.deep),
                small: true,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMediumBold(context).copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall(context).copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: cs.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A payment breakdown row with a progress bar.
class PaymentProgressRow extends StatelessWidget {
  final IconData icon;
  final DashAccent accent;
  final String method;
  final String amount;
  final double percent;
  final bool showDivider;

  const PaymentProgressRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.method,
    required this.amount,
    required this.percent,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = dashAccentColor(context, accent);

    return Column(
      children: [
        if (showDivider)
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, small: true),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method,
                      style: AppTypography.bodyMediumSemibold(context).copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent / 100,
                        backgroundColor:
                            cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: AppTypography.titleSmallBold(context).copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
