import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Loads and caches the Inter TTF font assets for use in PDF documents.
///
/// The same Inter family used by the Flutter UI is embedded into generated
/// PDFs so text measurement matches the app's typography.  This prevents
/// the default Helvetica fallback from producing incorrect word-wrap
/// widths (the root cause of the one-character-per-line receipt bug).
///
/// Fonts are loaded once and cached statically for the lifetime of the
/// process, so repeated PDF generation does not re-read the asset.
class PdfFontService {
  PdfFontService._();

  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _medium;
  static pw.Font? _semiBold;

  /// Loads the Inter font assets if they haven't been loaded yet.
  /// Safe to call repeatedly; subsequent calls are no-ops.
  static Future<void> ensureLoaded() async {
    if (_regular != null && _bold != null) return;

    try {
      _regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      _bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      _medium = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Medium.ttf'));
      _semiBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    } catch (e) {
      debugPrint('[PdfFontService] Could not load Inter fonts: $e');
    }
  }

  /// The regular-weight Inter font, or null if loading failed (in which
  /// case the PDF library falls back to Helvetica).
  static pw.Font? get regular => _regular;

  /// The bold-weight Inter font, or null if loading failed.
  static pw.Font? get bold => _bold;

  /// The medium-weight Inter font, or null if loading failed.
  static pw.Font? get medium => _medium;

  /// The semi-bold Inter font, or null if loading failed.
  static pw.Font? get semiBold => _semiBold;

  /// Returns a [pw.ThemeData] that uses Inter as the default font family.
  /// Pass this to [pw.Document] so every widget inherits Inter without
  /// needing to set it explicitly on each [pw.TextStyle].
  static pw.ThemeData theme() {
    return pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
    );
  }

  /// Builds a [pw.TextStyle] using the Inter font at the requested weight.
  static pw.TextStyle style({
    double fontSize = 10,
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) {
    final isBold = fontWeight == pw.FontWeight.bold;
    return pw.TextStyle(
      fontSize: fontSize,
      font: isBold ? _bold : _regular,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// Pre-defined PDF typography sizes. Use these instead of ad-hoc values.
  static pw.TextStyle display({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 24, fontWeight: fontWeight, color: color);

  static pw.TextStyle headline({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 20, fontWeight: fontWeight, color: color);

  static pw.TextStyle title({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 16, fontWeight: fontWeight, color: color);

  static pw.TextStyle subhead({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 12, fontWeight: fontWeight, color: color);

  static pw.TextStyle body({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 10, fontWeight: fontWeight, color: color);

  static pw.TextStyle small({
    pw.FontWeight? fontWeight,
    PdfColorValue? color,
  }) =>
      style(fontSize: 9, fontWeight: fontWeight, color: color);
}

/// Re-export of [PdfColor] so callers can reference [PdfColorValue]
/// without importing the pdf package separately.
typedef PdfColorValue = PdfColor;
