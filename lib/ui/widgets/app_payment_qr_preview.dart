import 'package:flutter/material.dart';

import 'package:pinoy_pos/ui/widgets/app_card.dart';
import 'package:pinoy_pos/ui/widgets/app_image.dart';

/// A small, tappable preview of the store's payment QR.
///
/// Displays the QR image from [imagePath] at a size comfortable for the POS
/// form, with a clear "tap to enlarge" cue. When no QR is configured it shows
/// a compact empty state.
///
/// The image is always rendered with [BoxFit.contain] and no cache width so
/// the original QR pixels are preserved.
class AppPaymentQrPreview extends StatelessWidget {
  /// Relative path to the configured QR image, or null/empty if none.
  final String? imagePath;

  /// Called when the user taps the QR preview.
  final VoidCallback? onTap;

  /// Title shown when no QR is configured.
  final String emptyTitle;

  /// Subtitle shown when no QR is configured.
  final String emptySubtitle;

  /// Maximum height of the preview.
  final double maxHeight;

  /// Background color for the empty state. Defaults to [ColorScheme.errorContainer].
  final Color? emptyColor;

  /// Foreground color for the empty state. Defaults to [ColorScheme.onErrorContainer].
  final Color? emptyForegroundColor;

  const AppPaymentQrPreview({
    super.key,
    required this.imagePath,
    this.onTap,
    this.emptyTitle = 'QR payment not configured',
    this.emptySubtitle = 'Configure a payment QR in Payment Settings.',
    this.maxHeight = 240,
    this.emptyColor,
    this.emptyForegroundColor,
  });

  bool get _hasImage => imagePath != null && imagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_hasImage) {
      return _buildEmptyState(cs);
    }

    final preview = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: 1,
        child: AppImage(
          imagePath: imagePath,
          placeholderIcon: Icons.qr_code,
          fit: BoxFit.contain,
          cacheWidth: null,
          semanticLabel: 'Payment QR code',
        ),
      ),
    );

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              preview,
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.fullscreen,
                      size: 18,
                      color: cs.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                'Tap to enlarge',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    final background = emptyColor ?? cs.errorContainer;
    final foreground = emptyForegroundColor ?? cs.onErrorContainer;

    return AppCard(
      color: background,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code, color: foreground, size: 40),
          const SizedBox(height: 8),
          Text(
            emptyTitle,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (emptySubtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                emptySubtitle,
                style: TextStyle(color: foreground),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
