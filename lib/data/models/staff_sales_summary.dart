import 'package:pinoy_pos/data/models/user.dart';

/// Sales performance for a single user over a given period.
class StaffSalesSummary {
  final int userId;
  final String fullName;
  final UserRole? role;
  final double totalSales;
  final int transactionCount;

  const StaffSalesSummary({
    required this.userId,
    required this.fullName,
    this.role,
    required this.totalSales,
    required this.transactionCount,
  });

  double get averageTransaction =>
      transactionCount == 0 ? 0.0 : totalSales / transactionCount;

  factory StaffSalesSummary.fromMap(Map<String, dynamic> map) {
    return StaffSalesSummary(
      userId: (map['user_id'] as num).toInt(),
      fullName: (map['full_name'] as String?) ?? 'Unknown',
      role: map['role'] != null
          ? UserRole.values.firstWhere(
              (r) => r.name == map['role'],
              orElse: () => UserRole.staff,
            )
          : null,
      totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
    );
  }
}
