class ClassStanding {
  final double passingGrade;
  final double? prelimAverage;
  final double? midtermAverage;
  final double? finalsAverage;
  final double? classAverage;
  final int passingCount;
  final int atRiskCount;
  final bool weightsUnbalanced;
  final double weightTotal;
  final List<CategoryAverage> categoryAverages;
  final List<StudentGrade> students;

  const ClassStanding({
    required this.passingGrade,
    this.prelimAverage,
    this.midtermAverage,
    this.finalsAverage,
    this.classAverage,
    this.passingCount = 0,
    this.atRiskCount = 0,
    this.weightsUnbalanced = false,
    this.weightTotal = 0,
    this.categoryAverages = const [],
    this.students = const [],
  });

  static const empty = ClassStanding(passingGrade: 75);

  factory ClassStanding.fromJson(Map<String, dynamic> json) => ClassStanding(
        passingGrade: (json['passingGrade'] as num?)?.toDouble() ?? 75,
        prelimAverage: (json['prelimAverage'] as num?)?.toDouble(),
        midtermAverage: (json['midtermAverage'] as num?)?.toDouble(),
        finalsAverage: (json['finalsAverage'] as num?)?.toDouble(),
        classAverage: (json['classAverage'] as num?)?.toDouble(),
        passingCount: (json['passingCount'] as num?)?.toInt() ?? 0,
        atRiskCount: (json['atRiskCount'] as num?)?.toInt() ?? 0,
        weightsUnbalanced: json['weightsUnbalanced'] as bool? ?? false,
        weightTotal: (json['weightTotal'] as num?)?.toDouble() ?? 0,
        categoryAverages: (json['categoryAverages'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CategoryAverage.fromJson)
                .toList() ??
            const [],
        students: (json['students'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(StudentGrade.fromJson)
                .toList() ??
            const [],
      );

  double? averageFor(String categoryId) {
    for (final c in categoryAverages) {
      if (c.categoryId == categoryId) return c.average;
    }
    return null;
  }

  int itemCountFor(String categoryId) {
    for (final c in categoryAverages) {
      if (c.categoryId == categoryId) return c.itemCount;
    }
    return 0;
  }
}

class CategoryAverage {
  final String categoryId;
  final String name;
  final double weight;
  final bool isAttendance;

  final double? average;
  final int itemCount;

  const CategoryAverage({
    required this.categoryId,
    required this.name,
    required this.weight,
    required this.isAttendance,
    this.average,
    this.itemCount = 0,
  });

  factory CategoryAverage.fromJson(Map<String, dynamic> json) => CategoryAverage(
        categoryId: '${json['categoryId']}',
        name: json['name'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
        isAttendance: json['isAttendance'] as bool? ?? false,
        average: (json['average'] as num?)?.toDouble(),
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      );
}

class StudentGrade {

  final String enrollmentId;
  final String studentNumber;
  final String fullName;
  final double? prelim;
  final double? midterm;
  final double? finals;
  final double? finalGrade;

  final String remark;

  const StudentGrade({
    required this.enrollmentId,
    required this.studentNumber,
    required this.fullName,
    this.prelim,
    this.midterm,
    this.finals,
    this.finalGrade,
    this.remark = '',
  });

  factory StudentGrade.fromJson(Map<String, dynamic> json) => StudentGrade(
        enrollmentId: '${json['enrollmentId']}',
        studentNumber: json['studentNumber'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        prelim: (json['prelim'] as num?)?.toDouble(),
        midterm: (json['midterm'] as num?)?.toDouble(),
        finals: (json['finals'] as num?)?.toDouble(),
        finalGrade: (json['finalGrade'] as num?)?.toDouble(),
        remark: json['remark'] as String? ?? '',
      );

  double? gradeFor(int periodIndex) => switch (periodIndex) {
        0 => prelim,
        1 => midterm,
        2 => finals,
        _ => null,
      };
}