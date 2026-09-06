import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';

/// A circular countdown indicator with a label centered inside the ring.
///
/// [value] is the remaining fraction in the range 0.0–1.0: `1.0` renders a
/// full ring, `0.5` a half ring, and `0.0` an empty ring. The arc uses the
/// warning semantic color so it reads consistently in light and dark mode.
///
/// The widget is a pure view — it owns no timer. Callers drive [value] from
/// an authoritative countdown source (e.g. the session-warning deadline).
class AppCountdownRing extends StatelessWidget {
  const AppCountdownRing({
    super.key,
    required this.value,
    required this.center,
    this.size = 96,
  });

  /// Remaining fraction of the countdown, 0.0–1.0.
  final double value;

  /// Widget centered inside the ring (typically the remaining count).
  final Widget center;

  /// Diameter of the ring in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color =
        AppSemanticColors.resolve(AppSemanticColors.warning, brightness);
    final trackColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              color: trackColor,
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0.0, 1.0),
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              color: color,
            ),
          ),
          center,
        ],
      ),
    );
  }
}
