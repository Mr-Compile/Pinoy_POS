import 'package:flutter/material.dart';

/// Displays a row of PIN indicator dots that show how many digits
/// have been entered without revealing the actual digits.
///
/// The number of dots is determined by [pinLength].  Filled dots
/// represent entered digits; empty dots represent remaining slots.
class PinIndicators extends StatelessWidget {
  /// The total number of PIN digits (determines dot count).
  final int pinLength;

  /// How many digits have been entered so far.
  final int enteredCount;

  /// Whether the indicators should show an error state (e.g. after
  /// an incorrect PIN).  This changes the filled dot color to error.
  final bool error;

  const PinIndicators({
    super.key,
    required this.pinLength,
    required this.enteredCount,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filledColor = error ? cs.error : cs.primary;
    final emptyColor = cs.outlineVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pinLength, (index) {
        final isFilled = index < enteredCount;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: pinLength > 4 ? 8.0 : 12.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? filledColor : Colors.transparent,
              border: Border.all(
                color: isFilled ? filledColor : emptyColor,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}
