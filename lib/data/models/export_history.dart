/// Status values for the report submission lifecycle.
class ReportStatus {
  ReportStatus._();

  static const String generated = 'generated';
  static const String submitted = 'submitted';
  static const String viewed = 'viewed';
  static const String archived = 'archived';
  static const String imported = 'imported';
}

class ExportHistory {
  final int? id;
  final String reportType;
  final String fileFormat;
  final String filePath;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final int? createdBy;
  final DateTime createdAt;
  final String status;
  final DateTime? submittedAt;
  final DateTime? viewedAt;
  final int? fileSize;
  final String? thumbnailPath;
  final String? reportNumber;
  final DateTime? deletedAt;

  ExportHistory({
    this.id,
    required this.reportType,
    required this.fileFormat,
    required this.filePath,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.createdBy,
    required this.createdAt,
    this.status = ReportStatus.generated,
    this.submittedAt,
    this.viewedAt,
    this.fileSize,
    this.thumbnailPath,
    this.reportNumber,
    this.deletedAt,
  });

  bool get isSubmitted => status == ReportStatus.submitted;
  bool get isViewed => status == ReportStatus.viewed;
  bool get isArchived => status == ReportStatus.archived;

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
      'status': status,
      'submitted_at': submittedAt?.toIso8601String(),
      'viewed_at': viewedAt?.toIso8601String(),
      'file_size': fileSize,
      'thumbnail_path': thumbnailPath,
      'report_number': reportNumber,
      'deleted_at': deletedAt?.toIso8601String(),
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
      status: map['status'] as String? ?? ReportStatus.generated,
      submittedAt: map['submitted_at'] != null
          ? DateTime.parse(map['submitted_at'] as String)
          : null,
      viewedAt: map['viewed_at'] != null
          ? DateTime.parse(map['viewed_at'] as String)
          : null,
      fileSize: map['file_size'] as int?,
      thumbnailPath: map['thumbnail_path'] as String?,
      reportNumber: map['report_number'] as String?,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
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
    String? status,
    DateTime? submittedAt,
    DateTime? viewedAt,
    int? fileSize,
    String? thumbnailPath,
    String? reportNumber,
    DateTime? deletedAt,
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
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      viewedAt: viewedAt ?? this.viewedAt,
      fileSize: fileSize ?? this.fileSize,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      reportNumber: reportNumber ?? this.reportNumber,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
