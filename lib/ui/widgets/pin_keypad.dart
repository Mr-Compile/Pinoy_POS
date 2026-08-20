import 'package:flutter/material.dart';

/// A reusable, touch-friendly numeric keypad for PIN entry.
///
/// Displays digits 1–9, 0, and a backspace button in a 3×4 grid.
/// Each button has a minimum 48×48 touch target (enlarged for comfort),
/// visual pressed feedback, and uses theme colors exclusively.
///
/// The keypad does not manage any state — it simply notifies the
/// parent via [onDigitPressed] and [onBackspacePressed].
class PinKeypad extends StatelessWidget {
  /// Called when a digit (0–9) is tapped.
  final ValueChanged<String> onDigitPressed;

  /// Called when the backspace button is tapped.
  final VoidCallback onBackspacePressed;

  /// Whether input is currently disabled (e.g. during verification).
  final bool enabled;

  const PinKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onBackspacePressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(context, ['1', '2', '3']),
        const SizedBox(height: 12),
        _buildRow(context, ['4', '5', '6']),
        const SizedBox(height: 12),
        _buildRow(context, ['7', '8', '9']),
        const SizedBox(height: 12),
        _buildRow(context, [null, '0', 'backspace']),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<String?> items) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        if (item == null) return const SizedBox(width: 72, height: 72);
        if (item == 'backspace') {
          return _buildBackspaceButton(context);
        }
        return _buildDigitButton(context, item);
      }).toList(),
    );
  }

  Widget _buildDigitButton(BuildContext context, String digit) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 72,
      height: 72,
      child: Semantics(
        label: 'Digit $digit',
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onDigitPressed(digit) : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHigh,
              ),
              alignment: Alignment.center,
              child: Text(
                digit,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 72,
      height: 72,
      child: Semantics(
        label: 'Backspace',
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onBackspacePressed : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHigh,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.backspace_outlined,
                size: 28,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
