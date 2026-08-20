import 'package:flutter/material.dart';
import 'package:pinoy_pos/services/password_strength_service.dart';

/// A dynamic checklist that shows password requirements with
/// success/error/neutral states.
///
/// Updates in real-time as the user types.  Uses clear icons and text
/// so that color is not the only indicator.
class PasswordRequirementsChecklist extends StatelessWidget {
  final PasswordStrengthResult result;

  const PasswordRequirementsChecklist({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      label: 'Password requirements checklist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password requirements',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _RequirementItem(
            satisfied: result.meetsMinLength,
            label: 'At least 8 characters',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 4),
          _RequirementItem(
            satisfied: result.notCommonPassword,
            label: 'Not a common password',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 4),
          _RequirementItem(
            satisfied: result.doesNotContainUsername,
            label: 'Does not contain your username',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 4),
          _RequirementItem(
            satisfied: result.isStrongEnough,
            label: 'Strong enough to continue',
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

class _RequirementItem extends StatelessWidget {
  final bool satisfied;
  final String label;
  final ColorScheme colorScheme;

  const _RequirementItem({
    required this.satisfied,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          satisfied ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          semanticLabel: satisfied ? 'Requirement met' : 'Requirement not met',
          color: satisfied
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: satisfied
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
