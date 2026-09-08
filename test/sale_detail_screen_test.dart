import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/core/app_theme.dart';
import 'package:pinoy_pos/core/session_status.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/data/models/receipt_view_data.dart';
import 'package:pinoy_pos/data/models/sale.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/providers/auth_provider.dart';
import 'package:pinoy_pos/providers/receipt_provider.dart';
import 'package:pinoy_pos/providers/service_providers.dart';
import 'package:pinoy_pos/services/auth_service.dart';
import 'package:pinoy_pos/services/product_service.dart';
import 'package:pinoy_pos/ui/screens/sale_detail_screen.dart';

class _FakeAuthService extends AuthService {
  final User _user;

  _FakeAuthService(this._user);

  @override
  User? get currentUser => _user;

  @override
  Future<SessionStatus> restoreSession() async => SessionStatus.active;

  @override
  bool hasPermission(String permission) => true;
}

class _FakeProductService extends ProductService {
  @override
  Future<Product?> getProductById(int id) async {
    return Product(
      id: id,
      name: 'Pastil',
      price: 10,
      stock: 100,
      createdAt: DateTime(2026, 9, 8),
      imageUrl: null,
    );
  }
}

Widget _buildTestableScreen({
  required Widget child,
  required ReceiptViewData receipt,
  required User user,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWith((ref) => _FakeAuthService(user)),
      productServiceProvider.overrideWith((ref) => _FakeProductService()),
      receiptViewDataProvider.overrideWith((ref, saleId) async => receipt),
    ],
    child: child,
  );
}

Future<void> _pumpAndSettle(WidgetTester tester) async {
  // Flush the FutureProvider and any microtasks, then render the data state.
  await tester.pump();
  await tester.pump();
}

void main() {
  final now = DateTime(2026, 9, 8, 17, 59);

  final sale = Sale(
    id: 1,
    totalAmount: 10,
    cashReceived: 10,
    change: 0,
    paymentMethod: 'GCash',
    paymentStatus: 'confirmed',
    referenceNumber: 'UUWUWUWUWU',
    customerName: 'Hah',
    userId: 1,
    createdAt: now,
    receiptNumber: '20260908-0001',
  );

  final receipt = ReceiptViewData(
    storeName: 'Test Store',
    saleId: 1,
    receiptNumber: '20260908-0001',
    date: now,
    cashierName: 'Store Owner',
    paymentMethod: 'GCash',
    paymentStatus: 'confirmed',
    total: 10,
    subtotal: 10,
    discount: 0,
    cashReceived: 10,
    change: 0,
    referenceNumber: 'UUWUWUWUWU',
    customerName: 'Hah',
    items: const [
      ReceiptItem(
        productId: 1,
        productName: 'Pastil',
        quantity: 1,
        unitPrice: 10,
        totalPrice: 10,
      ),
    ],
  );

  final owner = User(
    id: 1,
    username: 'owner',
    passwordHash: '',
    role: UserRole.owner,
    fullName: 'Store Owner',
    createdAt: now,
  );

  group('SaleDetailScreen', () {
    testWidgets('renders all key sections in light mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppColors.getLightTheme(),
          home: _buildTestableScreen(
            child: SaleDetailScreen(sale: sale),
            receipt: receipt,
            user: owner,
          ),
        ),
      );
      await _pumpAndSettle(tester);

      expect(find.textContaining('Sale #20260908-0001'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.textContaining('₱10.00'), findsWidgets);
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('Pastil'), findsOneWidget);
      expect(find.text('Payment Information'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('View Receipt'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
    });

    testWidgets('renders in dark mode without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppColors.getDarkTheme(),
          home: _buildTestableScreen(
            child: SaleDetailScreen(sale: sale),
            receipt: receipt,
            user: owner,
          ),
        ),
      );
      await _pumpAndSettle(tester);

      expect(find.textContaining('Sale #20260908-0001'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Ensure no overflow in the portrait phone layout.
      // Any RenderFlex overflow will be reported by the test framework.
    });

    testWidgets('adapts to tablet width with multi-column layout', (tester) async {
      await tester.binding.setSurfaceSize(const Size(820, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppColors.getLightTheme(),
          home: _buildTestableScreen(
            child: SaleDetailScreen(sale: sale),
            receipt: receipt,
            user: owner,
          ),
        ),
      );
      await _pumpAndSettle(tester);

      expect(find.textContaining('Sale #20260908-0001'), findsOneWidget);
      expect(find.text('Total Amount'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows fallback placeholder when product has no image', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppColors.getLightTheme(),
          home: _buildTestableScreen(
            child: SaleDetailScreen(sale: sale),
            receipt: receipt,
            user: owner,
          ),
        ),
      );
      await _pumpAndSettle(tester);

      // The AppImage placeholder is an inventory icon.
      expect(find.byIcon(Icons.inventory_2), findsOneWidget);
    });

    testWidgets('shows pending actions when payment is pending', (tester) async {
      final pendingReceipt = ReceiptViewData(
        storeName: 'Test Store',
        saleId: 1,
        receiptNumber: '20260908-0002',
        date: now,
        cashierName: 'Store Owner',
        paymentMethod: 'GCash',
        paymentStatus: 'pending',
        total: 30,
        subtotal: 30,
        discount: 0,
        cashReceived: 0,
        change: 0,
        referenceNumber: 'PENDING123',
        customerName: 'Hah',
        items: const [
          ReceiptItem(
            productId: 2,
            productName: 'Pastil',
            quantity: 3,
            unitPrice: 10,
            totalPrice: 30,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppColors.getLightTheme(),
          home: _buildTestableScreen(
            child: SaleDetailScreen(sale: sale),
            receipt: pendingReceipt,
            user: owner,
          ),
        ),
      );
      await _pumpAndSettle(tester);

      expect(find.text('Pending'), findsNWidgets(2));
      expect(find.text('Confirm'), findsNWidgets(2));
      expect(find.text('Reject'), findsNWidgets(2));
    });
  });
}
