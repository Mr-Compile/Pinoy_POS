class BackupHistory {
  final int? id;
  final String filePath;
  final int? fileSize;
  final int? createdBy;
  final DateTime createdAt;

  BackupHistory({
    this.id,
    required this.filePath,
    this.fileSize,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_size': fileSize,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BackupHistory.fromMap(Map<String, dynamic> map) {
    return BackupHistory(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      fileSize: map['file_size'] as int?,
      createdBy: map['created_by'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  BackupHistory copyWith({
    int? id,
    String? filePath,
    int? fileSize,
    int? createdBy,
    DateTime? createdAt,
  }) {
    return BackupHistory(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
