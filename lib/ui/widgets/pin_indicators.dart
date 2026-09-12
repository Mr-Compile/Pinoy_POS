import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// Displays a row of PIN indicator dots that show how many digits
/// have been entered without revealing the actual digits.
///
/// The number of dots is determined by [pinLength]. Filled dots
/// represent entered digits; empty dots render as rings — the modern
/// phone lock-screen style. For variable-length flows (set PIN) pass
/// the entered count as [pinLength] so dots grow as the user types.
///
/// Call [PinIndicatorsState.shake] through a [GlobalKey] to play the
/// error shake animation.
class PinIndicators extends StatefulWidget {
  /// The total number of PIN digits (determines dot count).
  final int pinLength;

  /// How many digits have been entered so far.
  final int enteredCount;

  /// Whether the indicators should show an error state (e.g. after
  /// an incorrect PIN). This changes the filled dot color to error.
  final bool error;

  /// Whether the indicators should show a success state (e.g. right
  /// after a newly set PIN is saved). Filled dots turn success green.
  final bool success;

  const PinIndicators({
    super.key,
    required this.pinLength,
    required this.enteredCount,
    this.error = false,
    this.success = false,
  });

  @override
  State<PinIndicators> createState() => PinIndicatorsState();
}

class PinIndicatorsState extends State<PinIndicators>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  /// Plays the horizontal shake animation used for wrong/mismatched
  /// PINs. Safe to call while a previous shake is still running.
  void shake() {
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final filledColor = widget.error
        ? cs.error
        : widget.success
            ? AppSemanticColors.resolve(
                AppSemanticColors.success,
                brightness,
              )
            : cs.primary;
    final emptyColor = cs.onSurfaceVariant;

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final t = _shakeController.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 9 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.pinLength, (index) {
          final isFilled = index < widget.enteredCount;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.pinLength > 4 ? 8.0 : 12.0,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled ? filledColor : Colors.transparent,
                border: Border.all(
                  color: isFilled ? filledColor : emptyColor,
                  width: 1.6,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
