import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/settings.dart';

/// In-memory smoke test for the report export generation logic.
/// This does NOT use FilePicker; it only generates the PDF/Excel bytes
/// that the screen would write to disk.
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

    final sales = [
      Sale(
        id: 1,
        totalAmount: 100.0,
        cashReceived: 150.0,
        change: 50.0,
        paymentMethod: 'Cash',
        userId: 1,
        createdAt: DateTime.now(),
        receiptNumber: 'R-0001',
        notes: 'Test sale',
      ),
    ];

    test('can generate PDF report bytes', () async {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) => [
            pw.Text(store.storeName),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Receipt #', 'Date', 'Method', 'Total', 'Cash', 'Change'],
              data: sales
                  .map((s) => [
                        '${s.receiptNumber ?? s.id}',
                        s.createdAt.toLocal().toString().split('.')[0],
                        s.paymentMethod,
                        'PHP ${s.totalAmount.toStringAsFixed(2)}',
                        'PHP ${s.cashReceived.toStringAsFixed(2)}',
                        'PHP ${s.change.toStringAsFixed(2)}',
                      ])
                  .toList(),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      expect(bytes, isNotEmpty);
    });

    test('can generate Excel report bytes', () async {
      final excel = Excel.createExcel();
      final sheet = excel['Sales Report'];
      excel.delete('Sheet1');

      sheet.cell(CellIndex.indexByString('A1')).value =
          TextCellValue(store.storeName);

      for (final s in sales) {
        sheet.appendRow([
          TextCellValue('${s.receiptNumber ?? s.id}'),
          TextCellValue(s.createdAt.toLocal().toString().split('.')[0]),
          TextCellValue(s.paymentMethod),
          DoubleCellValue(s.totalAmount),
          DoubleCellValue(s.cashReceived),
          DoubleCellValue(s.change),
          TextCellValue(s.notes ?? ''),
        ]);
      }

      final bytes = excel.save();
      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    });
  });
}
