import 'dart:io';

import 'package:flutter/material.dart';

import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/ui/widgets/app_header.dart';
import 'package:pinoy_pos/ui/widgets/loading_state.dart';

/// Full-screen, zoomable payment QR viewer.
///
/// The QR is shown at the largest comfortable size for the current screen,
/// preserving its original aspect ratio. The user can pinch to zoom on mobile
/// and use mouse wheel / trackpad zoom on desktop and web where supported.
/// Pan works when zoomed. The image is never recoloured, tinted, inverted, or
/// cropped.
class AppPaymentQrViewer extends StatefulWidget {
  /// Relative path to the QR image.
  final String imagePath;

  /// Window / app bar title.
  final String title;

  /// Caption shown beneath the QR.
  final String caption;

  const AppPaymentQrViewer({
    super.key,
    required this.imagePath,
    this.title = 'Scan to Pay',
    this.caption = 'Scan this QR code to pay',
  });

  @override
  State<AppPaymentQrViewer> createState() => _AppPaymentQrViewerState();
}

class _AppPaymentQrViewerState extends State<AppPaymentQrViewer> {
  File? _file;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = await ImageService().resolveImageFile(widget.imagePath);
      if (mounted) {
        setState(() {
          _file = file;
          _isLoading = false;
          if (file == null) {
            _error = 'The QR image could not be found.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Unable to load the QR image.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppHeader(
        title: widget.title,
        showBackButton: true,
        showNotificationBell: false,
        showProfileMenu: false,
        showThemeToggle: false,
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_isLoading) {
      return const LoadingState();
    }

    if (_error != null || _file == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text(
                _error ?? 'QR image not available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Configure a payment QR in Payment Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxDimension =
                      constraints.maxWidth < constraints.maxHeight
                          ? constraints.maxWidth
                          : constraints.maxHeight;
                  final size = maxDimension - 48;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Image.file(
                        _file!,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  size: 64, color: cs.outline),
                              const SizedBox(height: 16),
                              Text(
                                'Unable to display this QR image.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.caption,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
