import 'assessment_model.dart';
import 'attendance_record.dart';

class ApiEnums {
  ApiEnums._();

  static String periodToApi(GradingPeriod period) => switch (period) {
        GradingPeriod.prelim => 'Prelim',
        GradingPeriod.midterm => 'Midterm',
        GradingPeriod.finals => 'Finals',
      };

  static GradingPeriod periodFromApi(String? value) => switch (value?.toLowerCase()) {
        'midterm' => GradingPeriod.midterm,
        'finals' => GradingPeriod.finals,
        _ => GradingPeriod.prelim,
      };

  static String statusToApi(AttendanceStatus status) => switch (status) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.excused => 'Excused',
      };

  static AttendanceStatus statusFromApi(String? value) => switch (value?.toLowerCase()) {
        'absent' => AttendanceStatus.absent,
        'late' => AttendanceStatus.late,
        'excused' => AttendanceStatus.excused,
        _ => AttendanceStatus.present,
      };

  static String dateToApi(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime dateFromApi(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed == null) return DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}