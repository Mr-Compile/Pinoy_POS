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

extension UserRoleManagement on UserRole {
  /// Whether a user with [managerRole] is allowed to create or manage
  /// accounts with this role.
  ///
  /// Explicit matrix (rows = target role, columns = manager role):
  ///
  /// | Target | Owner | Admin | Staff |
  /// |--------|-------|-------|-------|
  /// | Owner  |  YES  |  YES  |  NO   |
  /// | Admin  |  YES  |  NO   |  NO   |
  /// | Staff  |  YES  |  YES  |  NO   |
  ///
  /// Owner has full control. Admin can create and manage Owner and Staff,
  /// but not another Admin. Staff cannot manage any role.
  bool canBeManagedBy(UserRole managerRole) => switch (managerRole) {
        UserRole.owner => true,
        UserRole.admin =>
            this == UserRole.owner || this == UserRole.staff,
        UserRole.staff => false,
      };

  /// The roles that a user with [managerRole] is allowed to create or assign.
  static List<UserRole> manageableBy(UserRole managerRole) =>
      UserRole.values.where((role) => role.canBeManagedBy(managerRole)).toList();
}

class User {
  /// Sentinel used by [copyWith] to keep the existing value unchanged.
  /// Pass `inactivityTimeoutSentinel` explicitly to clear the override.
  static const Object inactivityTimeoutSentinel = Object();

  final int? id;
  final String username;
  final String passwordHash;
  final String? pin;
  final int? pinLength;
  final UserRole role;
  final String fullName;
  final String colorPreference;
  final String? profileImagePath;
  final bool isActive;
  final bool mustChangePassword;
  final bool hasChangedUsername;
  final DateTime? lastLogin;
  final int? inactivityTimeoutMinutes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  User({
    this.id,
    required this.username,
    required this.passwordHash,
    this.pin,
    this.pinLength,
    required this.role,
    required this.fullName,
    this.colorPreference = 'green',
    this.profileImagePath,
    this.isActive = true,
    this.mustChangePassword = false,
    this.hasChangedUsername = false,
    this.lastLogin,
    this.inactivityTimeoutMinutes,
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
      'pin_length': pinLength,
      'role': role.name,
      'full_name': fullName,
      'color_preference': colorPreference,
      'profile_image_path': profileImagePath,
      'is_active': isActive ? 1 : 0,
      'must_change_password': mustChangePassword ? 1 : 0,
      'has_changed_username': hasChangedUsername ? 1 : 0,
      'last_login': lastLogin?.toIso8601String(),
      'inactivity_timeout_minutes': inactivityTimeoutMinutes,
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
      pinLength: map['pin_length'] as int?,
      role: UserRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => UserRole.staff,
      ),
      fullName: map['full_name'] as String,
      colorPreference: (map['color_preference'] as String?) ?? 'green',
      profileImagePath: map['profile_image_path'] as String?,
      isActive: (map['is_active'] as int) == 1,
      mustChangePassword: (map['must_change_password'] as int?) == 1,
      hasChangedUsername: (map['has_changed_username'] as int?) == 1,
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
      inactivityTimeoutMinutes: map['inactivity_timeout_minutes'] is int
          ? map['inactivity_timeout_minutes'] as int
          : int.tryParse(map['inactivity_timeout_minutes']?.toString() ?? ''),
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
    int? pinLength,
    UserRole? role,
    String? fullName,
    String? colorPreference,
    String? profileImagePath,
    bool? isActive,
    bool? mustChangePassword,
    bool? hasChangedUsername,
    DateTime? lastLogin,
    Object? inactivityTimeoutMinutes = inactivityTimeoutSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      pin: pin ?? this.pin,
      pinLength: pinLength ?? this.pinLength,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      colorPreference: colorPreference ?? this.colorPreference,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      isActive: isActive ?? this.isActive,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      hasChangedUsername: hasChangedUsername ?? this.hasChangedUsername,
      lastLogin: lastLogin ?? this.lastLogin,
      inactivityTimeoutMinutes: inactivityTimeoutMinutes == inactivityTimeoutSentinel
          ? this.inactivityTimeoutMinutes
          : inactivityTimeoutMinutes as int?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;

  /// Whether this user has a PIN configured.
  bool get hasPin => pin != null && pin!.isNotEmpty;

  /// The number of digits in this user's configured PIN.
  /// Returns 0 if no PIN is set or pinLength is null.
  int get configuredPinLength => pinLength ?? 0;
}
