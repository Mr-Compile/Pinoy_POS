import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_code_dart_decoder/qr_code_dart_decoder.dart';
import 'package:zxing_lib/common.dart' as zxing_common;
import 'package:zxing_lib/multi.dart' as zxing_multi;
import 'package:zxing_lib/zxing.dart' as zxing;

import 'image_service.dart';

/// Outcome of a QR preview generation attempt.
class QrPreviewResult {
  /// Relative path to the generated preview image, or null when the original
  /// image should be used as the fallback.
  final String? previewPath;

  /// Relative path to the original uploaded merchant image.
  final String? originalPath;

  /// Whether a QR code was detected and a preview generated.
  final bool wasDetected;

  /// A short, human-readable message about the result.
  final String? message;

  const QrPreviewResult({
    this.previewPath,
    this.originalPath,
    this.wasDetected = false,
    this.message,
  });

  bool get hasPreview => previewPath != null && previewPath!.isNotEmpty;
}

/// Coordinates of a detected QR code in image space.
class _QrBounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const _QrBounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  int get left => minX.floor();
  int get top => minY.floor();
  int get right => maxX.ceil();
  int get bottom => maxY.ceil();
  int get width => right - left;
  int get height => bottom - top;
  int get area => width * height;
}

/// Service for detecting a QR code inside a merchant-uploaded image and
/// generating a cropped, scan-friendly preview while preserving the original.
class PaymentQrService {
  final ImageService _imageService;

  PaymentQrService({ImageService? imageService})
      : _imageService = imageService ?? ImageService();

  static const double _paddingRatio = 0.15;
  static const int _minPadding = 24;
  static const String _previewSuffix = '_preview';

  /// Detects the QR code in [originalRelativePath], crops it with a safe
  /// margin, and writes the preview to app-controlled storage.
  ///
  /// Returns [QrPreviewResult.previewPath] when a preview was generated, or
  /// [QrPreviewResult.originalPath] when detection fails and the original
  /// should be displayed.
  Future<QrPreviewResult> generatePreview(String? originalRelativePath) async {
    if (originalRelativePath == null || originalRelativePath.trim().isEmpty) {
      return const QrPreviewResult();
    }

    final file = await _imageService.resolveImageFile(originalRelativePath);
    if (file == null) {
      return QrPreviewResult(
        originalPath: originalRelativePath,
        message: 'Original image file not found.',
      );
    }

    final bytes = await file.readAsBytes();
    final sourceImage = img.decodeImage(bytes);
    if (sourceImage == null) {
      return QrPreviewResult(
        originalPath: originalRelativePath,
        message: 'Could not decode the uploaded image.',
      );
    }

    final bounds = await _detectBestQr(sourceImage, bytes);
    if (bounds == null) {
      return QrPreviewResult(
        originalPath: originalRelativePath,
        wasDetected: false,
        message: 'QR code could not be detected automatically. '
            'The original image will be used.',
      );
    }

    final cropRect = _computeCropRect(
      bounds,
      sourceImage.width,
      sourceImage.height,
    );
    final cropped = img.copyCrop(
      sourceImage,
      x: cropRect.left,
      y: cropRect.top,
      width: cropRect.width,
      height: cropRect.height,
    );

    // PNG is used for the preview to avoid introducing JPEG compression
    // artifacts that could make the QR harder to scan.
    final previewBytes = img.encodePng(cropped);
    final previewPath = await _writePreviewFile(
      originalRelativePath,
      previewBytes,
    );

    return QrPreviewResult(
      previewPath: previewPath,
      originalPath: originalRelativePath,
      wasDetected: true,
      message: 'QR preview generated.',
    );
  }

  /// Deletes a previously generated preview file. Safe to call with null.
  Future<void> deletePreview(String? previewRelativePath) async {
    if (previewRelativePath == null || previewRelativePath.isEmpty) return;
    await _imageService.deleteImage(previewRelativePath);
  }

  /// Deletes any existing preview that belongs to the original image before
  /// replacing it. Used when the merchant uploads a new QR.
  Future<void> deletePreviewForOriginal(String? originalRelativePath) async {
    if (originalRelativePath == null || originalRelativePath.isEmpty) return;
    final previewPath = _previewPathForOriginal(originalRelativePath);
    await deletePreview(previewPath);
  }

  /// Runs multiple detection strategies and returns the bounding box of the
  /// largest QR code found, or null when no QR is detected.
  Future<_QrBounds?> _detectBestQr(img.Image image, Uint8List originalBytes) async {
    final results = await _detectWithZxing(image);

    if (results.isEmpty) {
      final fallback = await _detectWithDartDecoder(originalBytes);
      if (fallback != null) return fallback;
      return null;
    }

    if (results.length == 1) return results.first;

    // Choose the largest QR when the image contains several codes.
    _QrBounds? best;
    var bestArea = -1;
    for (final bounds in results) {
      if (bounds.area > bestArea) {
        bestArea = bounds.area;
        best = bounds;
      }
    }
    return best;
  }

  /// Detects QR codes using the ZXing multi-reader.
  Future<List<_QrBounds>> _detectWithZxing(img.Image image) async {
    try {
      final rgbaImage = image.convert(
        format: img.Format.uint8,
        numChannels: 4,
      );
      final rgbaBytes = rgbaImage.toUint8List();
      final luminances = _toLuminance(rgbaBytes, image.width, image.height);
      final source = zxing.RGBLuminanceSource.orig(
        image.width,
        image.height,
        luminances,
      );
      final bitmap = zxing.BinaryBitmap(zxing_common.HybridBinarizer(source));
      final reader = zxing_multi.QRCodeMultiReader();

      final results = reader.decodeMultiple(
        bitmap,
        const zxing.DecodeHint(
          tryHarder: true,
          alsoInverted: true,
        ),
      );

      return results
          .where((r) => r.resultPoints != null && r.resultPoints!.isNotEmpty)
          .map((r) => _boundsFromPoints(r.resultPoints!))
          .toList();
    } on zxing.NotFoundException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Fallback single-QR detection using the dart decoder, which has stronger
  /// pre-processing (background cropping/inversion) for hard images.
  Future<_QrBounds?> _detectWithDartDecoder(Uint8List originalBytes) async {
    try {
      final decoder = QrCodeDartDecoder(
        formats: [BarcodeFormat.qrCode],
      );
      final result = await decoder.decodeFile(originalBytes);
      if (result == null || result.corners.isEmpty) return null;
      return _boundsFromCorners(result.corners);
    } catch (_) {
      return null;
    }
  }

  Uint8List _toLuminance(Uint8List rgba, int width, int height) {
    final pixelCount = width * height;
    final luminances = Uint8List(pixelCount);
    for (var i = 0, j = 0; i < pixelCount; i++, j += 4) {
      final r = rgba[j];
      final g = rgba[j + 1];
      final b = rgba[j + 2];
      // Green-weighted average matching ZXing's RGBLuminanceSource.
      luminances[i] = ((r + (g << 1) + b) ~/ 4);
    }
    return luminances;
  }

  _QrBounds _boundsFromPoints(List<zxing.ResultPoint?> points) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final point in points) {
      if (point == null) continue;
      final x = point.x;
      final y = point.y;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    return _QrBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  _QrBounds _boundsFromCorners(List<math.Point<double>> corners) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final point in corners) {
      final x = point.x;
      final y = point.y;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    return _QrBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  _QrBounds _computeCropRect(_QrBounds bounds, int imageWidth, int imageHeight) {
    final qrSize = math.max(bounds.width, bounds.height);
    final padding = math.max(_minPadding, (qrSize * _paddingRatio).round());

    var left = bounds.left - padding;
    var top = bounds.top - padding;
    var right = bounds.right + padding;
    var bottom = bounds.bottom + padding;

    // Clamp to image bounds.
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > imageWidth) right = imageWidth;
    if (bottom > imageHeight) bottom = imageHeight;

    return _QrBounds(
      minX: left.toDouble(),
      minY: top.toDouble(),
      maxX: right.toDouble(),
      maxY: bottom.toDouble(),
    );
  }

  Future<String?> _writePreviewFile(
    String originalRelativePath,
    Uint8List previewBytes,
  ) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final previewPath = _previewPathForOriginal(originalRelativePath);
      final absolutePath = p.join(appDir.path, previewPath);

      final dir = Directory(p.dirname(absolutePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File(absolutePath);
      await file.writeAsBytes(previewBytes);
      return previewPath;
    } catch (_) {
      return null;
    }
  }

  String _previewPathForOriginal(String originalRelativePath) {
    final dir = p.dirname(originalRelativePath);
    final base = p.basenameWithoutExtension(originalRelativePath);
    final fileName = '$base$_previewSuffix.png';
    return p.join(dir, fileName);
  }
}
