$path = 'C:\wamp64\www\Pinoy_Pos\lib\services\dashboard_service.dart'
$content = [System.IO.File]::ReadAllText($path)

# 1. Remove the hourly data model import.
$content = $content -replace "^import 'package:pinoy_pos/data/models/sales_by_hour_point.dart';\r?\n", ''

# 2. Remove the salesByHour / mySalesByHour fields from DTOs (and the blank line after).
$content = $content -replace '  final List<SalesByHourPoint> (salesByHour|mySalesByHour);\r?\n\r?\n', ''

# 3. Remove the constructor parameters.
$content = $content -replace '    required this\.(salesByHour|mySalesByHour),\r?\n', ''

# 4. Remove the Owner and Admin getSalesByHour single-line assignments.
$content = $content -replace '(?s)    final salesByHour = await _saleRepository\.getSalesByHour\([^)]*\);.*?    return (Owner|Admin)DashboardData\(', '    return $1DashboardData('

# 5. Remove the salesByHour constructor arguments.
$content = $content -replace '      salesByHour: salesByHour,\r?\n', ''

# 6. Remove the Staff getSalesByHour multi-line block.
$content = $content -replace '(?s)    // Own sales by hour over the last 7 days\..*?    return StaffDashboardData\(', '    return StaffDashboardData('

# 7. Remove the mySalesByHour constructor argument.
$content = $content -replace '      mySalesByHour: mySalesByHour,\r?\n', ''

# 8. Remove the empty state values.
$content = $content -replace '        salesByHour: \[\],\r?\n', ''
$content = $content -replace '        mySalesByHour: \[\],\r?\n', ''

[System.IO.File]::WriteAllText($path, $content)
