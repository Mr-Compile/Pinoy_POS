$nl = "`n"

# sales_analytics_service: add category_sales_result import and replace getCategorySales.
$path = 'C:\wamp64\www\Pinoy_Pos\lib\services\sales_analytics_service.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"

# Add import.
if ($content.IndexOf("import 'package:pinoy_pos/data/models/category_sales_result.dart';") -eq -1) {
  $content = $content.Replace(
    "import 'package:pinoy_pos/data/models/calendar_day_sales.dart';" + $nl,
    "import 'package:pinoy_pos/data/models/calendar_day_sales.dart';" + $nl +
    "import 'package:pinoy_pos/data/models/category_sales_result.dart';" + $nl
  )
}

# Replace getCategorySales call with empty list.
$content = $content.Replace(
  '    final categorySales = await _saleRepository.getCategorySales(' + $nl +
  '      bounds.start,' + $nl +
  '      bounds.end,' + $nl +
  '      userId: userId,' + $nl +
  '    );',
  '    final categorySales = <CategorySalesResult>[];'
)

# Ensure constructor receives previousTrend and categorySales.
if ($content.IndexOf('      previousTrend: previousTrend,') -eq -1) {
  $content = $content.Replace(
    '      comparison: comparison,' + $nl +
    '      trend: trend,' + $nl +
    '      paymentBreakdown: paymentBreakdown,',
    '      comparison: comparison,' + $nl +
    '      trend: trend,' + $nl +
    '      previousTrend: previousTrend,' + $nl +
    '      paymentBreakdown: paymentBreakdown,'
  )
}
if ($content.IndexOf('      categorySales: categorySales,') -eq -1) {
  $content = $content.Replace(
    '      topProducts: topProducts,' + $nl +
    '      staffSummaries: staffSummaries,' + $nl +
    '      sales: sales,',
    '      topProducts: topProducts,' + $nl +
    '      categorySales: categorySales,' + $nl +
    '      staffSummaries: staffSummaries,' + $nl +
    '      sales: sales,'
  )
}

# Ensure previousTrend variable exists.
if ($content.IndexOf('    final previousTrend = _fillTrendGaps(rawPreviousTrend, previousBounds);') -eq -1) {
  $content = $content.Replace(
    '    final trend = _fillTrendGaps(rawTrend, bounds);' + $nl + $nl +
    '    final paymentBreakdown = await _saleRepository.getPaymentBreakdown(',
    '    final trend = _fillTrendGaps(rawTrend, bounds);' + $nl + $nl +
    '    final rawPreviousTrend = await _saleRepository.getSalesTrend(' + $nl +
    '      bounds.previousStart,' + $nl +
    '      bounds.previousEnd,' + $nl +
    '      groupBy: bounds.groupBy,' + $nl +
    '      userId: userId,' + $nl +
    '    );' + $nl +
    '    final previousBounds = ReportingPeriodBounds(' + $nl +
    '      start: bounds.previousStart,' + $nl +
    '      end: bounds.previousEnd,' + $nl +
    '      previousStart: bounds.previousStart,' + $nl +
    '      previousEnd: bounds.previousEnd,' + $nl +
    '      groupBy: bounds.groupBy,' + $nl +
    '    );' + $nl +
    '    final previousTrend = _fillTrendGaps(rawPreviousTrend, previousBounds);' + $nl + $nl +
    '    final paymentBreakdown = await _saleRepository.getPaymentBreakdown('
  )
}

[System.IO.File]::WriteAllText($path, $content)

# sale_repository: remove getCategorySales method.
$path = 'C:\wamp64\www\Pinoy_Pos\lib\data\repositories\sale_repository.dart'
$content = [System.IO.File]::ReadAllText($path)
$content = $content -replace "`r`n", "`n"
$content = $content -replace '(?s)  Future<List<CategorySalesResult>> getCategorySales\(\r?\n    DateTime start,\r?\n    DateTime end, \{\r?\n    int\? userId,\r?\n  \}\) =>\r?\n      _saleDao\.getCategorySales\(start, end, userId: userId\);\r?\n\r?\n', ''
$content = $content -replace "(?m)^import 'package:pinoy_pos/data/models/category_sales_result.dart';\r?\n", ''
[System.IO.File]::WriteAllText($path, $content)
