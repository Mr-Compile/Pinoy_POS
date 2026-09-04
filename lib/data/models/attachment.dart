import 'package:pinoy_pos/core/file_type_utils.dart';

/// A generic file attachment linked to an entity.
///
/// Attachments can be images, PDFs, manuals, or any other supported file.
/// They follow the entity lifecycle: soft-deleted with the entity, restored
/// with the entity, and physically deleted when the entity is permanently
/// deleted.
class Attachment {
  final int? id;
  final String entityType;
  final int entityId;
  final String filePath;
  final String mimeType;
  final String fileName;
  final String? attachmentType;
  final bool isActive;
  final DateTime? deletedAt;
  final DateTime createdAt;

  const Attachment({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.filePath,
    required this.mimeType,
    required this.fileName,
    this.attachmentType,
    this.isActive = true,
    this.deletedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'file_path': filePath,
      'mime_type': mimeType,
      'file_name': fileName,
      'attachment_type': attachmentType,
      'is_active': isActive ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Attachment.fromMap(Map<String, dynamic> map) {
    return Attachment(
      id: map['id'] as int?,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int,
      filePath: map['file_path'] as String,
      mimeType: map['mime_type'] as String,
      fileName: map['file_name'] as String,
      attachmentType: map['attachment_type'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Attachment copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? filePath,
    String? mimeType,
    String? fileName,
    String? attachmentType,
    bool? isActive,
    DateTime? deletedAt,
    DateTime? createdAt,
  }) {
    return Attachment(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      filePath: filePath ?? this.filePath,
      mimeType: mimeType ?? this.mimeType,
      fileName: fileName ?? this.fileName,
      attachmentType: attachmentType ?? this.attachmentType,
      isActive: isActive ?? this.isActive,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isDeleted => deletedAt != null;
  bool get isImage => FileTypeUtils.isImage(mimeType);
  bool get isPdf => FileTypeUtils.isPdf(mimeType);
  FileType? get fileType => FileType.fromMime(mimeType);
}
