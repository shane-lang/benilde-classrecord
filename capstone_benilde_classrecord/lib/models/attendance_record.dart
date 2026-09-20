import 'api_enums.dart';
import 'assessment_model.dart';

enum AttendanceStatus { present, absent, late, excused }

class AttendanceRecord {
  final String studentId;
  final DateTime date;
  final AttendanceStatus status;
  final GradingPeriod gradingPeriod;
  final String? remarks;

  AttendanceRecord({
    required this.studentId,
    required this.date,
    required this.status,
    required this.gradingPeriod,
    this.remarks,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        studentId: '${json['enrollmentId']}',
        date: ApiEnums.dateFromApi(json['date'] as String?),
        status: ApiEnums.statusFromApi(json['status'] as String?),
        gradingPeriod: ApiEnums.periodFromApi(json['gradingPeriod'] as String?),
        remarks: json['remarks'] as String?,
      );

  bool isSameDate(DateTime other) {
    return date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
  }
}