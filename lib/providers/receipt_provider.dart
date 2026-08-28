import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/providers/service_providers.dart';

/// Loads a [ReceiptViewData] for a given sale id.
///
/// Both the on-screen receipt and the PDF generator can watch this provider
/// so the receipt preview and downloaded PDF always show the same data.
final receiptViewDataProvider =
    FutureProvider.family<ReceiptViewData?, int>((ref, saleId) async {
  final salesService = ref.watch(salesServiceProvider);
  return salesService.getReceiptViewData(saleId);
});
