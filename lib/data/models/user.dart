enum UserRole {
  owner,
  admin,
  staff;

  /// Human-readable display name for the role.
  String get displayName => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.admin => 'System Admin',
        UserRole.staff => 'Staff',
      };
}

class User {
  final int? id;
  final String username;
  final String passwordHash;
  final String? pin;
  final UserRole role;
  final String fullName;
  final String colorPreference;
  final bool isActive;
  final String? colorPreference;
  final DateTime? lastLogin;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  User({
    this.id,
    required this.username,
    required this.passwordHash,
    this.pin,
    required this.role,
    required this.fullName,
    this.colorPreference = 'green',
    this.isActive = true,
    this.colorPreference,
    this.lastLogin,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password_hash': passwordHash,
      'pin': pin,
      'role': role.name,
      'full_name': fullName,
      'color_preference': colorPreference,
      'is_active': isActive ? 1 : 0,
      'color_preference': colorPreference,
      'last_login': lastLogin?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      username: map['username'] as String,
      passwordHash: map['password_hash'] as String,
      pin: map['pin'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => UserRole.staff,
      ),
      fullName: map['full_name'] as String,
      colorPreference: (map['color_preference'] as String?) ?? 'green',
      isActive: (map['is_active'] as int) == 1,
      colorPreference: map['color_preference'] as String?,
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? passwordHash,
    String? pin,
    UserRole? role,
    String? fullName,
    String? colorPreference,
    bool? isActive,
    String? colorPreference,
    DateTime? lastLogin,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      pin: pin ?? this.pin,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      colorPreference: colorPreference ?? this.colorPreference,
      isActive: isActive ?? this.isActive,
      colorPreference: colorPreference ?? this.colorPreference,
      lastLogin: lastLogin ?? this.lastLogin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;
}