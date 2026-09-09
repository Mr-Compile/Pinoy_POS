import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pinoy_pos/core/authorization_exception.dart';
import 'package:pinoy_pos/core/database.dart';
import 'package:pinoy_pos/core/database_seeder.dart';
import 'package:pinoy_pos/core/session_manager.dart';
import 'package:pinoy_pos/data/models/export_history.dart';
import 'package:pinoy_pos/data/models/sales_analytics.dart';
import 'package:pinoy_pos/data/models/sales_period.dart';
import 'package:pinoy_pos/data/models/settings.dart';
import 'package:pinoy_pos/data/models/user.dart';
import 'package:pinoy_pos/data/repositories/export_history_repository.dart';
import 'package:pinoy_pos/data/repositories/sale_repository.dart';
import 'package:pinoy_pos/data/repositories/user_repository.dart';
import 'package:pinoy_pos/services/report_export_service.dart';
import 'package:pinoy_pos/services/report_service.dart';
import 'package:pinoy_pos/services/sales_import_service.dart';
import 'package:pinoy_pos/ui/screens/more_screen.dart';

/// Service-layer tests for the staff-to-owner report workflow and the
/// owner-only direct sales import/export separation.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
    await DatabaseHelper().database;
    await DatabaseSeeder().seed();
    SharedPreferences.setMockInitialValues({});
    SessionManager.resetForTest();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTest();
    await Future.delayed(const Duration(milliseconds: 200));
  });

  Future<User> user(String username) async =>
      (await UserRepository().getByUsername(username))!;

  group('Report workflow roles', () {
    test('staff can submit their own report and the owner sees it',
        () async {
      final staff = await user('staff');
      final owner = await user('owner');
      final service = ReportService();

      SessionManager().setCurrentUser(staff);
      final id = await service.recordExport(
        fileFormat: 'pdf',
        filePath: 'reports/staff_report.pdf',
      );
      expect(id, isNotNull);
      expect(await service.submitReport(id!), isTrue);

      SessionManager().setCurrentUser(owner);
      final inbox = await service.getSubmittedReports();
      final submitted = inbox.where((r) => r.id == id).toList();
      expect(submitted.length, 1);
      expect(submitted.first.status, ReportStatus.submitted);
      expect(submitted.first.createdBy, staff.id);
    });

    test('owner cannot submit a report even with export_reports', () async {
      final owner = await user('owner');
      final service = ReportService();

      SessionManager().setCurrentUser(owner);
      // The owner can still export (audit history), but submitting a
      // staff-style report must be rejected at the service layer.
      final id = await service.recordExport(
        fileFormat: 'pdf',
        filePath: 'reports/owner_export.pdf',
      );
      expect(id, isNotNull);
      expect(await service.submitReport(id!), isFalse);
    });

    test('staff cannot submit a report authored by another user', () async {
      final owner = await user('owner');
      final staff = await user('staff');
      final service = ReportService();

      SessionManager().setCurrentUser(owner);
      final id = await service.recordExport(
        fileFormat: 'csv',
        filePath: 'reports/other.csv',
      );

      SessionManager().setCurrentUser(staff);
      expect(await service.submitReport(id!), isFalse);
    });

    test('getMyReports is empty for the owner even after exporting',
        () async {
      final owner = await user('owner');
      final service = ReportService();

      SessionManager().setCurrentUser(owner);
      final id = await service.recordExport(
        fileFormat: 'csv',
        filePath: 'reports/owner.csv',
      );
      expect(id, isNotNull);
      // "My Reports" is a staff-author concept; the owner is never a
      // report author, so this returns nothing even though export_history
      // rows exist for audit purposes.
      expect(await service.getMyReports(), isEmpty);
    });

    test('owner cannot import report files into the reports inbox',
        () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);
      final result = await ReportService().importReport(
        fileName: 'external.pdf',
        bytes: Uint8List.fromList(const [1, 2, 3]),
      );
      expect(result, isNull);
    });

    test('submitSalesReport is rejected for the owner at the service layer',
        () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);
      // Even if a caller bypasses the UI, the owner cannot enter the
      // staff submission workflow.
      expect(
        await ReportExportService().submitSalesReport(
          analytics: SalesAnalytics.empty(
            boundsForSalesFilter(
              SalesPeriodFilter.today(SalesPeriod.monthly),
            ),
          ),
          store: Settings(
            storeName: 'Test Store',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ),
        isNull,
      );
    });

    test('More entries: My Reports is staff-only, Submitted Reports owner-only',
        () {
      // Build minimal in-memory users; MoreEntry filtering only needs
      // SessionManager permissions, no database rows.
      final owner = User(
        id: 1,
        username: 'owner',
        passwordHash: 'x',
        role: UserRole.owner,
        fullName: 'Owner',
        createdAt: DateTime(2026),
      );
      final staff = User(
        id: 2,
        username: 'staff',
        passwordHash: 'x',
        role: UserRole.staff,
        fullName: 'Staff',
        createdAt: DateTime(2026),
      );

      SessionManager().setCurrentUser(owner);
      var entries =
          MoreEntry.accessibleFor(SessionManager().hasPermission);
      expect(entries.any((e) => e.title == 'My Reports'), isFalse);
      expect(
        entries.any((e) => e.title == 'Submitted Reports'),
        isTrue,
      );

      SessionManager().setCurrentUser(staff);
      entries = MoreEntry.accessibleFor(SessionManager().hasPermission);
      expect(entries.any((e) => e.title == 'My Reports'), isTrue);
      expect(
        entries.any((e) => e.title == 'Submitted Reports'),
        isFalse,
      );
    });
  });

  group('SalesImportService', () {
    setUp(() async {
      // The ffi test database persists between runs — clear sales (child
      // table first) so receipt-number assertions stay deterministic.
      final db = await DatabaseHelper().database;
      await db.delete('sale_items');
      await db.delete('sales');
    });

    test('preview parses valid rows and flags invalid ones', () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);

      const csv = 'date,total,payment_method,customer\n'
          '2026-09-01 10:00,150.00,Cash,Juan\n'
          '2026-09-02,200.50,GCash,\n'
          'not-a-date,abc,,\n';

      final preview = await SalesImportService().previewSalesImport(
        fileName: 'sales.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );

      expect(preview, isNotNull);
      expect(preview!.fileError, isNull);
      expect(preview.validRows.length, 2);
      expect(preview.invalidRows.length, 1);
      expect(preview.validRows.first.customerName, 'Juan');
      expect(preview.validRows.last.paymentMethod, 'GCash');
    });

    test('preview reports missing required columns', () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);

      final preview = await SalesImportService().previewSalesImport(
        fileName: 'bad.csv',
        bytes: Uint8List.fromList(utf8.encode('a,b\n1,2\n')),
      );

      expect(preview, isNotNull);
      expect(preview!.fileError, isNotNull);
      expect(preview.rows, isEmpty);
    });

    test('staff are denied sales import (owner-only permission)', () async {
      final staff = await user('staff');
      SessionManager().setCurrentUser(staff);

      expect(
        SalesImportService().previewSalesImport(
          fileName: 's.csv',
          bytes: Uint8List(0),
        ),
        throwsA(isA<AuthorizationException>()),
      );
    });

    test('owner import inserts sales and creates no report records',
        () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);
      final service = SalesImportService();

      const csv = 'date,total,receipt_number,notes\n'
          '2026-09-01,100.00,IMP-0001,Opening balance sale\n'
          '2026-09-02,50.00,,\n';

      final preview = await service.previewSalesImport(
        fileName: 'sales.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      expect(preview!.validRows.length, 2);

      // Snapshot the owner's audit rows — the test database is shared
      // between tests, so assert the import adds none rather than none
      // existing at all.
      final historyRepo = ExportHistoryRepository();
      final historyBefore =
          (await historyRepo.getByCreatedBy(owner.id!)).length;

      final result = await service.importSales(preview);
      expect(result.imported, 2);
      expect(result.errors, isEmpty);

      final sales = await SaleRepository().getAllActive();
      expect(sales.length, 2);
      // Explicit receipt numbers are kept; missing ones are generated.
      expect(
        sales.any((s) => s.receiptNumber == 'IMP-0001'),
        isTrue,
      );
      expect(
        sales.every(
          (s) => s.receiptNumber != null && s.receiptNumber!.isNotEmpty,
        ),
        isTrue,
      );

      // Sales import must never create a report/export_history record.
      final historyAfter =
          await historyRepo.getByCreatedBy(owner.id!);
      expect(historyAfter.length, historyBefore);
    });

    test('duplicate receipt numbers are skipped', () async {
      final owner = await user('owner');
      SessionManager().setCurrentUser(owner);
      final service = SalesImportService();

      const csv = 'date,total,receipt_number\n'
          '2026-09-01,100.00,DUP-0001\n'
          '2026-09-02,60.00,DUP-0001\n';

      final preview = await service.previewSalesImport(
        fileName: 'dupes.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );

      final result = await service.importSales(preview!);
      expect(result.imported, 1);
      expect(result.skipped, 1);
      expect(result.errors, isEmpty);
    });
  });
}
