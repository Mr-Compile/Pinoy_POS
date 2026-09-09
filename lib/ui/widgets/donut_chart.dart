import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/spacing.dart';

/// One segment of a [DonutChart].
class DonutSegment {
  final String label;
  final int value;
  final Color color;

  const DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// A lightweight, dependency-free donut chart with a legend.
///
/// Segments are drawn proportionally. When the total is zero, a muted
/// ring is drawn so the widget never collapses or looks broken. Colors
/// are provided by the caller (semantic tokens), never hardcoded here.
class DonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final double size;

  const DonutChart({
    super.key,
    required this.segments,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = segments.fold<int>(0, (s, seg) => s + seg.value);
    final strokeWidth = size * 0.23;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              segments: segments,
              total: total,
              strokeWidth: strokeWidth,
              trackColor: cs.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(
                '$total',
                style: AppTypography.titleSmallBold(context).copyWith(
                  fontSize: 18,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          alignment: WrapAlignment.center,
          children: [
            for (final seg in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: seg.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${seg.label} ',
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${seg.value}',
                    style: AppTypography.bodySmall(context).copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final int total;
  final double strokeWidth;
  final Color trackColor;

  _DonutPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    // Track ring (shown when total is 0 or as the background).
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (total <= 0) return;

    double startAngle = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = 2 * math.pi * seg.value / total;
      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = seg.color,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.total != total ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.segments.length != segments.length;
}
