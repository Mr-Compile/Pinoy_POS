import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// A visual section with a bold title, optional subtitle, and optional
/// trailing action. Used to break screens into scannable groups and to
/// reinforce the F-pattern / Z-pattern hierarchy.
class AppSection extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;

  const AppSection({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    required this.child,
    this.showDivider = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null || subtitle != null || action != null)
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: AppTypography.titleLargeBold(context),
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          subtitle!,
                          style: AppTypography.bodySmall(context).copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: Spacing.md),
                  action!,
                ],
              ],
            ),
          ),
        if (showDivider && (title != null || action != null))
          const Divider(height: 24),
        child,
      ],
    );
  }
}
