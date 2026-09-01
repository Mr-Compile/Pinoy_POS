import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/services/file_export_service.dart';
import 'package:pinoy_pos/services/image_service.dart';

/// Generates and saves customer receipts.
///
/// All rendering uses a stable 80mm thermal-receipt page format with generous
/// word-wrapping so product names, store names and references do not render
/// one character per line.
class ReceiptService {
  final ImageService _imageService = ImageService();

  /// Builds a PDF receipt for the given sale.
  Future<Uint8List> generateReceiptPdf(ReceiptViewData receipt) async {
    final pdf = pw.Document();

    final pageFormat = PdfPageFormat.roll80;
    final currency = receipt.currency;

    // Load store logo bytes if a logo path is configured.
    pw.ImageProvider? logoProvider;
    if (receipt.storeLogoPath != null && receipt.storeLogoPath!.isNotEmpty) {
      try {
        final file = await _imageService.resolveImageFile(receipt.storeLogoPath);
        if (file != null) {
          final bytes = await file.readAsBytes();
          logoProvider = pw.MemoryImage(bytes);
        }
      } catch (_) {
        // Omit the logo if it cannot be loaded.
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(8),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildStoreHeader(receipt, logoProvider),
              _buildTransactionHeader(receipt),
              pw.Divider(),
              _buildItems(receipt, currency),
              pw.Divider(),
              _buildTotals(receipt, currency),
              pw.Divider(),
              _buildPaymentInfo(receipt, currency),
              if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                _buildNotes(receipt),
              ],
              pw.SizedBox(height: 16),
              _buildFooter(receipt),
            ],
          );
        },
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  pw.Widget _buildStoreHeader(
    ReceiptViewData receipt,
    pw.ImageProvider? logo,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Image(logo, width: 48, height: 48),
          ),
        pw.Center(
          child: pw.Text(
            receipt.storeName,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
            softWrap: true,
          ),
        ),
        if (receipt.storeAddress.isNotEmpty)
          pw.Center(
            child: pw.Text(
              receipt.storeAddress,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
              softWrap: true,
            ),
          ),
        if (receipt.storePhone.isNotEmpty)
          pw.Center(
            child: pw.Text(
              'Contact: ${receipt.storePhone}',
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
              softWrap: true,
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTransactionHeader(ReceiptViewData receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'OFFICIAL RECEIPT',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'Receipt #${receipt.receiptNumber}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
        pw.Center(
          child: pw.Text(
            receipt.date.toLocal().toString().split('.')[0],
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Cashier: ${receipt.cashierName}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _buildItems(ReceiptViewData receipt, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'Item',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Text(
              'Total',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        ...receipt.items.map((item) => _buildItemRow(item, currency)),
      ],
    );
  }

  pw.Widget _buildItemRow(ReceiptItem item, String currency) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  item.productName,
                  style: const pw.TextStyle(fontSize: 10),
                  softWrap: true,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                item.formattedTotal(currency),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
          pw.Text(
            '${item.quantity} x ${item.formattedUnitPrice(currency)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTotals(ReceiptViewData receipt, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildValueRow('Subtotal', receipt.formattedSubtotal()),
        if (receipt.discount > 0)
          _buildValueRow('Discount', receipt.formattedDiscount()),
        _buildValueRow(
          'TOTAL',
          receipt.formattedTotal(),
          isBold: true,
        ),
      ],
    );
  }

  pw.Widget _buildPaymentInfo(ReceiptViewData receipt, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildValueRow('Payment Method', receipt.paymentMethod),
        if (receipt.cashReceived > 0)
          _buildValueRow('Amount Paid', receipt.formattedCashReceived()),
        if (receipt.change > 0)
          _buildValueRow('Change', receipt.formattedChange()),
        if (receipt.referenceNumber != null &&
            receipt.referenceNumber!.isNotEmpty)
          _buildValueRow('Reference', receipt.referenceNumber!),
        if (receipt.customerName != null && receipt.customerName!.isNotEmpty)
          _buildValueRow('Customer', receipt.customerName!),
        _buildValueRow('Status', receipt.statusLabel),
      ],
    );
  }

  pw.Widget _buildNotes(ReceiptViewData receipt) {
    return pw.Text(
      'Notes: ${receipt.notes}',
      style: const pw.TextStyle(fontSize: 9),
      softWrap: true,
    );
  }

  pw.Widget _buildFooter(ReceiptViewData receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (receipt.receiptFooter != null && receipt.receiptFooter!.isNotEmpty)
          pw.Center(
            child: pw.Text(
              receipt.receiptFooter!,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
              softWrap: true,
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'Thank you!',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildValueRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: isBold
                  ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  : const pw.TextStyle(),
              softWrap: true,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            value,
            style: isBold
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                : const pw.TextStyle(),
          ),
        ],
      ),
    );
  }

  /// Generates a filename such as `PinoyPOS_Receipt_000123_2026-08-28.pdf`.
  String buildFileName(ReceiptViewData receipt) {
    final date = receipt.date.toLocal().toString().split(' ')[0];
    final raw = 'PinoyPOS_Receipt_${receipt.receiptNumber}_$date';
    // Sanitize Windows/Android/Linux invalid filename characters.
    return raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(' ', '_');
  }

  /// Presents a save dialog and writes the receipt bytes to the chosen path.
  /// Returns the saved file path, or null if the user cancels.
  Future<String?> saveReceiptToFile(
    Uint8List bytes, {
    String dialogTitle = 'Save Receipt',
    String fileName = 'pinoy_pos_receipt.pdf',
  }) async {
    return FileExportService.saveBytes(
      bytes: bytes,
      fileName: fileName,
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
  }

  /// Generates a PDF receipt and writes it to the application documents
  /// directory (or a platform-safe fallback) for internal viewing/sharing.
  /// Returns the absolute path.
  ///
  /// This is a fallback when the user does not want to pick an explicit
  /// download location.
  Future<String?> saveReceiptToAppDocuments(
    Uint8List bytes, {
    String? fileName,
  }) async {
    Directory? dir;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(appDir.path, 'receipts'));
    } catch (_) {
      try {
        final tempDir = await getTemporaryDirectory();
        dir = Directory(p.join(tempDir.path, 'pinoy_pos_receipts'));
      } catch (_) {
        // Last resort: use the system temp directory.
        dir = Directory.systemTemp;
      }
    }

    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final name =
          fileName ?? 'receipt_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
