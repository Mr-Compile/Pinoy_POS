import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/settings.dart';

/// Generates and saves customer receipts.
///
/// Uses the existing [pdf] package and follows the same storage patterns as
/// the reports export screen.
class ReceiptService {
  /// Builds a PDF receipt for the given sale.
  Future<Uint8List> generateReceiptPdf(
    Sale sale,
    List<SaleItem> items,
    Map<int, String> productNames,
    Settings store,
  ) async {
    final pdf = pw.Document();

    final tableData = items
        .map((item) => [
              productNames[item.productId] ?? 'Product #${item.productId}',
              '${item.quantity}',
              '₱${item.unitPrice.toStringAsFixed(2)}',
              '₱${item.totalPrice.toStringAsFixed(2)}',
            ])
        .toList();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  store.storeName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (store.storeAddress.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    store.storeAddress,
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              if (store.storePhone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Contact: ${store.storePhone}',
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Receipt #${sale.receiptNumber ?? sale.id}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  sale.createdAt.toLocal().toString().split('.')[0],
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.TableHelper.fromTextArray(
                headers: ['Item', 'Qty', 'Price', 'Total'],
                data: tableData,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(vertical: 2),
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal'),
                  pw.Text('₱${sale.totalAmount.toStringAsFixed(2)}'),
                ],
              ),
              if (sale.paymentMethod == 'Cash') ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cash Received'),
                    pw.Text('₱${sale.cashReceived.toStringAsFixed(2)}'),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Change'),
                    pw.Text('₱${sale.change.toStringAsFixed(2)}'),
                  ],
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '₱${sale.totalAmount.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Payment Method'),
                  pw.Text(sale.paymentMethod),
                ],
              ),
              if (sale.referenceNumber != null) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Reference'),
                    pw.Text(sale.referenceNumber!),
                  ],
                ),
              ],
              if (sale.customerName != null) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Customer'),
                    pw.Text(sale.customerName!),
                  ],
                ),
              ],
              if (sale.notes != null) ...[
                pw.SizedBox(height: 8),
                pw.Text('Notes: ${sale.notes}', style: const pw.TextStyle(fontSize: 10)),
              ],
              pw.SizedBox(height: 16),
              if (store.receiptFooter != null)
                pw.Center(
                  child: pw.Text(
                    store.receiptFooter!,
                    style: const pw.TextStyle(fontSize: 10),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Thank you!',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  /// Presents a save dialog and writes the receipt bytes to the chosen path.
  /// Returns the saved file path, or null if the user cancels.
  ///
  /// The [dialogTitle] and [fileName] can be customised by the caller.
  Future<String?> saveReceiptToFile(
    Uint8List bytes, {
    String dialogTitle = 'Save Receipt',
    String fileName = 'pinoy_pos_receipt.pdf',
  }) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return null;

    final path = result.toLowerCase().endsWith('.pdf') ? result : '$result.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  /// Generates a PDF receipt and writes it to the application documents
  /// directory for internal viewing/sharing. Returns the absolute path.
  ///
  /// This is a fallback when the user does not want to pick an explicit
  /// download location.
  Future<String?> saveReceiptToAppDocuments(
    Uint8List bytes, {
    String? fileName,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final receiptsDir = Directory(p.join(appDir.path, 'receipts'));
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }

      final name = fileName ?? 'receipt_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(p.join(receiptsDir.path, name));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }
}
