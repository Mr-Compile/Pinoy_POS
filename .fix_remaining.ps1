$nl = "`n"

# 1. dashboard_service: imports and OwnerDashboardData getters.
$path = 'C:\wamp64\www\Pinoy_Pos\lib\services\dashboard_service.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"

# Add required model imports if missing.
$content = $content.Replace(
  "import 'package:pinoy_pos/data/models/announcement.dart';" + $nl,
  "import 'package:pinoy_pos/data/models/announcement.dart';" + $nl +
  "import 'package:pinoy_pos/data/models/daily_sales_point.dart';" + $nl +
  "import 'package:pinoy_pos/data/models/sale.dart';" + $nl
)

# Remove the unused sale_item_repository import.
$content = $content -replace "(?m)^import 'package:pinoy_pos/data/repositories/sale_item_repository.dart';\r?\n", ''

# Replace the partial OwnerDashboardData getters with the full set.
$old = '  List<Sale> get recentSales => analytics.sales;' + $nl +
       '  List<StaffSalesSummary> get staffSales => analytics.staffSummaries;' + $nl +
       '}'
$new = '  double get todaySales => analytics.totalSales;' + $nl +
       '  int get todayTransactions => analytics.transactionCount;' + $nl +
       '  int get lowStockCount => inventoryStatus.lowStock;' + $nl +
       '  int get outOfStockCount => inventoryStatus.outOfStock;' + $nl +
       '  List<DailySalesPoint> get salesTrend => analytics.trend;' + $nl +
       '  List<TopProductResult> get topProducts => analytics.topProducts;' + $nl +
       '  List<Sale> get recentSales => analytics.sales;' + $nl +
       '  List<StaffSalesSummary> get staffSales => analytics.staffSummaries;' + $nl +
       '}'
$content = $content.Replace($old, $new)
[System.IO.File]::WriteAllText($path, $content)

# 2. sales_analytics_service: add category_sales_result import and replace getCategorySales.
$path = 'C:\wamp64\www\Pinoy_Pos\lib\services\sales_analytics_service.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"
$content = $content.Replace(
  "import 'package:pinoy_pos/data/models/calendar_day_sales.dart';" + $nl,
  "import 'package:pinoy_pos/data/models/calendar_day_sales.dart';" + $nl +
  "import 'package:pinoy_pos/data/models/category_sales_result.dart';" + $nl
)
$content = $content.Replace(
  '    final categorySales = await _saleRepository.getCategorySales(' + $nl +
  '      bounds.start,' + $nl +
  '      bounds.end,' + $nl +
  '      userId: userId,' + $nl +
  '    );',
  '    final categorySales = <CategorySalesResult>[];'
)
[System.IO.File]::WriteAllText($path, $content)

# 3. sale_repository: remove the getCategorySales method.
$path = 'C:\wamp64\www\Pinoy_Pos\lib\data\repositories\sale_repository.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"
$content = $content -replace '(?s)  Future<List<CategorySalesResult>> getCategorySales\(\r?\n    DateTime start,\r?\n    DateTime end, \{\r?\n    int\? userId,\r?\n  \}\) =>\r?\n      _saleDao\.getCategorySales\(start, end, userId: userId\);\r?\n\r?\n', ''
# Also remove the category_sales_result import if present.
$content = $content -replace "(?m)^import 'package:pinoy_pos/data/models/category_sales_result.dart';\r?\n", ''
[System.IO.File]::WriteAllText($path, $content)
