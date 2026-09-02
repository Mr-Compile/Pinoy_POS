# Pinoy POS Sales Reporting System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a real-world, role-aware, period-aware sales analytics and reporting system that reuses the existing `sales`/`sale_items` tables and does not duplicate reporting architecture.

**Architecture:** Add a single authoritative `SalesAnalyticsService` plus a small `ReportExportService` that centralizes all successful-sale queries, period math, and PDF/Excel generation. The UI (`ReportsScreen` becomes `Sales Analytics`, new `SalesCalendarScreen` and `ReportSubmissionsScreen`) consumes providers that watch this service. Existing `SalesService`, `ReportService`, `DashboardService` and `BusinessIntelligenceService` are refactored to delegate to the new service instead of duplicating date/status logic.

**Tech Stack:** Flutter 3 / Dart, `flutter_riverpod`, `sqflite`/`sqflite_common_ffi`, `pdf`, `excel`, `csv`, `file_picker`, `intl`.

## Global Constraints

- Successful sale filter: `sales.payment_status = 'confirmed'` AND `sales.deleted_at IS NULL`.
- Other statuses (`pending`, `cancelled`, `refunded`) are excluded from confirmed-sales analytics.
- Staff can only see their own sales (`user_id = currentUser.id`); Owner/Admin see all.
- All date math uses local `DateTime(year, month, day)` boundaries; no UTC drift.
- Period UI and export must use the same date range and status filter.
- Material 3 theme colors only; no hardcoded `Colors.*` for analytics/calendar/report cards.
- Existing sales creation, payment processing, receipts, inventory, and database records must not change.

## Files / Structure

- **Core query layer**
  - `lib/services/sales_analytics_service.dart` — central reporting service
  - `lib/data/models/reporting_period.dart` — period enum + bounds + grouping
  - `lib/data/models/sales_analytics.dart` — analytics DTO
  - `lib/data/models/calendar_day_sales.dart` — calendar cell DTO
  - `lib/data/models/payment_breakdown.dart` — moved from `ReportService`
  - `lib/data/models/top_product_result.dart` — add `revenue`, `fromMap`

- **Data access additions**
  - `lib/data/dao/sale_dao.dart` — new range summary, trend, payment, top-product, calendar queries
  - `lib/data/repositories/sale_repository.dart` — expose new DAO methods
  - `lib/data/dao/sale_item_dao.dart` — filter top products by confirmed sales + range
  - `lib/data/models/export_history.dart` — add `status`, `submittedAt`, `viewedAt`, `fileSize`, `thumbnailPath`, `reportNumber`
  - `lib/core/database.dart` — migration v16 → v17 adds `export_history` columns

- **Reporting / export service**
  - `lib/services/report_export_service.dart` — generate bytes, filenames, verify, record history
  - `lib/ui/screens/reports_screen.dart` — replace with Sales Analytics + export actions
  - `lib/providers/reports_provider.dart` — state for period, analytics, export

- **Sales list improvements**
  - `lib/ui/screens/sales_screen.dart` — add period filter, use analytics service, improved rows

- **Calendar (Owner)**
  - `lib/ui/screens/sales_calendar_screen.dart` — month calendar with sales indicators
  - `lib/ui/widgets/sales_calendar.dart` — reusable calendar grid
  - `lib/ui/screens/sales_calendar_day_detail_screen.dart` — day detail + sales list

- **Report submissions / Owner inbox**
  - `lib/ui/screens/report_submissions_screen.dart` — staff submit, owner view/download
  - `lib/ui/widgets/report_document_card.dart` — document card with metadata and actions

- **Navigation / permissions**
  - `lib/core/session_manager.dart` — add `'view_report_submissions'` to Owner
  - `lib/ui/screens/more_screen.dart` — add calendar and submissions entries

## Phase 1: Core Analytics Engine & UI

### Task 1.1: Centralize reporting period math and successful-sale filtering

**Files:**
- Create: `lib/data/models/reporting_period.dart`
- Modify: `lib/data/dao/sale_dao.dart`, `lib/data/repositories/sale_repository.dart`

**Steps:**
1. Define `ReportingPeriod` enum with all required periods.
2. Define `ReportingPeriodBounds` with `start`, `end`, `previousStart`, `previousEnd`, `groupBy`.
3. Add `SaleDao.getSalesSummaryForRange(start, end, userId)` returning total, count, items.
4. Add `SaleDao.getSalesTrendForRange(start, end, userId, groupBy)` returning `List<DailySalesPoint>` (or week/month points).
5. Add `SaleDao.getPaymentBreakdownForRange(start, end, userId)` returning maps of method → {total, count}.
6. Add `SaleDao.getTopProductsForRange(start, end, userId, sortBy, limit)` returning product id, name, qty, revenue.
7. Add `SaleDao.getStaffSalesSummary` range overload.
8. Add `SaleDao.getCalendarDaySales(start, end, userId)` returning date → {total, count}.
9. Expose all in `SaleRepository`.

**Verification:**
- `flutter analyze` clean.
- Run `test/owner_integration_test.dart` and `test/reports_export_in_memory_test.dart`.

### Task 1.2: Build `SalesAnalyticsService`

**Files:**
- Create: `lib/services/sales_analytics_service.dart`, `lib/data/models/sales_analytics.dart`
- Modify: `lib/services/sales_service.dart`, `lib/services/report_service.dart`, `lib/services/dashboard_service.dart`

**Steps:**
1. Implement `SalesAnalyticsService.getAnalytics(ReportingPeriod, {customStart, customEnd})`.
2. Implement `SalesAnalyticsService.getSalesList(...)` with period, search, method/status.
3. Implement `SalesAnalyticsService.getCalendarDaySales(...)`.
4. Refactor `SalesService.getTodaySales`, `getMonthSales`, `getSalesByDateRange` to delegate.
5. Refactor `ReportService` to delegate analytics and keep only history recording.
6. Refactor `DashboardService` to delegate 7-day trend and top products.
7. Refactor `BusinessIntelligenceService` to use the new service for AI facts (optional, keep if time short).

**Verification:**
- `flutter analyze` clean.
- Manual test with seeded data: totals for today/yesterday/week/month match manual DB sums.

### Task 1.3: Rebuild `ReportsScreen` as Sales Analytics

**Files:**
- Modify: `lib/ui/screens/reports_screen.dart`, `lib/providers/reports_provider.dart`
- Create: `lib/ui/widgets/period_selector.dart`, `lib/ui/widgets/sales_summary_cards.dart`, `lib/ui/widgets/sales_trend_chart.dart`, `lib/ui/widgets/product_performance_list.dart`, `lib/ui/widgets/payment_breakdown_list.dart`, `lib/ui/widgets/staff_performance_list.dart`

**Steps:**
1. Add `ReportingPeriod` to `ReportsState` and `ReportsNotifier`.
2. Build `PeriodSelector` chip row: Today, Yesterday, Week, Month, Year, Custom.
3. Build `SalesSummaryCards` with Total Sales, Transactions, Average Sale, Items Sold + comparison.
4. Build `SalesTrendChart` using `MiniBarChart` with appropriate labels.
5. Build `ProductPerformanceList` (ranked with qty and revenue, sort toggle).
6. Build `PaymentBreakdownList` with count/amount/percentage.
7. Build `StaffPerformanceList` for Owner/Admin.
8. Add Export actions (PDF/Excel) to app bar / top section.

**Verification:**
- Pump `test/owner_screens_test.dart` Reports screen.
- Verify light/dark mode and responsive layout.

### Task 1.4: Improve `SalesScreen` with period filtering and visual hierarchy

**Files:**
- Modify: `lib/ui/screens/sales_screen.dart`

**Steps:**
1. Add period chip selector (Today, Week, Month, All, Custom) using analytics service.
2. Keep existing method/status/search filters.
3. Improve sale row: Receipt #, total, date/time, cashier, item count, payment method, status.
4. Use `AppListItem` consistently and currency formatting.

**Verification:**
- `flutter test` for `owner_screens_test.dart` and `owner_integration_test.dart`.

## Phase 2: Calendar, Export Reliability, Report Submission

### Task 2.1: Owner Sales Calendar

**Files:**
- Create: `lib/ui/screens/sales_calendar_screen.dart`, `lib/ui/widgets/sales_calendar.dart`, `lib/ui/screens/sales_calendar_day_detail_screen.dart`

**Steps:**
1. Build month calendar with Previous/Current/Next.
2. Query `SalesAnalyticsService.getCalendarDaySales` for displayed month.
3. Color-code days by sales intensity using `ColorScheme` semantics and amount/transaction labels.
4. Tap day opens detail screen with total, count, average, sales list.
5. Add `view_report_submissions`-gated entry to `MoreScreen`.

**Verification:**
- Manual test: empty days neutral, days with sales show amount and count, no future dates.

### Task 2.2: Reliable PDF / Excel Export

**Files:**
- Create: `lib/services/report_export_service.dart`
- Modify: `lib/services/report_service.dart`, `lib/ui/screens/reports_screen.dart`

**Steps:**
1. Move all PDF/Excel/CSV generation from `ReportsScreen` into `ReportExportService`.
2. Use `SalesAnalyticsService` data for selected period.
3. Professional PDF layout (store header, period, generated by, summary, trend, top products, payment summary, detailed sales).
4. Excel with sheets: Summary, Sales, Product Performance, Payment Summary.
5. Embed period in filename (`sales_report_YYYY-MM-DD_to_YYYY-MM-DD.{pdf,xlsx}`).
6. Verify file exists and non-zero size before returning; return `null` on failure.
7. Record export in `export_history` with status `generated` (or `submitted` for staff).

**Verification:**
- Generate PDF/Excel for a known period and verify totals match analytics.
- Open files and confirm period, totals, columns.

### Task 2.3: Report Submission / Owner Inbox

**Files:**
- Modify: `lib/core/database.dart` (v17 migration), `lib/data/models/export_history.dart`, `lib/data/dao/export_history_dao.dart`, `lib/data/repositories/export_history_repository.dart`
- Create: `lib/ui/screens/report_submissions_screen.dart`, `lib/ui/widgets/report_document_card.dart`
- Modify: `lib/core/session_manager.dart`, `lib/ui/screens/more_screen.dart`

**Steps:**
1. Migration v17: add `status`, `submitted_at`, `viewed_at`, `file_size`, `thumbnail_path`, `report_number` to `export_history`.
2. Update `ExportHistory` model with new fields and statuses `generated`, `submitted`, `viewed`, `archived`.
3. Add `SalesAnalyticsService.submitReport(id)` and `viewReport(id)`.
4. Staff: after export, optionally `Submit to Owner` → status `submitted`.
5. Owner: `ReportSubmissionsScreen` lists submitted reports with metadata, status badge, View/Download PDF/Excel actions.
6. PDF thumbnail: on supported platforms, generate first-page preview and save to `thumbnail_path`; fallback to a rendered preview card (never a generic icon if possible).
7. Add `view_report_submissions` to Owner permissions and `MoreScreen`.

**Verification:**
- Staff can generate and submit; Owner can view and download.
- Report status lifecycle: generated → submitted → viewed.
- Totals in Owner view match analytics.

## Phase 3: Cross-Component Consistency & Final Verification

### Task 3.1: End-to-end consistency test

**Steps:**
1. Seed sales with known status/method/product/staff mix.
2. For a fixed range, compare:
   - `SalesAnalytics` total == `SalesScreen` total == `SalesCalendar` total == PDF total == Excel total.
3. Verify cancelled/pending/failed/voided sales do **not** appear in confirmed-sales totals.
4. Verify Staff only see own sales; Owner sees all.

**Verification:**
- Add targeted test(s) in `test/reports_export_in_memory_test.dart` or `test/owner_integration_test.dart`.
- Run `flutter test` and `flutter build apk --debug`.

### Task 3.2: Final acceptance criteria check

Check each final acceptance item from the spec and record PASS/FAIL:

- [ ] Sales analytics support meaningful date periods
- [ ] Daily/weekly/monthly/yearly aggregation works
- [ ] Custom date range works
- [ ] Confirmed/successful sales are the primary analytics source
- [ ] Cancelled/pending/failed sales do not contaminate confirmed totals
- [ ] Important sales columns only are displayed
- [ ] Sales list has strong visual hierarchy
- [ ] Owner has calendar-based sales view
- [ ] Calendar has meaningful indicators
- [ ] Calendar works in light mode
- [ ] Calendar works in dark mode
- [ ] Staff can generate reports
- [ ] Staff can submit reports to Owner
- [ ] Owner can view Staff-submitted reports
- [ ] Owner can view PDF
- [ ] Owner can download PDF
- [ ] Owner can download Excel
- [ ] PDF has first-page thumbnail preview
- [ ] Excel has appropriate file representation
- [ ] PDF has professional business-report layout
- [ ] Excel has useful business-report structure
- [ ] PDF and Excel use the same reporting data
- [ ] Analytics totals match Sales totals
- [ ] Analytics totals match PDF totals
- [ ] Analytics totals match Excel totals
- [ ] File generation is verified
- [ ] Failed exports do not show fake success
- [ ] Permissions are enforced
- [ ] No duplicate reporting architecture was introduced
- [ ] Existing sales functionality still works
- [ ] Light mode works
- [ ] Dark mode works
- [ ] Mobile layout works
- [ ] Desktop layout works
