import '../models/assessment_model.dart';
import '../models/attendance_record.dart';
import '../models/class_model.dart';
import '../models/grading_category_model.dart';
import '../models/score_record.dart';
import '../models/student_model.dart';

class ClassStats {
  final ClassModel classModel;

  const ClassStats(this.classModel);

  List<GradingCategoryModel> _childrenOf(String parentId) {
    return classModel.gradingCategories
        .where((c) => c.parentId == parentId)
        .toList();
  }

  ScoreRecord? _findScore(String studentId, String assessmentId) {
    for (final s in classModel.scores) {
      if (s.studentId == studentId && s.assessmentId == assessmentId) {
        return s;
      }
    }
    return null;
  }

  double? _percentForCategory(
    String studentId,
    GradingPeriod period,
    String categoryId,
  ) {
    final assessments = classModel.assessments
        .where((a) => a.gradingPeriod == period && a.categoryId == categoryId)
        .toList();

    if (assessments.isEmpty) return null;

    double totalScore = 0;
    double totalMax = 0;
    bool hasAnyScore = false;

    for (final a in assessments) {
      final record = _findScore(studentId, a.id);
      if (record != null) {
        totalScore += record.score;
        totalMax += a.maxScore;
        hasAnyScore = true;
      }
    }

    if (!hasAnyScore || totalMax == 0) return null;
    return (totalScore / totalMax) * 100;
  }

  double? _percentForAnyCategory(
    String studentId,
    GradingPeriod period,
    GradingCategoryModel category,
  ) {
    if (category.isAttendance) {
      return attendancePercentForPeriod(studentId, period);
    }

    final children = _childrenOf(category.id);
    if (children.isEmpty) {
      return _percentForCategory(studentId, period, category.id);
    }

    double totalWeight = 0;
    double weightedSum = 0;
    for (final child in children) {
      final percent = _percentForAnyCategory(studentId, period, child);
      if (percent != null) {
        totalWeight += child.weight;
        weightedSum += child.weight * percent;
      }
    }
    if (totalWeight == 0) return null;
    return weightedSum / totalWeight;
  }

  double? attendancePercentForPeriod(String studentId, GradingPeriod period) {
    final records = classModel.attendanceRecords
        .where((r) => r.studentId == studentId && r.gradingPeriod == period)
        .toList();

    if (records.isEmpty) return null;

    final attended =
        records.where((r) => r.status != AttendanceStatus.absent).length;
    return (attended / records.length) * 100;
  }

  double? attendancePercent(String studentId) {
    final records = classModel.attendanceRecords
        .where((r) => r.studentId == studentId)
        .toList();

    if (records.isEmpty) return null;

    final attended =
        records.where((r) => r.status != AttendanceStatus.absent).length;
    return (attended / records.length) * 100;
  }

  double? get classAttendanceRate {
    final records = classModel.attendanceRecords;
    if (records.isEmpty) return null;

    final attended =
        records.where((r) => r.status != AttendanceStatus.absent).length;
    return (attended / records.length) * 100;
  }

  int get sessionsRecorded {
    final days = <String>{};
    for (final r in classModel.attendanceRecords) {
      days.add('${r.date.year}-${r.date.month}-${r.date.day}');
    }
    return days.length;
  }

  double? periodGrade(String studentId, GradingPeriod period) {
    double totalWeight = 0;
    double weightedSum = 0;

    final topLevel =
        classModel.gradingCategories.where((c) => c.parentId == null);

    for (final category in topLevel) {
      final percent = _percentForAnyCategory(studentId, period, category);
      if (percent != null) {
        totalWeight += category.weight;
        weightedSum += category.weight * percent;
      }
    }

    if (totalWeight == 0) return null;
    return weightedSum / totalWeight;
  }

  double? finalGrade(String studentId) {
    final grades = <double>[
      for (final period in GradingPeriod.values)
        if (periodGrade(studentId, period) != null)
          periodGrade(studentId, period)!,
    ];

    if (grades.isEmpty) return null;
    return grades.reduce((a, b) => a + b) / grades.length;
  }

  double? get classAverage {
    double total = 0;
    int count = 0;
    for (final s in classModel.activeStudents) {
      final grade = finalGrade(s.id);
      if (grade != null) {
        total += grade;
        count++;
      }
    }
    if (count == 0) return null;
    return total / count;
  }

  int atRiskCount({double passingGrade = 75}) {
    int count = 0;
    for (final s in classModel.activeStudents) {
      final grade = finalGrade(s.id);
      if (grade != null && grade < passingGrade) count++;
    }
    return count;
  }

  int get assessmentCount => classModel.assessments.length;

  int get missingScores {
    final students = classModel.activeStudents;
    if (students.isEmpty || classModel.assessments.isEmpty) return 0;

    int missing = 0;
    for (final StudentModel s in students) {
      for (final a in classModel.assessments) {
        if (_findScore(s.id, a.id) == null) missing++;
      }
    }
    return missing;
  }
}