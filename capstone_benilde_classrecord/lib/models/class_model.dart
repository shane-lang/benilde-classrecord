import 'student_model.dart';
import 'attendance_record.dart';
import 'assessment_model.dart';
import 'score_record.dart';
import 'grading_category_model.dart';
import 'class_schedule_model.dart';

class ClassModel {
  final String id;
  final String subjectName;
  final String subjectCode;
  final String course;
  final String yearSection;
  final String schoolYear;

  final int studentCount;

  final bool hasSchedule;

  final double prelimWeight;
  final double midtermWeight;
  final double finalsWeight;

  bool get hasPeriodWeights =>
      prelimWeight + midtermWeight + finalsWeight > 0;

  bool isArchived;

  bool prelimLocked;
  bool midtermLocked;
  bool finalsLocked;

  void setLock(GradingPeriod period, bool locked) {
    switch (period) {
      case GradingPeriod.prelim:
        prelimLocked = locked;
      case GradingPeriod.midterm:
        midtermLocked = locked;
      case GradingPeriod.finals:
        finalsLocked = locked;
    }
  }

  bool lockedFor(GradingPeriod period) => switch (period) {
        GradingPeriod.prelim => prelimLocked,
        GradingPeriod.midterm => midtermLocked,
        GradingPeriod.finals => finalsLocked,
      };

  final DateTime? createdAt;
  final List<StudentModel> students;
  final List<AttendanceRecord> attendanceRecords;
  final List<AssessmentModel> assessments;
  final List<ScoreRecord> scores;
  final List<GradingCategoryModel> gradingCategories;

  ClassScheduleModel? schedule;

  List<StudentModel> get activeStudents =>
      students.where((s) => s.isActive).toList();

  ClassModel({
    required this.id,
    required this.subjectName,
    this.subjectCode = '',
    required this.course,
    required this.yearSection,
    this.schoolYear = '',
    this.studentCount = 0,
    this.hasSchedule = false,
    this.prelimWeight = 0,
    this.midtermWeight = 0,
    this.finalsWeight = 0,
    this.isArchived = false,
    this.prelimLocked = false,
    this.midtermLocked = false,
    this.finalsLocked = false,
    this.createdAt,
    List<StudentModel>? students,
    List<AttendanceRecord>? attendanceRecords,
    List<AssessmentModel>? assessments,
    List<ScoreRecord>? scores,
    List<GradingCategoryModel>? gradingCategories,
    this.schedule,
  })  : students = students ?? [],
        attendanceRecords = attendanceRecords ?? [],
        assessments = assessments ?? [],
        scores = scores ?? [],
        gradingCategories = gradingCategories ??
            [

              GradingCategoryModel(
                id: 'attendance',
                name: 'Attendance',
                weight: 0.05,
                isAttendance: true,
              ),
              GradingCategoryModel(id: 'quizzes', name: 'Quizzes', weight: 0.20),
              GradingCategoryModel(
                id: 'activities',
                name: 'Activities/Seatwork',
                weight: 0.15,
              ),
              GradingCategoryModel(
                id: 'performance_task',
                name: 'Performance Task',
                weight: 0.15,
              ),
              GradingCategoryModel(id: 'project', name: 'Project', weight: 0.10),
              GradingCategoryModel(
                id: 'major_exam',
                name: 'Major Exam (Midterm/Final)',
                weight: 0.35,
              ),
            ];

  factory ClassModel.fromJson(Map<String, dynamic> json) => ClassModel(
        id: '${json['id']}',
        subjectName: json['subjectName'] as String? ?? '',
        subjectCode: json['subjectCode'] as String? ?? '',
        course: json['course'] as String? ?? '',
        yearSection: json['yearSection'] as String? ?? '',
        schoolYear: json['schoolYear'] as String? ?? '',
        studentCount: (json['studentCount'] as num?)?.toInt() ?? 0,
        hasSchedule: json['hasSchedule'] as bool? ?? false,
        prelimWeight: (json['prelimWeight'] as num?)?.toDouble() ?? 0,
        midtermWeight: (json['midtermWeight'] as num?)?.toDouble() ?? 0,
        finalsWeight: (json['finalsWeight'] as num?)?.toDouble() ?? 0,
        isArchived: json['isArchived'] as bool? ?? false,
        prelimLocked: json['prelimLocked'] as bool? ?? false,
        midtermLocked: json['midtermLocked'] as bool? ?? false,
        finalsLocked: json['finalsLocked'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  Map<String, dynamic> toRequestJson() => {
        'subjectName': subjectName,
        'subjectCode': subjectCode,
        'course': course,
        'yearSection': yearSection,
        'schoolYear': schoolYear,
        'prelimWeight': prelimWeight,
        'midtermWeight': midtermWeight,
        'finalsWeight': finalsWeight,
      };
}