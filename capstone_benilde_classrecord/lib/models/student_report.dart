class StudentReport {
  final String enrollmentId;
  final String studentNumber;
  final String fullName;
  final String gradingPeriod;

  final double? periodGrade;
  final double? finalGrade;

  final String remark;

  final double? attendanceRate;
  final int daysPresent;
  final int daysRecorded;

  final List<CategoryResult> categories;

  const StudentReport({
    required this.enrollmentId,
    required this.studentNumber,
    required this.fullName,
    required this.gradingPeriod,
    this.periodGrade,
    this.finalGrade,
    this.remark = '',
    this.attendanceRate,
    this.daysPresent = 0,
    this.daysRecorded = 0,
    this.categories = const [],
  });

  static const empty = StudentReport(
    enrollmentId: '',
    studentNumber: '',
    fullName: '',
    gradingPeriod: 'Prelim',
  );

  factory StudentReport.fromJson(Map<String, dynamic> json) => StudentReport(
        enrollmentId: '${json['enrollmentId']}',
        studentNumber: json['studentNumber'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        gradingPeriod: json['gradingPeriod'] as String? ?? 'Prelim',
        periodGrade: (json['periodGrade'] as num?)?.toDouble(),
        finalGrade: (json['finalGrade'] as num?)?.toDouble(),
        remark: json['remark'] as String? ?? '',
        attendanceRate: (json['attendanceRate'] as num?)?.toDouble(),
        daysPresent: (json['daysPresent'] as num?)?.toInt() ?? 0,
        daysRecorded: (json['daysRecorded'] as num?)?.toInt() ?? 0,
        categories: (json['categories'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CategoryResult.fromJson)
                .toList() ??
            const [],
      );

  bool get isEmpty => categories.every((c) => c.percent == null);
}

class CategoryResult {
  final String categoryId;
  final String name;

  final double weight;

  final bool isAttendance;

  final double? percent;

  final double? effectiveWeight;

  final List<CategoryResult> children;

  const CategoryResult({
    required this.categoryId,
    required this.name,
    required this.weight,
    this.isAttendance = false,
    this.percent,
    this.effectiveWeight,
    this.children = const [],
  });

  factory CategoryResult.fromJson(Map<String, dynamic> json) => CategoryResult(
        categoryId: '${json['categoryId']}',
        name: json['name'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
        isAttendance: json['isAttendance'] as bool? ?? false,
        percent: (json['percent'] as num?)?.toDouble(),
        effectiveWeight: (json['effectiveWeight'] as num?)?.toDouble(),
        children: (json['children'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CategoryResult.fromJson)
                .toList() ??
            const [],
      );
}