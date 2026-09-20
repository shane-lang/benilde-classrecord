class AuthUser {
  final int id;
  final String email;
  final String fullName;
  final String? department;

  final bool isAdmin;

  final bool mustChangePassword;

  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.department,
    this.isAdmin = false,
    this.mustChangePassword = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        department: json['department'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'department': department,
        'isAdmin': isAdmin,
        'mustChangePassword': mustChangePassword,
      };

  AuthUser copyWith({bool? mustChangePassword}) => AuthUser(
        id: id,
        email: email,
        fullName: fullName,
        department: department,
        isAdmin: isAdmin,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Teacher' : parts.first;
  }
}