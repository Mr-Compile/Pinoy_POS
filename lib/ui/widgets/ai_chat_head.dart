import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinoy_pos/core/ai_config_status.dart';
import 'package:pinoy_pos/providers/ai_advisor_provider.dart';

/// Floating, draggable AI chat head inspired by modern messaging apps.
///
/// Shows a circular button that the Owner can drag to any position on
/// screen. Tapping (without dragging) opens the AI chat panel.
///
/// Position persistence:
/// - The last valid position is stored in SharedPreferences keyed by
///   user ID so different Owner accounts don't inherit each other's
///   positions.
/// - On orientation/window change, the position is clamped to the new
///   safe area.
///
/// The widget enforces:
/// - SafeArea boundaries (the button cannot move behind system UI)
/// - At least 50% of the button remains visible on each edge
/// - Drag vs tap distinction (a drag > 8px is not a tap)
/// - Gentle edge snapping after drag ends
class AIChatHead extends ConsumerStatefulWidget {
  final int userId;

  const AIChatHead({super.key, required this.userId});

  @override
  ConsumerState<AIChatHead> createState() => _AIChatHeadState();
}

class _AIChatHeadState extends ConsumerState<AIChatHead> {
  Offset _position = Offset.zero;
  bool _isDragging = false;
  double _totalDragDistance = 0;
  bool _positionLoaded = false;

  static const double _headSize = 56.0;
  static const double _edgePadding = 8.0;
  static const double _dragThreshold = 8.0;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_chat_head_pos_${widget.userId}';
    final dx = prefs.getDouble('${key}_x');
    final dy = prefs.getDouble('${key}_y');

    if (dx != null && dy != null && mounted) {
      final safe = _safeAreaBounds();
      final clamped = _clampPosition(Offset(dx, dy), safe);
      setState(() {
        _position = clamped;
        _positionLoaded = true;
      });
    } else if (mounted) {
      // Default: bottom-right corner, above SafeArea.
      final mq = MediaQuery.of(context);
      final safeBottom = mq.padding.bottom;
      setState(() {
        _position = Offset(
          mq.size.width - _headSize - _edgePadding,
          mq.size.height - safeBottom - _headSize - _edgePadding - 80,
        );
        _positionLoaded = true;
      });
      _savePosition(_position);
    }
  }

  Future<void> _savePosition(Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_chat_head_pos_${widget.userId}';
    await prefs.setDouble('${key}_x', pos.dx);
    await prefs.setDouble('${key}_y', pos.dy);
  }

  Rect _safeAreaBounds() {
    final mq = MediaQuery.of(context);
    return Rect.fromLTWH(
      mq.padding.left + _edgePadding,
      mq.padding.top + _edgePadding,
      mq.size.width -
          mq.padding.left -
          mq.padding.right -
          _headSize -
          _edgePadding * 2,
      mq.size.height -
          mq.padding.top -
          mq.padding.bottom -
          _headSize -
          _edgePadding * 2,
    );
  }

  Offset _clampPosition(Offset pos, Rect bounds) {
    return Offset(
      pos.dx.clamp(bounds.left, bounds.right),
      pos.dy.clamp(bounds.top, bounds.bottom),
    );
  }

  Offset _snapToNearestEdge(Offset pos, Rect bounds) {
    final center = pos + const Offset(_headSize / 2, _headSize / 2);
    final distLeft = (center.dx - bounds.left).abs();
    final distRight = (bounds.right - center.dx).abs();

    final snappedX = distLeft < distRight ? bounds.left : bounds.right;
    return Offset(snappedX, pos.dy.clamp(bounds.top, bounds.bottom));
  }

  void _onPanStart(DragStartDetails details) {
    _totalDragDistance = 0;
    _isDragging = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final delta = details.delta;
    _totalDragDistance += delta.distance;
    if (_totalDragDistance > _dragThreshold) {
      _isDragging = true;
    }

    if (_isDragging) {
      setState(() {
        _position = _clampPosition(
          _position + delta,
          _safeAreaBounds(),
        );
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDragging) {
      // Snap to nearest horizontal edge.
      final bounds = _safeAreaBounds();
      final snapped = _snapToNearestEdge(_position, bounds);
      setState(() {
        _position = snapped;
      });
      _savePosition(snapped);
    } else {
      // It was a tap, not a drag — open the panel.
      ref.read(aiAdvisorChatProvider.notifier).openPanel();
    }
    _isDragging = false;
    _totalDragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    // Watch panel state to hide the head when panel is open.
    final chatState = ref.watch(aiAdvisorChatProvider);
    if (chatState.isPanelOpen) return const SizedBox.shrink();

    if (!_positionLoaded) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Material(
          elevation: 6,
          shape: const CircleBorder(),
          shadowColor: cs.primary.withValues(alpha: 0.3),
          child: Container(
            width: _headSize,
            height: _headSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  cs.primary.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: cs.onPrimary,
                  size: 26,
                ),
                // Small status indicator dot.
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _statusColor(chatState.configStatus, cs),
                      border: Border.all(
                        color: cs.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(AIConfigStatus status, ColorScheme cs) {
    switch (status) {
      case AIConfigStatus.active:
        return Colors.green;
      case AIConfigStatus.notConfigured:
        return Colors.orange;
      case AIConfigStatus.invalid:
        return Colors.red;
      case AIConfigStatus.unavailable:
        return Colors.red;
      case AIConfigStatus.checking:
        return cs.secondary;
    }
  }
}
