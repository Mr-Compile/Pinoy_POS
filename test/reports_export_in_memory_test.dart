import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/settings.dart';

/// In-memory smoke test for the report export generation logic.
/// This does NOT use FilePicker; it only generates the PDF/Excel bytes
/// that the screen would write to disk, exercising the same table shapes
/// and color coding.
void main() {
  group('Report export byte generation', () {
    final store = Settings(
      storeName: 'Sari-Sari Store Ññ',
      storeAddress: '123 Mabini St.',
      storePhone: '09171234567',
      currency: 'PHP',
      receiptFooter: 'Thank you po!',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Real-world export should only include confirmed (paid) sales.
    final sales = [
      Sale(
        id: 1,
        totalAmount: 100.0,
        cashReceived: 100.0,
        change: 0.0,
        paymentMethod: 'Cash',
        paymentStatus: 'confirmed',
        userId: 1,
        createdAt: DateTime.now(),
        receiptNumber: 'R-0001',
        notes: 'Test sale',
      ),
      Sale(
        id: 2,
        totalAmount: 250.0,
        cashReceived: 250.0,
        change: 0.0,
        paymentMethod: 'GCash',
        paymentStatus: 'pending',
        userId: 1,
        createdAt: DateTime.now(),
        receiptNumber: 'R-0002',
      ),
    ];

    final confirmedSales = sales.where((s) => s.paymentStatus == 'confirmed').toList();

    final items = [
      SaleItem(
        saleId: 1,
        productId: 101,
        productName: 'Test Product',
        quantity: 2,
        unitPrice: 50.0,
        totalPrice: 100.0,
      ),
    ];

    test('can generate PDF report bytes with color-coded tables', () async {
      final pdf = pw.Document();
      final currency = store.currency;
      final brandColor = PdfColor.fromInt(0xFF1565C0);

      PdfColor methodColor(String method) {
        return switch (method.toLowerCase()) {
          'cash' => PdfColor.fromInt(0xFF1565C0),
          'gcash' => PdfColor.fromInt(0xFF2E7D32),
          'card' => PdfColor.fromInt(0xFF7C4DFF),
          _ => PdfColor.fromInt(0xFF757575),
        };
      }

      PdfColor methodBackground(String method) {
        return switch (method.toLowerCase()) {
          'cash' => PdfColor.fromInt(0xFFE3F2FD),
          'gcash' => PdfColor.fromInt(0xFFC8E6C9),
          'card' => PdfColor.fromInt(0xFFD1C4E9),
          _ => PdfColor.fromInt(0xFFF5F5F5),
        };
      }

      pw.Widget headerCell(String text) => pw.Container(
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.all(5),
            color: brandColor,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
            ),
          );

      pw.Widget dataCell(
        String text, {
        PdfColor? backgroundColor,
        PdfColor? textColor,
      }) =>
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            color: backgroundColor,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                color: textColor,
                fontSize: 9,
              ),
            ),
          );

      final headers = [
        'Receipt #',
        'Date/Time',
        'Cashier',
        'Customer',
        'Method',
        'Reference',
        'Items',
        'Total',
      ];

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) => [
            pw.Text(store.storeName),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey400,
                width: 0.5,
              ),
              children: [
                pw.TableRow(children: headers.map(headerCell).toList()),
                ...confirmedSales.map((s) {
                  return pw.TableRow(
                    children: [
                      dataCell('${s.receiptNumber ?? s.id}'),
                      dataCell(s.createdAt.toLocal().toString().split('.')[0]),
                      dataCell('User ${s.userId}'),
                      dataCell(s.customerName ?? ''),
                      dataCell(
                        s.paymentMethod,
                        backgroundColor: methodBackground(s.paymentMethod),
                        textColor: methodColor(s.paymentMethod),
                      ),
                      dataCell(s.referenceNumber ?? ''),
                      dataCell('${items.length}'),
                      dataCell(
                          '$currency ${s.totalAmount.toStringAsFixed(2)}'),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      expect(bytes, isNotEmpty);
    });

    test('can generate Excel report bytes with styled cells and two sheets',
        () async {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final brandBlue = ExcelColor.fromHexString('FF1565C0');
      final white = ExcelColor.white;

      final summary = excel['Sales Summary'];
      summary.cell(CellIndex.indexByString('A1')).value =
          TextCellValue(store.storeName);

      final headerStyle = CellStyle(
        backgroundColorHex: brandBlue,
        fontColorHex: white,
        bold: true,
      );

      final headers = [
        'Receipt #',
        'Date/Time',
        'Product',
        'Qty',
        'Unit Price',
        'Line Total',
      ];

      final lineItems = excel['Line Items'];
      for (var i = 0; i < headers.length; i++) {
        final cell = lineItems.cell(CellIndex.indexByColumnRow(
          columnIndex: i,
          rowIndex: 0,
        ));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      final sale = confirmedSales.first;
      final item = items.first;
      const row = 1;
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        ..value = TextCellValue('${sale.receiptNumber ?? sale.id}')
        ..cellStyle = CellStyle();
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        ..value = TextCellValue(sale.createdAt.toLocal().toString().split('.')[0])
        ..cellStyle = CellStyle();
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
        ..value = TextCellValue(item.productName ?? '')
        ..cellStyle = CellStyle();
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        ..value = IntCellValue(item.quantity)
        ..cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
        ..value = DoubleCellValue(item.unitPrice)
        ..cellStyle = CellStyle(numberFormat: NumFormat.standard_4);
      lineItems.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
        ..value = DoubleCellValue(item.totalPrice)
        ..cellStyle = CellStyle(numberFormat: NumFormat.standard_4);

      final bytes = excel.save();
      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
      expect(excel.sheets.keys, containsAll(["Sales Summary", "Line Items"]));
    });
  });
}
