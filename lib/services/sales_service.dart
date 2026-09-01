import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/payment_validation_exception.dart';
import 'package:pinoy_pos/core/security.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/payment_settings.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/sale_item.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/repositories/product_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';
import 'package:pinoy_pos/data/repositories/stock_history_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/data/models/stock_history.dart';
import 'package:pinoy_pos/services/activity_log_service.dart';
import 'package:pinoy_pos/services/image_service.dart';
import 'package:pinoy_pos/services/settings_service.dart';
import 'package:pinoy_pos/services/stock_service.dart';
import 'package:sqflite/sqflite.dart';

class SalesService {
  final SaleRepository _saleRepository = SaleRepository();
  final SaleItemRepository _saleItemRepository = SaleItemRepository();
  final StockService _stockService = StockService();
  final SessionManager _sessionManager = SessionManager();
  final ActivityLogService _activityLogService = ActivityLogService();
  final ProductRepository _productRepository = ProductRepository();
  final StockHistoryRepository _stockHistoryRepository = StockHistoryRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SettingsService _settingsService = SettingsService();
  final ImageService _imageService = ImageService();
  final UserRepository _userRepository = UserRepository();

  /// Returns the current user's non-null id.
  ///
  /// Throws [AuthorizationException] for [permission] when the user is not
  /// logged in or their id is missing.
  int _currentUserId(String permission) {
    final user = _sessionManager.currentUser;
    if (user == null) {
      throw AuthorizationException(permission);
    }
    final id = user.id;
    if (id == null) {
      throw AuthorizationException(permission);
    }
    return id;
  }

  Future<List<Sale>> getSales() async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return [];
    }

    final currentUser = _sessionManager.currentUser;
    final userId = currentUser?.role == UserRole.staff
        ? _currentUserId('view_sales')
        : null;

    return _saleRepository.getFilteredSales(userId: userId, limit: 500);
  }

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return [];
    }

    final currentUser = _sessionManager.currentUser;
    final userId = currentUser?.role == UserRole.staff
        ? _currentUserId('view_sales')
        : null;

    return _saleRepository.getFilteredSales(
      start: start,
      end: end,
      userId: userId,
      limit: 500,
    );
  }

  Future<List<Sale>> getFilteredSales({
    DateTime? start,
    DateTime? end,
    String? paymentMethod,
    String? paymentStatus,
    String? search,
    int limit = 500,
  }) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return [];
    }

    final currentUser = _sessionManager.currentUser;
    final userId = currentUser?.role == UserRole.staff
        ? _currentUserId('view_sales')
        : null;

    return _saleRepository.getFilteredSales(
      start: start,
      end: end,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      search: search,
      userId: userId,
      limit: limit,
    );
  }

  Future<Sale?> getSaleById(int id) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return null;
    }

    final sale = await _saleRepository.getById(id);

    if (sale == null) return null;

    final currentUser = _sessionManager.currentUser;
    if (currentUser?.role == UserRole.staff &&
        sale.userId != currentUser?.id) {
      return null;
    }

    return sale;
  }

  Future<Sale?> getLatestSale() async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return null;
    }

    final currentUser = _sessionManager.currentUser;
    final userId = currentUser?.role == UserRole.staff
        ? _currentUserId('view_sales')
        : null;

    final sales = await _saleRepository.getFilteredSales(
      userId: userId,
      limit: 1,
    );

    return sales.isNotEmpty ? sales.first : null;
  }

  Future<List<SaleItem>> getSaleItems(int saleId) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return [];
    }

    // For Staff, verify the sale belongs to the current user before
    // returning items. This prevents accessing another user's sale items
    // by simply knowing the sale id.
    final currentUser = _sessionManager.currentUser;
    if (currentUser?.role == UserRole.staff) {
      final sale = await _saleRepository.getById(saleId);
      if (sale == null || sale.userId != currentUser?.id) {
        return [];
      }
    }

    return _saleItemRepository.getBySaleId(saleId);
  }

  /// Builds a [ReceiptViewData] for the given sale id.
  ///
  /// Returns null if the sale cannot be found or the current user is not
  /// allowed to view it.  Product names are read from the persisted
  /// [SaleItem.productName] when available; older records fall back to the
  /// current product name.
  Future<ReceiptViewData?> getReceiptViewData(int saleId) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return null;
    }

    final sale = await _saleRepository.getById(saleId);
    if (sale == null) return null;

    final currentUser = _sessionManager.currentUser;
    if (currentUser?.role == UserRole.staff &&
        sale.userId != currentUser?.id) {
      return null;
    }

    final items = await _saleItemRepository.getBySaleId(saleId);
    final store = await _settingsService.getStoreInfo();
    final cashier = await _userRepository.getById(sale.userId);

    final receiptItems = <ReceiptItem>[];
    for (final item in items) {
      String name = item.productName ?? '';
      if (name.isEmpty) {
        final product = await _productRepository.getById(item.productId);
        name = product?.name ?? 'Product #${item.productId}';
      }
      receiptItems.add(ReceiptItem(
        productId: item.productId,
        productName: name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        totalPrice: item.totalPrice,
      ));
    }

    final subtotal = receiptItems.fold<double>(
      0.0,
      (sum, item) => sum + item.totalPrice,
    );
    final discount = (subtotal - sale.totalAmount).clamp(0.0, subtotal);

    return ReceiptViewData(
      storeName: store.storeName,
      storeAddress: store.storeAddress,
      storePhone: store.storePhone,
      currency: store.currency,
      receiptFooter: store.receiptFooter,
      storeLogoPath: null,
      saleId: sale.id!,
      receiptNumber: sale.receiptNumber ?? sale.id!.toString(),
      date: sale.createdAt,
      cashierName: cashier?.fullName ?? cashier?.username ?? 'Unknown',
      paymentMethod: sale.paymentMethod,
      paymentStatus: sale.paymentStatus,
      total: sale.totalAmount,
      subtotal: subtotal,
      discount: discount,
      cashReceived: sale.cashReceived,
      change: sale.change,
      referenceNumber: sale.referenceNumber,
      customerName: sale.customerName,
      notes: sale.notes,
      paymentProofPath: sale.paymentProofPath,
      items: receiptItems,
    );
  }

  /// Create a sale within a single atomic transaction.
  ///
  /// Steps:
  /// 1. Validate all items have sufficient stock (pre-check).
  /// 2. Validate payment rules (cash, GCash reference, customer, proof).
  /// 3. Insert sale record.
  /// 4. Insert sale_items.
  /// 5. Deduct stock for each item.
  /// 6. If any step fails, the transaction rolls back automatically.
  ///
  /// Throws [PaymentValidationException] for validation errors such as
  /// missing required GCash fields or duplicate reference numbers.
  Future<bool> createSale({
    required List<SaleItem> items,
    required double totalAmount,
    double? cashReceived,
    String? notes,
    String paymentMethod = 'Cash',
    String? referenceNumber,
    String? customerName,
    String? paymentProofPath,
    String? paymentProofType,
  }) async {
    if (!_sessionManager.hasPermission('create_sales')) {
      await _activityLogService.logActivity(
        action: 'unauthorized_create_sale',
        entity: 'sale',
        details: 'Attempted to create sale without permission',
      );
      throw AuthorizationException('create_sales');
    }

    if (items.isEmpty) {
      throw PaymentValidationException('Cart is empty.');
    }

    _validateCart(items, totalAmount);

    // Load payment settings so GCash rules are applied immediately.
    final PaymentSettings paymentSettings;
    try {
      paymentSettings = await _settingsService.getPaymentSettings();
    } on AuthorizationException catch (_) {
      // Staff must be able to read payment settings to create a sale.
      rethrow;
    }

    var received = cashReceived ?? totalAmount;
    final trimmedReference = referenceNumber?.trim();
    final trimmedCustomer = customerName?.trim();
    final trimmedNotes = notes?.trim();

    // ── Payment-method-specific validation ───────────────────────────────

    if (paymentMethod == 'Cash') {
      if (received < totalAmount) {
        throw PaymentValidationException(
          'Insufficient cash received',
          details: 'Received ₱${received.toStringAsFixed(2)} but total is ₱${totalAmount.toStringAsFixed(2)}.',
        );
      }
    } else {
      // Non-cash payments must match the total exactly.
      received = totalAmount;
    }

    String paymentStatus = 'confirmed';
    DateTime? verifiedAt;
    int? verifiedBy;

    if (paymentMethod == 'GCash') {
      if (!paymentSettings.gcashEnabled) {
        throw PaymentValidationException('GCash payments are currently disabled.');
      }

      if (paymentSettings.gcashReferenceRequired) {
        if (trimmedReference == null || trimmedReference.isEmpty) {
          throw PaymentValidationException(
            'GCash reference number is required',
            details: 'Enter the reference number from the GCash transaction.',
          );
        }
        if (trimmedReference.length < paymentSettings.gcashReferenceMinLength) {
          throw PaymentValidationException(
            'GCash reference number is too short',
            details: 'Reference number must be at least ${paymentSettings.gcashReferenceMinLength} characters.',
          );
        }
      }

      if (paymentSettings.customerNameRequired &&
          (trimmedCustomer == null || trimmedCustomer.isEmpty)) {
        throw PaymentValidationException(
          'Customer name is required',
          details: 'Enter the customer name for this GCash payment.',
        );
      }

      if (paymentSettings.paymentProofRequired &&
          (paymentProofPath == null || paymentProofPath.isEmpty)) {
        throw PaymentValidationException(
          'Payment proof is required',
          details: 'Take or choose a photo of the GCash payment.',
        );
      }

      if (paymentSettings.verificationRequired) {
        paymentStatus = 'pending';
      }
    }

    // Pre-check stock availability and snapshot historical product names.
    final itemsWithNames = <SaleItem>[];
    for (final item in items) {
      final product = await _productRepository.getById(item.productId);
      if (product == null) {
        throw PaymentValidationException('Product not found.');
      }
      if (product.stock < item.quantity) {
        throw PaymentValidationException(
          'Insufficient stock for ${product.name}',
          details: 'Available: ${product.stock}, requested: ${item.quantity}.',
        );
      }
      itemsWithNames.add(item.copyWith(productName: product.name));
    }

    String? committedProofPath;

    try {
      return await _dbHelper.transaction((txn) async {
        // For GCash, check duplicate reference inside the transaction so the
        // check is part of the same atomic unit.
        if (paymentMethod == 'GCash' &&
            trimmedReference != null &&
            trimmedReference.isNotEmpty) {
          final existing = await _saleRepository.findByReferenceNumber(
            trimmedReference,
            paymentMethod,
            txn: txn,
          );
          if (existing != null) {
            throw PaymentValidationException(
              'This GCash reference number has already been used',
              details: 'Use a different reference number to continue.',
            );
          }
        }

        final change = received - totalAmount;
        final receiptNumber = SecurityHelper.generateReceiptNumber();

        var sale = Sale(
          totalAmount: totalAmount,
          cashReceived: received,
          change: change,
          paymentMethod: paymentMethod,
          paymentStatus: paymentStatus,
          referenceNumber: trimmedReference?.isNotEmpty == true ? trimmedReference : null,
          customerName: trimmedCustomer?.isNotEmpty == true ? trimmedCustomer : null,
          paymentProofPath: paymentProofPath,
          paymentProofType: paymentProofType ??
              (paymentProofPath != null && paymentProofPath.isNotEmpty ? 'image' : null),
          verifiedAt: verifiedAt,
          verifiedBy: verifiedBy,
          userId: _currentUserId('create_sales'),
          createdAt: DateTime.now(),
          receiptNumber: receiptNumber,
          notes: trimmedNotes?.isNotEmpty == true ? trimmedNotes : null,
        );

        final saleId = await _saleRepository.insert(sale, txn: txn);

        for (var item in itemsWithNames) {
          final saleItem = item.copyWith(saleId: saleId);
          await _saleItemRepository.insert(saleItem, txn: txn);

          final stockDeducted = await _stockService.deductStockForSale(
            item.productId,
            item.quantity,
            txn: txn,
          );

          if (!stockDeducted) {
            // Throwing inside a transaction causes automatic rollback
            throw Exception('Insufficient stock for product ${item.productId}');
          }
        }

        // Move payment proof from its temporary checkout location into a
        // predictable sale-owned directory after the sale has an id.
        if (paymentProofPath != null && paymentProofPath.isNotEmpty) {
          final fileName = paymentProofPath.split('/').last;
          final newPath = 'payment_evidence/sale_$saleId/$fileName';
          final moved = await _imageService.moveImage(paymentProofPath, newPath);
          if (moved != null) {
            committedProofPath = moved;
            sale = sale.copyWith(id: saleId, paymentProofPath: moved);
            await _saleRepository.update(sale, txn: txn);
          } else {
            throw PaymentValidationException(
              'Unable to save payment proof',
              details: 'The payment evidence could not be moved to the sale directory.',
            );
          }
        }

        // Log activity
        await _activityLogService.logActivity(
          action: 'create_sale',
          entity: 'sale',
          entityId: saleId,
          details: 'Sale $receiptNumber created for ₱${totalAmount.toStringAsFixed(2)}',
          txn: txn,
        );

        if (paymentMethod == 'GCash') {
          await _activityLogService.logActivity(
            action: 'gcash_payment_created',
            entity: 'sale',
            entityId: saleId,
            details: 'Reference: $trimmedReference; Status: $paymentStatus',
            txn: txn,
          );

          if (paymentStatus == 'confirmed') {
            await _activityLogService.logActivity(
              action: 'gcash_payment_confirmed',
              entity: 'sale',
              entityId: saleId,
              details: 'Reference: $trimmedReference',
              txn: txn,
            );
          }

          if (committedProofPath != null) {
            await _activityLogService.logActivity(
              action: 'gcash_payment_evidence_added',
              entity: 'sale',
              entityId: saleId,
              details: 'Reference: $trimmedReference',
              txn: txn,
            );
          }
        }

        return true;
      });
    } on PaymentValidationException {
      await _cleanupPaymentProof(committedProofPath ?? paymentProofPath);
      rethrow;
    } catch (e) {
      await _cleanupPaymentProof(committedProofPath ?? paymentProofPath);
      throw PaymentValidationException(
        'Failed to complete the sale',
        details: 'An unexpected error occurred: $e',
      );
    }
  }

  Future<void> _cleanupPaymentProof(String? path) async {
    if (path != null && path.isNotEmpty) {
      await _imageService.deleteImage(path);
    }
  }

  static const _kPriceEpsilon = 0.01;

  void _validateCart(List<SaleItem> items, double totalAmount) {
    if (totalAmount < 0) {
      throw PaymentValidationException('Total amount cannot be negative.');
    }

    var computedTotal = 0.0;
    for (final item in items) {
      if (item.productId <= 0) {
        throw PaymentValidationException('Invalid product in cart.');
      }
      if (item.quantity <= 0) {
        throw PaymentValidationException(
          'Quantity must be greater than zero',
          details: 'Product #${item.productId} has quantity ${item.quantity}.',
        );
      }
      if (item.unitPrice < 0) {
        throw PaymentValidationException(
          'Unit price cannot be negative',
          details: 'Product #${item.productId} has unit price ${item.unitPrice}.',
        );
      }
      final expectedLineTotal = item.quantity * item.unitPrice;
      if ((expectedLineTotal - item.totalPrice).abs() > _kPriceEpsilon) {
        throw PaymentValidationException(
          'Line total does not match for product #${item.productId}',
          details:
              'Expected ${expectedLineTotal.toStringAsFixed(2)}, got ${item.totalPrice.toStringAsFixed(2)}.',
        );
      }
      computedTotal += item.totalPrice;
    }

    if ((computedTotal - totalAmount).abs() > _kPriceEpsilon) {
      throw PaymentValidationException(
        'Cart total does not match the item total',
        details:
            'Expected ${computedTotal.toStringAsFixed(2)}, got ${totalAmount.toStringAsFixed(2)}.',
      );
    }
  }

  /// Returns true when the current user is allowed to verify GCash
  /// payments for the configured verification mode.
  Future<bool> _canVerify() async {
    if (!_sessionManager.hasPermission('verify_payments')) return false;

    final paymentSettings = await _settingsService.getPaymentSettings();
    final currentUser = _sessionManager.currentUser;
    if (currentUser == null) return false;

    final mode = paymentSettings.gcashVerificationMode;
    if (mode == 'owner' && currentUser.role != UserRole.owner) return false;
    if (mode == 'admin' && currentUser.role != UserRole.admin) return false;

    return true;
  }

  /// Returns all GCash payments that are pending owner/admin verification.
  Future<List<Sale>> getPendingPayments() async {
    if (!await _canVerify()) {
      return [];
    }
    return _saleRepository.getPendingPayments(limit: 500);
  }

  /// Confirm a pending GCash payment. Only Owner/Admin can confirm.
  ///
  /// Returns true when the sale is updated to confirmed, or false if the
  /// sale is not in a pending state.
  Future<bool> confirmGcashPayment(int saleId) async {
    if (!await _canVerify()) {
      await _activityLogService.logActivity(
        action: 'unauthorized_confirm_gcash',
        entity: 'sale',
        entityId: saleId,
        details: 'Attempted to confirm GCash payment without permission',
      );
      throw AuthorizationException('verify_payments');
    }

    return await _dbHelper.transaction((txn) async {
      final sale = await _saleRepository.getById(saleId, txn: txn);
      if (sale == null || sale.paymentStatus != 'pending') return false;

      final updated = sale.copyWith(
        paymentStatus: 'confirmed',
        verifiedAt: DateTime.now(),
        verifiedBy: _currentUserId('verify_payments'),
      );

      await _saleRepository.update(updated, txn: txn);

      await _activityLogService.logActivity(
        action: 'gcash_payment_confirmed',
        entity: 'sale',
        entityId: saleId,
        details: 'Reference: ${sale.referenceNumber}',
        txn: txn,
      );

      return true;
    });
  }

  /// Reject a pending GCash payment. Restores stock, sets the payment status
  /// to 'cancelled', and removes any associated payment evidence.
  ///
  /// Only Owner/Admin can reject.
  Future<bool> rejectGcashPayment(int saleId, {String? reason}) async {
    if (!await _canVerify()) {
      await _activityLogService.logActivity(
        action: 'unauthorized_reject_gcash',
        entity: 'sale',
        entityId: saleId,
        details: 'Attempted to reject GCash payment without permission',
      );
      throw AuthorizationException('verify_payments');
    }

    return await _dbHelper.transaction((txn) async {
      final sale = await _saleRepository.getById(saleId, txn: txn);
      if (sale == null || sale.paymentStatus != 'pending') return false;

      final items = await _saleItemRepository.getBySaleId(saleId, txn: txn);

      for (var item in items) {
        final product = await _productRepository.getById(item.productId, txn: txn);
        if (product == null) continue;

        final previousStock = product.stock;
        final newStock = previousStock + item.quantity;
        await _productRepository.updateStock(item.productId, newStock, txn: txn);

        final history = StockHistory(
          productId: item.productId,
          operation: StockOperationType.return_,
          quantity: item.quantity,
          previousStock: previousStock,
          newStock: newStock,
          reason: 'GCash payment rejected: ${sale.receiptNumber}${reason != null ? ' - $reason' : ''}',
          userId: _currentUserId('verify_payments'),
          createdAt: DateTime.now(),
        );
        await _stockHistoryRepository.insert(history, txn: txn);
      }

      final updated = sale.copyWith(paymentStatus: 'cancelled');
      await _saleRepository.update(updated, txn: txn);

      await _imageService.deleteImage(sale.paymentProofPath);

      await _activityLogService.logActivity(
        action: 'gcash_payment_rejected',
        entity: 'sale',
        entityId: saleId,
        details: 'Reference: ${sale.referenceNumber}${reason != null ? ' - $reason' : ''}',
        txn: txn,
      );

      return true;
    });
  }

  /// Replace the payment evidence for a sale (e.g. when the cashier retakes
  /// a photo before the sale is committed, or when an owner/admin requests
  /// clearer evidence for a pending payment).
  ///
  /// Returns the new relative path, or null if the update failed.
  Future<String?> replacePaymentProof(
    int saleId,
    String newRelativePath, {
    DatabaseExecutor? txn,
  }) async {
    final sale = await _saleRepository.getById(saleId, txn: txn);
    if (sale == null) return null;

    final currentUser = _sessionManager.currentUser;
    final userId = currentUser?.id;
    final canVerify = _sessionManager.hasPermission('verify_payments');
    final isOwn = userId != null && userId == sale.userId;

    if (!canVerify && !(isOwn && _sessionManager.hasPermission('create_sales'))) {
      await _activityLogService.logActivity(
        action: 'unauthorized_replace_payment_proof',
        entity: 'sale',
        entityId: saleId,
        details: 'Attempted to replace payment proof without permission',
        txn: txn,
      );
      throw AuthorizationException('verify_payments');
    }

    final oldPath = sale.paymentProofPath;

    final updated = sale.copyWith(
      paymentProofPath: newRelativePath,
      paymentProofType: 'image',
    );
    await _saleRepository.update(updated, txn: txn);

    // Clean up the old file only after the new path is persisted.
    await _imageService.deleteImage(oldPath);

    await _activityLogService.logActivity(
      action: 'gcash_payment_evidence_replaced',
      entity: 'sale',
      entityId: saleId,
      details: 'Reference: ${sale.referenceNumber}',
      txn: txn,
    );

    return newRelativePath;
  }

  /// Void a sale within a single atomic transaction.
  /// Restores stock for all items, then soft-deletes the sale.
  Future<bool> voidSale(int saleId) async {
    if (!_sessionManager.hasPermission('void_sales')) {
      await _activityLogService.logActivity(
        action: 'unauthorized_void_sale',
        entity: 'sale',
        entityId: saleId,
        details: 'Attempted to void sale without permission',
      );
      throw AuthorizationException('void_sales');
    }

    return await _dbHelper.transaction((txn) async {
      final sale = await _saleRepository.getById(saleId, txn: txn);
      if (sale == null) return false;

      final items = await _saleItemRepository.getBySaleId(saleId, txn: txn);

      for (var item in items) {
        // addStock opens its own transaction; for void we restore stock
        // directly via the repository within this transaction.
        final product = await _productRepository.getById(item.productId, txn: txn);
        if (product == null) continue;

        final previousStock = product.stock;
        final newStock = previousStock + item.quantity;
        await _productRepository.updateStock(item.productId, newStock, txn: txn);

        final history = StockHistory(
          productId: item.productId,
          operation: StockOperationType.return_,
          quantity: item.quantity,
          previousStock: previousStock,
          newStock: newStock,
          reason: 'Void sale: ${sale.receiptNumber}',
          userId: _currentUserId('void_sales'),
          createdAt: DateTime.now(),
        );
        await _stockHistoryRepository.insert(history, txn: txn);
      }

      await _saleRepository.softDelete(saleId, txn: txn);

      // Clean up any payment evidence associated with the voided sale.
      await _imageService.deleteImage(sale.paymentProofPath);

      // Log activity
      await _activityLogService.logActivity(
        action: 'void_sale',
        entity: 'sale',
        entityId: saleId,
        details: 'Sale ${sale.receiptNumber} voided',
        txn: txn,
      );

      return true;
    });
  }

  Future<double> getTodaySales() async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return 0.0;
    }

    final now = DateTime.now();
    // Staff: only own sales
    if (_sessionManager.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForDateForUser(
        now,
        _currentUserId('view_sales'),
      );
    }
    return _saleRepository.getTotalSalesForDate(now);
  }

  Future<double> getMonthSales() async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return 0.0;
    }

    final now = DateTime.now();
    // Staff: only own sales
    if (_sessionManager.currentUser?.role == UserRole.staff) {
      return _saleRepository.getTotalSalesForMonthForUser(
        now.year,
        now.month,
        _currentUserId('view_sales'),
      );
    }
    return _saleRepository.getTotalSalesForMonth(now.year, now.month);
  }

  Future<double> getUserSales(int userId) async {
    if (!_sessionManager.hasPermission('view_sales')) {
      return 0.0;
    }

    // Staff can only query their own sales total.
    if (_sessionManager.currentUser?.role == UserRole.staff &&
        _sessionManager.currentUser?.id != userId) {
      return 0.0;
    }

    return _saleRepository.getTotalSalesForUser(userId);
  }
}