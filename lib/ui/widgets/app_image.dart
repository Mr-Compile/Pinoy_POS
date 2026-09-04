import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pinoy_pos/services/image_service.dart';

/// Reusable image widget that handles loading, missing files, and
/// corrupted images gracefully.
///
/// Displays [placeholder] when [imagePath] is null/empty or when the
/// file cannot be loaded.  Never throws uncaught exceptions.
///
/// On web, [imagePath] is resolved through [ImageService] and displayed
/// via [Image.file] (which works on web via the virtual filesystem
/// provided by path_provider).
class AppImage extends StatefulWidget {
  /// Relative path from the app documents directory, or null/empty
  /// to show the placeholder.
  final String? imagePath;

  /// Icon to display when no image is available or loading fails.
  final IconData placeholderIcon;

  /// Size of the placeholder icon.
  final double placeholderIconSize;

  /// Optional builder for a custom placeholder.
  final WidgetBuilder? placeholderBuilder;

  /// Border radius for the image.
  final double borderRadius;

  /// Whether the image should fill its parent (BoxFit.cover) or
  /// contain (BoxFit.contain).
  final BoxFit fit;

  /// Optional semantic label for accessibility.
  final String? semanticLabel;

  /// Optional width used to resize the decoded image and reduce memory.
  /// Pass `null` to decode the image at its full resolution (useful for
  /// QR codes that must remain sharp when scaled).
  final int? cacheWidth;

  const AppImage({
    super.key,
    required this.imagePath,
    this.placeholderIcon = Icons.inventory_2,
    this.placeholderIconSize = 48,
    this.placeholderBuilder,
    this.borderRadius = 12,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.cacheWidth = 512,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  File? _imageFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imagePath == null || widget.imagePath!.isEmpty) {
      if (mounted) {
        setState(() {
          _imageFile = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final imageService = ImageService();
      final file = await imageService.resolveImageFile(widget.imagePath);
      if (mounted) {
        setState(() {
          _imageFile = file;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageFile = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.file(
          _imageFile!,
          fit: widget.fit,
          semanticLabel: widget.semanticLabel,
          cacheWidth: widget.cacheWidth,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder(
              child: Icon(
                Icons.broken_image_outlined,
                size: widget.placeholderIconSize,
                color: Theme.of(context).colorScheme.outline,
              ),
            );
          },
        ),
      );
    }

    // No image or load failed — show placeholder
    return _buildPlaceholder(
      child: widget.placeholderBuilder != null
          ? widget.placeholderBuilder!(context)
          : Icon(
              widget.placeholderIcon,
              size: widget.placeholderIconSize,
              color: Theme.of(context).colorScheme.primary,
            ),
    );
  }

  Widget _buildPlaceholder({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Center(child: child),
    );
  }
}

/// Circular avatar widget that displays a user's profile image or
/// falls back to initials when no image is available.
///
/// Uses [ImageService] to resolve the relative path.
class AppAvatar extends StatefulWidget {
  /// Relative path from the app documents directory, or null/empty
  /// to show initials.
  final String? imagePath;

  /// Initials to display when no image is available.
  final String initials;

  /// Radius of the avatar circle.
  final double radius;

  /// Optional semantic label.
  final String? semanticLabel;

  const AppAvatar({
    super.key,
    required this.imagePath,
    required this.initials,
    this.radius = 48,
    this.semanticLabel,
  });

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  File? _imageFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imagePath == null || widget.imagePath!.isEmpty) {
      if (mounted) {
        setState(() {
          _imageFile = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final imageService = ImageService();
      final file = await imageService.resolveImageFile(widget.imagePath);
      if (mounted) {
        setState(() {
          _imageFile = file;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageFile = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;

    if (_isLoading) {
      return SizedBox(
        width: diameter,
        height: diameter,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (_imageFile != null) {
      return CircleAvatar(
        radius: widget.radius,
        foregroundImage: FileImage(_imageFile!),
        onForegroundImageError: (exception, stackTrace) {
          // Fall back to initials silently
        },
        child: Text(
          widget.initials.isNotEmpty
              ? widget.initials[0].toUpperCase()
              : '?',
          style: TextStyle(fontSize: widget.radius * 0.6),
        ),
      );
    }

    // No image — show initials
    return CircleAvatar(
      radius: widget.radius,
      child: Text(
        widget.initials.isNotEmpty
            ? widget.initials[0].toUpperCase()
            : '?',
        style: TextStyle(fontSize: widget.radius * 0.6),
      ),
    );
  }
}
