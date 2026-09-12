import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';

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
    DashAccent.blue => AppSemanticColors.resolve(
        AppSemanticColors.primaryLight,
        b,
      ),
    DashAccent.teal => AppSemanticColors.resolve(AppSemanticColors.teal, b),
    DashAccent.green => AppSemanticColors.resolve(AppSemanticColors.success, b),
    DashAccent.amber => AppSemanticColors.resolve(AppSemanticColors.warning, b),
    DashAccent.deep => AppSemanticColors.resolve(AppSemanticColors.primary, b),
    DashAccent.grey => AppSemanticColors.resolve(AppSemanticColors.neutral, b),
    DashAccent.red => AppSemanticColors.resolve(AppSemanticColors.error, b),
    DashAccent.purple => AppSemanticColors.resolve(AppSemanticColors.violet, b),
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

  String _greeting(UserRole? role) {
    if (greeting != null) return greeting!;
    if (role == UserRole.admin) return 'Welcome back';
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  (Color, Color) _rolePillColors(UserRole? role, Brightness brightness) {
    return switch (role) {
      UserRole.owner => (
          AppSemanticColors.resolve(
            AppSemanticColors.info,
            brightness,
          ).withValues(alpha: 0.18),
          AppSemanticColors.resolve(AppSemanticColors.info, brightness),
        ),
      UserRole.admin => (
          AppSemanticColors.resolve(
            AppSemanticColors.teal,
            brightness,
          ).withValues(alpha: 0.16),
          AppSemanticColors.resolve(AppSemanticColors.teal, brightness),
        ),
      UserRole.staff => (
          AppSemanticColors.resolve(
            AppSemanticColors.success,
            brightness,
          ).withValues(alpha: 0.16),
          AppSemanticColors.resolve(AppSemanticColors.success, brightness),
        ),
      null => (Colors.transparent, Colors.transparent),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final name = user?.fullName ?? '';
    final userRole = user?.role;
    final title = _greeting(userRole);
    final (roleBg, roleFg) = _rolePillColors(userRole, b);
    final roleLabel = userRole?.displayName ?? '';
    final date = DateFormat('EEE, MMM d').format(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodySmall(context).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (name.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  name,
                  style: AppTypography.titleLargeBold(context).copyWith(
                    color: cs.onSurface,
                    fontSize: 18,
                  ),
                ),
              ],
              if (roleLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: roleBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    roleLabel,
                    style: AppTypography.labelSmall(context).copyWith(
                      color: roleFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          date,
          style: AppTypography.bodySmall(context).copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
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

  /// Custom pill shown under the amount. Takes precedence over the
  /// delta pill when provided.
  final Widget? pill;

  /// Overrides the default 34pt amount size for long, non-currency
  /// values such as status text.
  final double? amountFontSize;

  const HeroKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.amount,
    this.deltaPercent,
    this.deltaSuffix,
    this.sparkValues,
    this.footStats,
    this.pill,
    this.amountFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final start = isDark
        ? AppColorTokens.primaryBlueStrong
        : AppColorTokens.lightPrimary;
    final end = isDark
        ? AppColorTokens.primaryBlueDeep
        : AppColorTokens.primaryBlueStrong;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, end],
    );
    final delta = deltaPercent;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroLabel(icon: icon, label: label),
                    const SizedBox(height: 6),
                    Text(
                      amount,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: amountFontSize ?? 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (pill != null) ...[
                      const SizedBox(height: Spacing.sm),
                      pill!,
                    ] else if (delta != null) ...[
                      const SizedBox(height: Spacing.sm),
                      _DeltaPill(delta: delta, suffix: deltaSuffix),
                    ],
                  ],
                ),
              ),
              if (sparkValues != null && sparkValues!.isNotEmpty) ...[
                const SizedBox(width: Spacing.md),
                _LineSparkline(
                  values: sparkValues!,
                  width: 90,
                  height: 40,
                ),
              ],
            ],
          ),
          if (footStats != null && footStats!.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
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

class _HeroLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.white.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.bodySmall(context).copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final double delta;
  final String? suffix;

  const _DeltaPill({required this.delta, this.suffix});

  @override
  Widget build(BuildContext context) {
    final positive = delta >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '${positive ? '+' : ''}${delta.toStringAsFixed(1)}% ${suffix ?? ''}'
                .trim(),
            style: AppTypography.bodySmall(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineSparkline extends StatelessWidget {
  final List<double> values;
  final double width;
  final double height;

  const _LineSparkline({
    required this.values,
    this.width = 90,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final max = values.reduce((a, b) => a > b ? a : b);
    final safeMax = max <= 0 ? 1.0 : max;

    if (values.length == 1) {
      final y = size.height - (values[0] / safeMax) * size.height;
      canvas.drawCircle(
        Offset(size.width, y),
        3,
        Paint()..color = Colors.white,
      );
      return;
    }

    final points = List<Offset>.generate(values.length, (i) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (values[i] / safeMax) * size.height;
      return Offset(x, y);
    });

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
    canvas.drawCircle(points.last, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values.length != values.length || old.values != values;
}

/// A single foot-stat shown below the hero KPI value.
class HeroFootStat extends StatelessWidget {
  final String value;
  final String label;

  const HeroFootStat(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.titleSmallBold(context).copyWith(
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: AppTypography.bodySmall(context).copyWith(
            color: Colors.white.withValues(alpha: 0.85),
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
      mainAxisExtent: 108,
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 13),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.titleMediumBold(context).copyWith(
              color: cs.onSurface,
              fontSize: 20,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall(context).copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
    this.title = '',
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
    final b = cs.brightness;
    final warning = AppSemanticColors.resolve(AppSemanticColors.warning, b);
    final bg = alert
        ? Color.lerp(cs.surface, warning, 0.04) ?? cs.surface
        : elevated
            ? cs.surfaceContainer
            : cs.surface;
    final borderColor = alert
        ? warning.withValues(alpha: 0.35)
        : cs.outline;
    final showHeader = title.isNotEmpty || icon != null || trailing != null;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, 0),
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
                        size: 38,
                        iconSize: 19,
                        square: true,
                        filled: false,
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
    final b = Theme.of(context).brightness;

    final Color bg;
    final Color borderColor;
    final Color fg;
    final Widget iconWidget;

    if (primary) {
      bg = cs.primary;
      borderColor = Colors.transparent;
      fg = cs.onPrimary;
      iconWidget = _QuickIconCircle(icon: icon, primary: true);
    } else if (accent != null) {
      final accentColor = dashAccentColor(context, accent!);
      bg = cs.surface;
      borderColor = cs.outline;
      fg = labelColor ??
          AppSemanticColors.resolve(AppSemanticColors.neutral, b);
      iconWidget = _QuickIconCircle(icon: icon, color: accentColor);
    } else {
      bg = cs.surface;
      borderColor = cs.outline;
      fg = labelColor ?? cs.onSurface;
      iconWidget = _QuickIconCircle(icon: icon);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 8),
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

class _QuickIconCircle extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool primary;

  const _QuickIconCircle({
    required this.icon,
    this.color,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 34;
    const double iconSize = 18;
    final Color bgColor;
    final Color iconColor;

    if (primary) {
      bgColor = Colors.white.withValues(alpha: 0.22);
      iconColor = Colors.white;
    } else if (color != null) {
      bgColor = color!.withValues(alpha: 0.16);
      iconColor = color!;
    } else {
      final cs = Theme.of(context).colorScheme;
      bgColor = cs.surfaceContainerHighest;
      iconColor = cs.onSurface;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

const double _kQuickActionTileHeight = 84.0;

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
    return GridView(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns ?? 2,
        mainAxisSpacing: Spacing.md,
        crossAxisSpacing: Spacing.md,
        mainAxisExtent: _kQuickActionTileHeight,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
            color: cs.outline.withValues(alpha: 0.5),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              leading ?? const SizedBox.shrink(),
              if (leading != null) const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: AppTypography.bodyMediumSemibold(context)
                            .copyWith(
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

/// A small product thumbnail for dashboard rows.
///
/// Shows the product image when [imagePath] resolves; otherwise falls back
/// to a dynamic placeholder built from the first letter of [label]. Missing
/// or corrupted files render the same placeholder — never a broken image.
class DashThumb extends StatelessWidget {
  final String label;
  final String? imagePath;

  const DashThumb({
    super.key,
    required this.label,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppImage(
        imagePath: imagePath,
        borderRadius: 12,
        placeholderIcon: Icons.inventory_2,
        placeholderIconSize: 20,
        placeholderBuilder: (context) => Center(
          child: Text(
            initial,
            style: AppTypography.titleMediumBold(context).copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular avatar for dashboard rows.
///
/// Shows the user's profile photo when [imagePath] resolves; otherwise
/// falls back to initials on [color] (or the primary colour).
class DashAvatar extends StatelessWidget {
  final String name;
  final Color? color;
  final String? imagePath;

  const DashAvatar({
    super.key,
    required this.name,
    this.color,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.primary;
    final fg = _Contrast.onColor(context, bg);

    return AppAvatar(
      imagePath: imagePath,
      initials: name,
      radius: 17,
      backgroundColor: bg,
      initialsStyle: AppTypography.bodySmallSemibold(context).copyWith(
        color: fg,
      ),
    );
  }
}

/// A coloured icon badge used by dashboard cards and rows.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool square;
  final bool small;
  final double? size;
  final double? iconSize;
  final bool filled;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.square = false,
    this.small = false,
    this.size,
    this.iconSize,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? (small ? 32.0 : 40.0);
    final effectiveIconSize = iconSize ?? (small ? 16.0 : 20.0);
    final bg = filled ? color : color.withValues(alpha: 0.16);
    final fg = filled ? _Contrast.onColor(context, color) : color;

    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: square
            ? BorderRadius.circular(10)
            : BorderRadius.circular(effectiveSize / 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: effectiveIconSize),
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
    final bg = color.withValues(alpha: 0.16);

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
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.labelSmall(context).copyWith(
              color: color,
              fontWeight: FontWeight.w700,
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
            color: cs.primary,
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
  return color.withValues(alpha: 0.16);
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
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.onPrimary, size: 18),
              const SizedBox(width: Spacing.sm),
              Text(
                label,
                style: AppTypography.titleSmallBold(context).copyWith(
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColorTokens.primaryBlueStrong.withValues(alpha: 0.35),
                AppColorTokens.primaryBlueDeep.withValues(alpha: 0.45),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              IconBadge(
                icon: icon,
                color: dashAccentColor(context, DashAccent.deep),
                size: 34,
                iconSize: 18,
                filled: true,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMediumBold(context).copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.85),
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
            color: cs.outline.withValues(alpha: 0.5),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconBadge(
                icon: icon,
                color: color,
                size: 34,
                iconSize: 17,
                filled: false,
              ),
              const SizedBox(width: Spacing.md),
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
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              DashRowEnd(
                amount: amount,
                pill: StatusPill(
                  label: '${percent.toStringAsFixed(0)}%',
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
