/// A view model that contains everything a receipt UI or PDF needs.
///
/// This is deliberately separate from the raw [Sale] / [SaleItem] models so
/// that the receipt can be rendered without re-querying the database and
/// without depending on current product data.  All values are historical
/// snapshots of the transaction.
class ReceiptViewData {
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String currency;
  final String? receiptFooter;
  final String? storeLogoPath;

  final int saleId;
  final String receiptNumber;
  final DateTime date;
  final String cashierName;

  final String paymentMethod;
  final String paymentStatus;
  final double total;
  final double subtotal;
  final double discount;
  final double cashReceived;
  final double change;
  final String? referenceNumber;
  final String? customerName;
  final String? notes;
  final String? paymentProofPath;

  final List<ReceiptItem> items;

  const ReceiptViewData({
    required this.storeName,
    this.storeAddress = '',
    this.storePhone = '',
    this.currency = 'PHP',
    this.receiptFooter,
    this.storeLogoPath,
    required this.saleId,
    required this.receiptNumber,
    required this.date,
    required this.cashierName,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.total,
    this.subtotal = 0,
    this.discount = 0,
    required this.cashReceived,
    required this.change,
    this.referenceNumber,
    this.customerName,
    this.notes,
    this.paymentProofPath,
    required this.items,
  });

  String get statusLabel {
    final s = paymentStatus;
    if (s.isEmpty) return 'Unknown';
    return s[0].toUpperCase() + s.substring(1);
  }

  String formattedTotal() => '$currency ${total.toStringAsFixed(2)}';
  String formattedSubtotal() => '$currency ${subtotal.toStringAsFixed(2)}';
  String formattedDiscount() => '$currency ${discount.toStringAsFixed(2)}';
  String formattedCashReceived() => '$currency ${cashReceived.toStringAsFixed(2)}';
  String formattedChange() => '$currency ${change.toStringAsFixed(2)}';
}

/// A single line item on a receipt.
class ReceiptItem {
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const ReceiptItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  String formattedUnitPrice(String currency) => '$currency ${unitPrice.toStringAsFixed(2)}';
  String formattedTotal(String currency) => '$currency ${totalPrice.toStringAsFixed(2)}';
}
