$path = 'C:\wamp64\www\Pinoy_Pos\lib\services\dashboard_service.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"
$nl = "`n"

# 1. Add missing model imports.
$old = "import 'package:pinoy_pos/data/models/announcement.dart';" + $nl
$new = "import 'package:pinoy_pos/data/models/announcement.dart';" + $nl +
       "import 'package:pinoy_pos/data/models/daily_sales_point.dart';" + $nl +
       "import 'package:pinoy_pos/data/models/sale.dart';" + $nl +
       "import 'package:pinoy_pos/data/models/top_product_result.dart';" + $nl
$content = $content.Replace($old, $new)

# 2. Remove the unused _saleItemRepository field.
$old = '  final SaleItemRepository _saleItemRepository = SaleItemRepository();' + $nl
$new = ''
$content = $content.Replace($old, $new)

# 3. Add OwnerDashboardData getters.
$old = '  const OwnerDashboardData({' + $nl +
       '    required this.analytics,' + $nl +
       '    this.storeInfo,' + $nl +
       '    required this.inventoryStatus,' + $nl +
       '    required this.lowStockProducts,' + $nl +
       '    required this.recentActivities,' + $nl +
       '    required this.announcements,' + $nl +
       '  });' + $nl +
       '}'
$new = '  const OwnerDashboardData({' + $nl +
       '    required this.analytics,' + $nl +
       '    this.storeInfo,' + $nl +
       '    required this.inventoryStatus,' + $nl +
       '    required this.lowStockProducts,' + $nl +
       '    required this.recentActivities,' + $nl +
       '    required this.announcements,' + $nl +
       '  });' + $nl +
       $nl +
       '  double get todaySales => analytics.totalSales;' + $nl +
       '  int get todayTransactions => analytics.transactionCount;' + $nl +
       '  int get lowStockCount => inventoryStatus.lowStock;' + $nl +
       '  int get outOfStockCount => inventoryStatus.outOfStock;' + $nl +
       '  List<DailySalesPoint> get salesTrend => analytics.trend;' + $nl +
       '  List<TopProductResult> get topProducts => analytics.topProducts;' + $nl +
       '  List<Sale> get recentSales => analytics.sales;' + $nl +
       '  List<StaffSalesSummary> get staffSales => analytics.staffSummaries;' + $nl +
       '}'
$content = $content.Replace($old, $new)

# 4. Add StaffDashboardData getters.
$old = '  const StaffDashboardData({' + $nl +
       '    required this.analytics,' + $nl +
       '    this.storeInfo,' + $nl +
       '    required this.inventoryStatus,' + $nl +
       '    required this.lowStockProducts,' + $nl +
       '    required this.recentActivities,' + $nl +
       '  });' + $nl +
       '}'
$new = '  const StaffDashboardData({' + $nl +
       '    required this.analytics,' + $nl +
       '    this.storeInfo,' + $nl +
       '    required this.inventoryStatus,' + $nl +
       '    required this.lowStockProducts,' + $nl +
       '    required this.recentActivities,' + $nl +
       '  });' + $nl +
       $nl +
       '  double get mySalesToday => analytics.totalSales;' + $nl +
       '  int get myTransactionsToday => analytics.transactionCount;' + $nl +
       '  int get lowStockCount => inventoryStatus.lowStock;' + $nl +
       '  int get outOfStockCount => inventoryStatus.outOfStock;' + $nl +
       '  List<DailySalesPoint> get mySalesTrend => analytics.trend;' + $nl +
       '  List<Sale> get myRecentSales => analytics.sales;' + $nl +
       '}'
$content = $content.Replace($old, $new)

[System.IO.File]::WriteAllText($path, $content)
