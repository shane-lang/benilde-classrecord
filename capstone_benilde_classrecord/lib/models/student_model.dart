class StudentModel {
  final String id;
  final String name;
  final String studentNumber;
  final String firstName;
  final String lastName;
  final bool isActive;

  StudentModel({
    required this.id,
    required this.name,
    required this.studentNumber,
    this.firstName = '',
    this.lastName = '',
    this.isActive = true,
  });

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    final first = json['firstName'] as String? ?? '';
    final last = json['lastName'] as String? ?? '';
    return StudentModel(
      id: '${json['enrollmentId']}',
      name: (json['fullName'] as String?)?.trim().isNotEmpty == true
          ? (json['fullName'] as String).trim()
          : '$first $last'.trim(),
      studentNumber: json['studentNumber'] as String? ?? '',
      firstName: first,
      lastName: last,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  static (String first, String last) splitName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, parts.first);
    return (parts.sublist(0, parts.length - 1).join(' '), parts.last);
  }
}