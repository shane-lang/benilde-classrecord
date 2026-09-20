class TeacherInvite {
  final int id;
  final String email;
  final String fullName;
  final String? department;
  final bool isAdmin;
  final String invitedBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;

  final String status;

  const TeacherInvite({
    required this.id,
    required this.email,
    required this.fullName,
    required this.invitedBy,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    this.department,
    this.isAdmin = false,
    this.acceptedAt,
  });

  bool get isPending => status == 'Pending';
  bool get isAccepted => status == 'Accepted';
  bool get isExpired => status == 'Expired';

  int get daysLeft {
    if (!isPending) return 0;
    final left = expiresAt.difference(DateTime.now()).inHours;
    return left <= 0 ? 0 : (left / 24).ceil();
  }

  factory TeacherInvite.fromJson(Map<String, dynamic> json) => TeacherInvite(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        department: json['department'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
        invitedBy: json['invitedBy'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        acceptedAt: DateTime.tryParse(json['acceptedAt'] as String? ?? '')?.toLocal(),
        status: json['status'] as String? ?? 'Pending',
      );
}

class NewInvite {
  final TeacherInvite invite;
  final String code;

  const NewInvite({required this.invite, required this.code});

  factory NewInvite.fromJson(Map<String, dynamic> json) => NewInvite(
        invite: TeacherInvite.fromJson(
            (json['invite'] as Map<String, dynamic>?) ?? const {}),
        code: json['code'] as String? ?? '',
      );
}