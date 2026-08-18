class ExportHistory {
  final int? id;
  final String reportType;
  final String fileFormat;
  final String filePath;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final int? createdBy;
  final DateTime createdAt;

  ExportHistory({
    this.id,
    required this.reportType,
    required this.fileFormat,
    required this.filePath,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'report_type': reportType,
      'file_format': fileFormat,
      'file_path': filePath,
      'date_range_start': dateRangeStart?.toIso8601String(),
      'date_range_end': dateRangeEnd?.toIso8601String(),
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ExportHistory.fromMap(Map<String, dynamic> map) {
    return ExportHistory(
      id: map['id'] as int?,
      reportType: map['report_type'] as String,
      fileFormat: map['file_format'] as String,
      filePath: map['file_path'] as String,
      dateRangeStart: map['date_range_start'] != null
          ? DateTime.parse(map['date_range_start'] as String)
          : null,
      dateRangeEnd: map['date_range_end'] != null
          ? DateTime.parse(map['date_range_end'] as String)
          : null,
      createdBy: map['created_by'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  ExportHistory copyWith({
    int? id,
    String? reportType,
    String? fileFormat,
    String? filePath,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
    int? createdBy,
    DateTime? createdAt,
  }) {
    return ExportHistory(
      id: id ?? this.id,
      reportType: reportType ?? this.reportType,
      fileFormat: fileFormat ?? this.fileFormat,
      filePath: filePath ?? this.filePath,
      dateRangeStart: dateRangeStart ?? this.dateRangeStart,
      dateRangeEnd: dateRangeEnd ?? this.dateRangeEnd,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
