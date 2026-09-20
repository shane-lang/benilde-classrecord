/// One class as the administrator's list shows it.
///
/// Deliberately thin: subject, section, school year, how many students, and
/// who holds it. No scores, no grades, no student names. An administrator
/// decides who may reach a record; reading the record stays with the teacher
/// who owns it, and the API sends nothing more than this.
class AdminClass {
  final int id;
  final String subjectCode;
  final String subjectName;
  final String course;
  final String yearSection;
  final String schoolYear;
  final bool isArchived;
  final int studentCount;
  final DateTime createdAt;

  final int teacherId;
  final String teacherName;
  final String teacherEmail;

  /// True when the owner can no longer sign in, so nobody can open this class
  /// until it is handed to someone else.
  final bool ownerIsInactive;

  const AdminClass({
    required this.id,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
    required this.teacherEmail,
    required this.createdAt,
    this.subjectCode = '',
    this.course = '',
    this.yearSection = '',
    this.schoolYear = '',
    this.isArchived = false,
    this.studentCount = 0,
    this.ownerIsInactive = false,
  });

  factory AdminClass.fromJson(Map<String, dynamic> json) => AdminClass(
        id: json['id'] as int,
        subjectCode: json['subjectCode'] as String? ?? '',
        subjectName: json['subjectName'] as String? ?? '',
        course: json['course'] as String? ?? '',
        yearSection: json['yearSection'] as String? ?? '',
        schoolYear: json['schoolYear'] as String? ?? '',
        isArchived: json['isArchived'] as bool? ?? false,
        studentCount: json['studentCount'] as int? ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        teacherId: json['teacherId'] as int? ?? 0,
        teacherName: json['teacherName'] as String? ?? '',
        teacherEmail: json['teacherEmail'] as String? ?? '',
        ownerIsInactive: json['ownerIsInactive'] as bool? ?? false,
      );

  /// "CC102 — Data Structures", or just the name when there is no code.
  String get title => subjectCode.trim().isEmpty
      ? subjectName
      : '$subjectCode — $subjectName';

  /// "BSIT 1A · A.Y. 2026–2027", with the empty parts left out.
  String get subtitle {
    final parts = <String>[
      [course, yearSection].where((p) => p.trim().isNotEmpty).join(' ').trim(),
      if (schoolYear.trim().isNotEmpty) 'A.Y. ${schoolYear.trim()}',
    ].where((p) => p.isNotEmpty).toList();
    return parts.join('  ·  ');
  }

  /// The class cannot be opened by anyone: its owner cannot sign in.
  bool get isStranded => ownerIsInactive;
}