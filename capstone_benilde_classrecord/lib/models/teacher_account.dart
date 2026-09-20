class TeacherAccount {
  final int id;
  final String email;
  final String fullName;
  final String? department;
  final bool isActive;
  final bool isAdmin;
  final bool mustChangePassword;
  final int classCount;
  final DateTime? lastLoginAt;

  const TeacherAccount({
    required this.id,
    required this.email,
    required this.fullName,
    this.department,
    this.isActive = true,
    this.isAdmin = false,
    this.mustChangePassword = false,
    this.classCount = 0,
    this.lastLoginAt,
  });

  factory TeacherAccount.fromJson(Map<String, dynamic> json) => TeacherAccount(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        department: json['department'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        isAdmin: json['isAdmin'] as bool? ?? false,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
        classCount: (json['classCount'] as num?)?.toInt() ?? 0,
        lastLoginAt: DateTime.tryParse(json['lastLoginAt'] as String? ?? '')?.toLocal(),
      );
}