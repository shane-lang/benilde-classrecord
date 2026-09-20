import '../models/admin_class.dart';
import '../models/api_enums.dart';
import '../models/assessment_model.dart';
import '../models/attendance_record.dart';
import '../models/class_model.dart';
import '../models/class_schedule_model.dart';
import '../models/class_standing.dart';
import '../models/audit_entry.dart';
import '../models/teacher_account.dart';
import '../models/teacher_invite.dart';
import '../models/student_report.dart';
import '../models/grading_category_model.dart';
import '../models/score_record.dart';
import '../models/student_model.dart';
import 'api_client.dart';
import 'auth_service.dart';

class ClassRepository {
  ClassRepository._();

  static final ClassRepository instance = ClassRepository._();

  ApiClient get _api => AuthService.instance.api;

  Future<List<ClassModel>> fetchClasses({bool includeArchived = false}) async {
    final rows = await _api.getList(
      includeArchived ? 'classes?includeArchived=true' : 'classes',
    );
    return rows.map(ClassModel.fromJson).toList();
  }

  Future<void> setClassArchived(String classId, bool archived) async {
    await _api.put('classes/$classId/archive', {'archived': archived});
  }

  Future<void> setPeriodLock(
    String classId,
    GradingPeriod period,
    bool locked,
  ) async {
    await _api.put(
      'classes/$classId/periods/${ApiEnums.periodToApi(period)}/lock',
      {'locked': locked},
    );
  }

  Future<List<AuditEntry>> fetchHistory(String classId, {int limit = 100}) async {
    final rows = await _api.getList('classes/$classId/history?limit=$limit');
    return rows.map(AuditEntry.fromJson).toList();
  }

  Future<List<TeacherAccount>> fetchTeachers() async {
    final rows = await _api.getList('admin/teachers');
    return rows.map(TeacherAccount.fromJson).toList();
  }

  Future<String> createTeacher({
    required String email,
    required String fullName,
    String? department,
    String? password,
    bool isAdmin = false,
  }) async {
    final body = await _api.post('admin/teachers', {
      'email': email.trim(),
      'fullName': fullName.trim(),
      if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
      if (password != null && password.isNotEmpty) 'password': password,
      'isAdmin': isAdmin,
    });
    return body['temporaryPassword'] as String? ?? '';
  }

  Future<void> setTeacherActive(int teacherId, bool active) async {
    await _api.put('admin/teachers/$teacherId/active', {'active': active});
  }

  Future<void> setTeacherAdmin(int teacherId, bool isAdmin) async {
    await _api.put('admin/teachers/$teacherId/role', {'isAdmin': isAdmin});
  }

  Future<List<TeacherInvite>> fetchInvites() async {
    final rows = await _api.getList('admin/invites');
    return rows.map(TeacherInvite.fromJson).toList();
  }

  Future<NewInvite> createInvite({
    required String email,
    required String fullName,
    String? department,
    bool isAdmin = false,
    int daysValid = 7,
  }) async {
    final body = await _api.post('admin/invites', {
      'email': email.trim(),
      'fullName': fullName.trim(),
      if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
      'isAdmin': isAdmin,
      'daysValid': daysValid,
    });
    return NewInvite.fromJson(body);
  }

  Future<void> revokeInvite(int inviteId) async {
    await _api.delete('admin/invites/$inviteId');
  }

  Future<List<AdminClass>> fetchAllClasses() async {
    final rows = await _api.getList('admin/classes');
    return rows.map(AdminClass.fromJson).toList();
  }

  Future<void> transferClass(int classId, int toTeacherId, {String? reason}) async {
    await _api.put('admin/classes/$classId/teacher', {
      'teacherId': toTeacherId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  Future<String> resetTeacherPassword(int teacherId) async {
    final body = await _api.post('admin/teachers/$teacherId/reset-password', const {});
    return body['temporaryPassword'] as String? ?? '';
  }

  Future<ClassModel> createClass(ClassModel draft) async {
    final json = await _api.post('classes', draft.toRequestJson());
    return ClassModel.fromJson(json);
  }

  Future<void> updateClass(ClassModel cls) async {
    await _api.put('classes/${cls.id}', cls.toRequestJson());
  }

  Future<void> deleteClass(String classId) async {
    await _api.delete('classes/$classId');
  }

  Future<ClassModel> fetchClassDetail(String classId) async {
    final detail = await _api.get('classes/$classId');

    final results = await Future.wait([
      _api.getList('classes/$classId/students'),
      _api.getList('classes/$classId/assessments'),
      _api.getList('classes/$classId/scores'),
      _api.getList('classes/$classId/attendance'),
    ]);

    final cls = ClassModel.fromJson(detail);
    cls.students.addAll(results[0].map(StudentModel.fromJson));
    cls.assessments.addAll(results[1].map(AssessmentModel.fromJson));
    cls.scores.addAll(results[2].map(ScoreRecord.fromJson));
    cls.attendanceRecords.addAll(results[3].map(AttendanceRecord.fromJson));

    cls.gradingCategories
      ..clear()
      ..addAll(GradingCategoryModel.listFromJson(
        (detail['categories'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [],
      ));

    final schedule = detail['schedule'];
    if (schedule is Map<String, dynamic>) {
      cls.schedule = ClassScheduleModel.fromJson(schedule);
    }

    return cls;
  }

  Future<List<StudentModel>> fetchRoster(String classId) async {
    final rows = await _api.getList('classes/$classId/students');
    return rows.map(StudentModel.fromJson).toList();
  }

  Future<List<StudentModel>> enrollStudents(
    String classId,
    List<({String studentNumber, String fullName})> students,
  ) async {
    final rows = await _api.postList('classes/$classId/students', {
      'students': [
        for (final s in students)
          () {
            final (first, last) = StudentModel.splitName(s.fullName);
            return {
              'studentNumber': s.studentNumber,
              'firstName': first,
              'lastName': last,
            };
          }()
      ],
    });
    return rows.map(StudentModel.fromJson).toList();
  }

  Future<void> updateStudent(String classId, StudentModel student) async {
    final (first, last) = StudentModel.splitName(student.name);
    await _api.put('classes/$classId/students/${student.id}', {
      'firstName': first,
      'lastName': last,
      'studentNumber': student.studentNumber,
      'isActive': student.isActive,
    });
  }

  Future<void> removeStudent(String classId, String enrollmentId) async {
    await _api.delete('classes/$classId/students/$enrollmentId');
  }

  Future<List<GradingCategoryModel>> fetchCategories(String classId) async {
    final rows = await _api.getList('classes/$classId/categories');
    return GradingCategoryModel.listFromJson(rows);
  }

  Future<GradingCategoryModel> createCategory(
    String classId, {
    required String name,
    required double weight,
    String? parentId,
    int sortOrder = 0,
  }) async {
    final json = await _api.post('classes/$classId/categories', {
      'name': name,
      'weight': weight,
      'parentId': parentId == null ? null : int.tryParse(parentId),
      'sortOrder': sortOrder,
    });
    return GradingCategoryModel.fromJson(json);
  }

  Future<void> updateCategory(
    String classId,
    GradingCategoryModel category, {
    int sortOrder = 0,
  }) async {
    await _api.put('classes/$classId/categories/${category.id}', {
      'name': category.name,
      'weight': category.weight,
      'sortOrder': sortOrder,
    });
  }

  Future<void> deleteCategory(String classId, String categoryId) async {
    await _api.delete('classes/$classId/categories/$categoryId');
  }

  Future<List<AssessmentModel>> fetchAssessments(
    String classId, {
    GradingPeriod? period,
    String? categoryId,
  }) async {
    final query = <String>[
      if (period != null) 'period=${ApiEnums.periodToApi(period)}',
      if (categoryId != null) 'categoryId=$categoryId',
    ];
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';
    final rows = await _api.getList('classes/$classId/assessments$suffix');
    return rows.map(AssessmentModel.fromJson).toList();
  }

  Future<AssessmentModel> createAssessment(
    String categoryId, {
    required String name,
    required double maxScore,
    required GradingPeriod period,
  }) async {
    final json = await _api.post('categories/$categoryId/assessments', {
      'name': name,
      'maxScore': maxScore,
      'gradingPeriod': ApiEnums.periodToApi(period),
    });
    return AssessmentModel.fromJson(json);
  }

  Future<List<AssessmentModel>> createAssessmentSeries(
    String categoryId, {
    required String namePrefix,
    required int count,
    required double maxScore,
    required GradingPeriod period,
  }) async {
    final rows = await _api.postList('categories/$categoryId/assessments/series', {
      'namePrefix': namePrefix,
      'count': count,
      'maxScore': maxScore,
      'gradingPeriod': ApiEnums.periodToApi(period),
    });
    return rows.map(AssessmentModel.fromJson).toList();
  }

  Future<void> updateAssessment(AssessmentModel assessment) async {
    await _api.put('assessments/${assessment.id}', {
      'name': assessment.name,
      'maxScore': assessment.maxScore,
      'gradingPeriod': ApiEnums.periodToApi(assessment.gradingPeriod),
    });
  }

  Future<void> deleteAssessment(String assessmentId) async {
    await _api.delete('assessments/$assessmentId');
  }

  Future<List<ScoreRecord>> fetchScores(String classId, {GradingPeriod? period}) async {
    final suffix = period == null ? '' : '?period=${ApiEnums.periodToApi(period)}';
    final rows = await _api.getList('classes/$classId/scores$suffix');
    return rows.map(ScoreRecord.fromJson).toList();
  }

  Future<void> saveScores(
    String classId,
    List<({String assessmentId, String enrollmentId, double? score})> scores,
  ) async {
    await _api.put('classes/$classId/scores', {
      'scores': [
        for (final s in scores)
          {
            'assessmentId': int.tryParse(s.assessmentId),
            'enrollmentId': int.tryParse(s.enrollmentId),
            'score': s.score,
          }
      ],
    });
  }

  Future<List<AttendanceRecord>> fetchAttendance(
    String classId, {
    GradingPeriod? period,
  }) async {
    final suffix = period == null ? '' : '?period=${ApiEnums.periodToApi(period)}';
    final rows = await _api.getList('classes/$classId/attendance$suffix');
    return rows.map(AttendanceRecord.fromJson).toList();
  }

  Future<List<DateTime>> fetchClassDays(String classId, GradingPeriod period) async {
    final rows = await _api.getList(
      'classes/$classId/attendance/days?period=${ApiEnums.periodToApi(period)}',
    );
    return rows.map((r) => ApiEnums.dateFromApi(r['date'] as String?)).toList();
  }

  Future<void> saveAttendance(
    String classId,
    List<({
      String enrollmentId,
      DateTime date,
      AttendanceStatus? status,
      GradingPeriod period,
      String? remarks,
    })> records,
  ) async {
    await _api.put('classes/$classId/attendance', {
      'records': [
        for (final r in records)
          {
            'enrollmentId': int.tryParse(r.enrollmentId),
            'date': ApiEnums.dateToApi(r.date),
            'status': r.status == null ? null : ApiEnums.statusToApi(r.status!),
            'gradingPeriod': ApiEnums.periodToApi(r.period),
            'remarks': r.remarks,
          }
      ],
    });
  }

  Future<void> deleteAttendanceDay(String classId, DateTime date) async {
    await _api.delete('classes/$classId/attendance/${ApiEnums.dateToApi(date)}');
  }

  Future<ClassScheduleModel?> fetchSchedule(String classId) async {
    try {
      final json = await _api.get('classes/$classId/schedule');
      return ClassScheduleModel.fromJson(json);
    } catch (_) {

      return null;
    }
  }

  Future<ClassScheduleModel> saveSchedule(
    String classId,
    ClassScheduleModel schedule,
  ) async {
    final json = await _api.put('classes/$classId/schedule', schedule.toRequestJson());
    return ClassScheduleModel.fromJson(json);
  }

  Future<void> addNoClassDay(String classId, DateTime date, String? reason) async {
    await _api.post('classes/$classId/schedule/no-class-days', {
      'date': ApiEnums.dateToApi(date),
      'reason': reason,
    });
  }

  Future<void> removeNoClassDay(String classId, DateTime date) async {
    await _api.delete(
      'classes/$classId/schedule/no-class-days/${ApiEnums.dateToApi(date)}',
    );
  }

  Future<ClassStanding> fetchStanding(String classId, {required GradingPeriod period}) async {
    final json = await _api.get(
      'classes/$classId/grades?period=${ApiEnums.periodToApi(period)}',
    );
    return ClassStanding.fromJson(json);
  }

  Future<StudentReport> fetchStudentReport(
    String classId,
    String enrollmentId, {
    required GradingPeriod period,
  }) async {
    final json = await _api.get(
      'classes/$classId/grades/$enrollmentId?period=${ApiEnums.periodToApi(period)}',
    );
    return StudentReport.fromJson(json);
  }
}