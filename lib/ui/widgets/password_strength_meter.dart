import 'package:flutter/material.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';

/// A live password strength meter that displays a colored progress bar
/// and a text label (Very Weak / Weak / Fair / Good / Strong).
///
/// The meter updates as the user types and uses semantic theme colors
/// — no hardcoded colors.  Labels are always shown in addition to the
/// bar so that color is not the only indicator.
class PasswordStrengthMeter extends StatelessWidget {
  final PasswordStrengthResult result;

  const PasswordStrengthMeter({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Map strength level to a semantic color token.
    final Color strengthColor;
    switch (result.level) {
      case PasswordStrengthLevel.veryWeak:
      case PasswordStrengthLevel.weak:
        strengthColor = colorScheme.error;
      case PasswordStrengthLevel.fair:
        strengthColor = colorScheme.tertiary;
      case PasswordStrengthLevel.good:
        strengthColor = colorScheme.primary;
      case PasswordStrengthLevel.strong:
        strengthColor = colorScheme.primary;
    }

    // 5 segments: 0–4.
    const int maxScore = 4;
    final int filledSegments = result.level.score;

    return Semantics(
      label: 'Password strength: ${result.level.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Password Strength',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                result.level.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: strengthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Segmented bar
          Row(
            children: List.generate(maxScore + 1, (i) {
              final isFilled = i <= filledSegments;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < maxScore ? 4 : 0),
                  decoration: BoxDecoration(
                    color: isFilled
                        ? strengthColor
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          // Guidance text
          Text(
            result.guidance,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
