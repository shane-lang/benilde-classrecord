import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/class_model.dart';
import '../models/student_model.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../utils/class_stats.dart';
import '../widgets/ui_kit.dart';
import 'attendance_screen.dart';
import 'class_schedule_screen.dart';
import 'grades_screen.dart';
import 'grading_categories_screen.dart';
import 'student_detail_screen.dart';

enum _SortMode {
  nameAsc,
  nameDesc,
  numberAsc,
  gradeHigh,
  gradeLow,
  attendanceLow,
}

enum _ViewMode { table, cards }

class ClassDetailScreen extends StatefulWidget {
  final ClassModel classModel;

  const ClassDetailScreen({super.key, required this.classModel});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  static const double _tabletBreakpoint = 760;
  static const double _desktopBreakpoint = 1120;
  static const double _passingGrade = 75;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _loadError;
  String _query = '';
  _SortMode _sort = _SortMode.nameAsc;
  _ViewMode _view = _ViewMode.table;

  late ClassModel _loaded = widget.classModel;

  ClassModel get _classModel => _loaded;
  ClassStats get _stats => ClassStats(_classModel);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final cls = await ClassRepository.instance.fetchClassDetail(widget.classModel.id);
      if (!mounted) return;
      setState(() {
        _loaded = cls;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _messageFor(e);
      });
    }
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Something went wrong. Try again.',
      };

  void _reportFailure(Object error) {
    if (!mounted) return;
    AppToast.show(context, _messageFor(error), type: ToastType.error);
  }

  List<StudentModel> get _visibleStudents {
    final stats = _stats;
    final q = _query.trim().toLowerCase();

    final result = _classModel.students.where((s) {
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.studentNumber.toLowerCase().contains(q);
    }).toList();

    int byName(StudentModel a, StudentModel b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    int byValue(double? a, double? b, {required bool descending}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return descending ? b.compareTo(a) : a.compareTo(b);
    }

    switch (_sort) {
      case _SortMode.nameAsc:
        result.sort(byName);
      case _SortMode.nameDesc:
        result.sort((a, b) => byName(b, a));
      case _SortMode.numberAsc:
        result.sort(
          (a, b) => a.studentNumber.toLowerCase().compareTo(
                b.studentNumber.toLowerCase(),
              ),
        );
      case _SortMode.gradeHigh:
        result.sort(
          (a, b) => byValue(
            stats.finalGrade(a.id),
            stats.finalGrade(b.id),
            descending: true,
          ),
        );
      case _SortMode.gradeLow:
        result.sort(
          (a, b) => byValue(
            stats.finalGrade(a.id),
            stats.finalGrade(b.id),
            descending: false,
          ),
        );
      case _SortMode.attendanceLow:
        result.sort(
          (a, b) => byValue(
            stats.attendancePercent(a.id),
            stats.attendancePercent(b.id),
            descending: false,
          ),
        );
    }

    return [
      ...result.where((s) => s.isActive),
      ...result.where((s) => !s.isActive),
    ];
  }

  Set<String> get _takenNumbers => _classModel.students
      .map((s) => s.studentNumber.trim().toLowerCase())
      .where((n) => n.isNotEmpty)
      .toSet();

  String get _titleLine => _classModel.subjectCode.isNotEmpty
      ? _classModel.subjectCode
      : _classModel.subjectName;

  Future<void> _addStudents() async {
    final added = await showStudentFormDialog(
      context,
      takenNumbers: _takenNumbers,
    );
    if (added == null || added.isEmpty || !mounted) return;

    try {

      final saved = await ClassRepository.instance.enrollStudents(
        _classModel.id,
        [for (final s in added) (studentNumber: s.studentNumber, fullName: s.name)],
      );
      if (!mounted) return;

      setState(() => _classModel.students.addAll(saved));
      AppToast.show(
        context,
        saved.length == 1
            ? '${saved.first.name} added to the class'
            : '${saved.length} students added',
        type: ToastType.success,
      );
    } catch (e) {
      _reportFailure(e);
    }
  }

  Future<void> _editStudent(StudentModel student) async {
    final taken = _takenNumbers
      ..remove(student.studentNumber.trim().toLowerCase());

    final result = await showStudentFormDialog(
      context,
      existing: student,
      takenNumbers: taken,
    );
    if (result == null || result.isEmpty || !mounted) return;

    final index = _classModel.students.indexWhere((s) => s.id == student.id);
    if (index == -1) return;

    final edited = StudentModel(
      id: student.id,
      name: result.first.name,
      studentNumber: result.first.studentNumber,
      isActive: student.isActive,
    );

    try {
      await ClassRepository.instance.updateStudent(_classModel.id, edited);
      if (!mounted) return;
      setState(() => _classModel.students[index] = edited);
      AppToast.show(context, 'Student details updated', type: ToastType.success);
    } catch (e) {
      _reportFailure(e);
    }
  }

  Future<void> _removeStudent(StudentModel student) async {
    final choice = await showDialog<_RemoveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(student.isActive ? 'Remove ${student.name}?' : '${student.name} is dropped'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            student.isActive
                ? 'Mark as dropped if the student stopped attending or transferred. '
                    'Their scores and attendance are kept but no longer counted, '
                    'and you can restore them later.\n\n'
                    'Delete permanently only if they were added by mistake. '
                    'This erases their scores and attendance in this class.'
                : 'Restore the student to count their scores and attendance again, '
                    'or delete them permanently to erase their records in this class.',
            style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_RemoveChoice.delete),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete permanently'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(
                student.isActive ? _RemoveChoice.drop : _RemoveChoice.restore),
            child: Text(student.isActive ? 'Mark as dropped' : 'Restore to class'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final index = _classModel.students.indexWhere((s) => s.id == student.id);
    if (index == -1) return;

    if (choice == _RemoveChoice.delete) {

      final sure = await showConfirmDialog(
        context,
        title: 'Delete ${student.name} permanently?',
        message: 'Their scores and attendance in this class will be erased. '
            'This cannot be undone. Their records in your other classes are not affected.',
        confirmLabel: 'Delete permanently',
        destructive: true,
        icon: Icons.delete_forever_outlined,
      );
      if (!sure || !mounted) return;
      try {
        await ClassRepository.instance.removeStudent(_classModel.id, student.id);
        if (!mounted) return;
        setState(() => _classModel.students.removeAt(index));
        AppToast.show(context, '${student.name} deleted', type: ToastType.info);
      } catch (e) {
        _reportFailure(e);
      }
      return;
    }

    final updated = StudentModel(
      id: student.id,
      name: student.name,
      studentNumber: student.studentNumber,
      firstName: student.firstName,
      lastName: student.lastName,
      isActive: choice == _RemoveChoice.restore,
    );
    try {
      await ClassRepository.instance.updateStudent(_classModel.id, updated);
      if (!mounted) return;
      setState(() => _classModel.students[index] = updated);
      AppToast.show(
        context,
        choice == _RemoveChoice.restore
            ? '${student.name} is back in the class'
            : '${student.name} marked as dropped. Their records are kept.',
        type: ToastType.success,
      );
    } catch (e) {
      _reportFailure(e);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => screen))
        .then((_) {

      if (mounted) _load();
    });
  }

  void _openAttendance() => _open(AttendanceScreen(classModel: _classModel));

  void _openGrades() => _open(GradesScreen(classModel: _classModel));

  void _openCategories() =>
      _open(GradingCategoriesScreen(classModel: _classModel));

  void _openSchedule() => _open(ClassScheduleScreen(classModel: _classModel));

  void _openStudent(StudentModel student) => _open(
        StudentDetailScreen(classModel: _classModel, student: student),
      );

  bool _requireStudents(String feature) {
    if (_classModel.students.isNotEmpty) return true;
    AppToast.show(
      context,
      'Add at least one student before opening $feature.',
      type: ToastType.info,
      actionLabel: 'Add',
      onAction: _addStudents,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= _desktopBreakpoint;
    final isTablet = width >= _tabletBreakpoint;
    final hPad = isDesktop ? 32.0 : (isTablet ? 24.0 : 16.0);

    final students = _visibleStudents;
    final hasStudents = _classModel.students.isNotEmpty;
    final searching = _query.trim().isNotEmpty;
    final useTable = isTablet && _view == _ViewMode.table;

    return Scaffold(
      appBar: _appBar(isTablet),
      floatingActionButton: (!isTablet && hasStudents && !_loading)
          ? FloatingActionButton.extended(
              onPressed: _addStudents,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              label: const Text('Add student'),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _breadcrumb(),
                    if (_loadError != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBanner(message: _loadError!, onRetry: _load),
                    ],
                    const SizedBox(height: 14),
                    _Hero(
                      classModel: _classModel,
                      compact: !isTablet,
                      onAttendance: () {
                        if (_requireStudents('attendance')) _openAttendance();
                      },
                      onGrades: () {
                        if (_requireStudents('the gradebook')) _openGrades();
                      },
                    ),
                    const SizedBox(height: 18),
                    _statGrid(),
                    if (_classModel.schedule == null && !_loading) ...[
                      const SizedBox(height: 16),
                      _SetupBanner(onSetSchedule: _openSchedule),
                    ],
                    const SizedBox(height: 22),
                    _ToolRail(
                      onAttendance: () {
                        if (_requireStudents('attendance')) _openAttendance();
                      },
                      onGrades: () {
                        if (_requireStudents('the gradebook')) _openGrades();
                      },
                      onCategories: _openCategories,
                      onSchedule: _openSchedule,
                      scheduleConfigured: _classModel.schedule != null,
                      assessmentCount: _stats.assessmentCount,
                      sessionCount: _stats.sessionsRecorded,
                    ),
                    const SizedBox(height: 28),
                    _rosterHeader(isTablet, students.length),
                    if (hasStudents || searching) ...[
                      const SizedBox(height: 14),
                      _toolbar(isTablet),
                    ],
                    const SizedBox(height: 14),
                    if (useTable && !_loading && students.isNotEmpty)
                      const _TableHeader(),
                  ]),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 96),
                sliver: _rosterSliver(
                  students: students,
                  hasStudents: hasStudents,
                  useTable: useTable,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool isTablet) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back to classes',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _titleLine,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
          Text(
            _classModel.subjectCode.isNotEmpty
                ? _classModel.subjectName
                : '${_classModel.course} • ${_classModel.yearSection}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
      actions: [
        if (isTablet) ...[
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Attendance',
            onPressed: () {
              if (_requireStudents('attendance')) _openAttendance();
            },
          ),
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Gradebook',
            onPressed: () {
              if (_requireStudents('the gradebook')) _openGrades();
            },
          ),
        ],
        PopupMenuButton<String>(
          tooltip: 'More options',
          icon: const Icon(Icons.more_vert_rounded),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.border),
          ),
          onSelected: (value) {
            switch (value) {
              case 'attendance':
                if (_requireStudents('attendance')) _openAttendance();
              case 'grades':
                if (_requireStudents('the gradebook')) _openGrades();
              case 'categories':
                _openCategories();
              case 'schedule':
                _openSchedule();
            }
          },

          itemBuilder: (context) => [
            if (!isTablet) ...[
              const PopupMenuItem<String>(
                value: 'attendance',
                child: _MenuRow(
                  icon: Icons.checklist_rounded,
                  label: 'Attendance',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'grades',
                child: _MenuRow(
                  icon: Icons.assignment_outlined,
                  label: 'Gradebook',
                ),
              ),
            ],
            const PopupMenuItem<String>(
              value: 'categories',
              child: _MenuRow(
                icon: Icons.tune_rounded,
                label: 'Grading categories',
              ),
            ),
            const PopupMenuItem<String>(
              value: 'schedule',
              child: _MenuRow(
                icon: Icons.calendar_month_outlined,
                label: 'Class schedule',
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _breadcrumb() {
    return Row(
      children: [
        Hoverable(
          builder: (context, hovered) => GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Text(
              'Classes',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hovered ? AppColors.primary : AppColors.textMuted,
                decoration:
                    hovered ? TextDecoration.underline : TextDecoration.none,
                decorationColor: AppColors.primary,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
        ),
        Flexible(
          child: Text(
            _titleLine,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statGrid() {
    final stats = _stats;
    final attendance = stats.classAttendanceRate;
    final atRisk = stats.atRiskCount(passingGrade: _passingGrade);

    final items = <_StatData>[
      _StatData(
        icon: Icons.groups_2_outlined,
        label: 'Students',
        value: '${_classModel.activeStudents.length}',
        caption: _classModel.students.isEmpty
            ? 'Roster is empty'
            : (_classModel.students.length > _classModel.activeStudents.length
                ? '${_classModel.students.length - _classModel.activeStudents.length} dropped, not counted'
                : 'Enrolled in this class'),
        color: AppColors.primary,
        background: AppColors.primaryLight,
      ),
      _StatData(
        icon: Icons.event_available_outlined,
        label: 'Attendance',
        value: attendance == null ? '—' : '${attendance.toStringAsFixed(0)}%',
        caption: attendance == null
            ? 'No sessions recorded yet'
            : '${stats.sessionsRecorded} session(s) recorded',
        color: AppColors.success,
        background: AppColors.successBg,
      ),
      _StatData(
        icon: Icons.flag_outlined,
        label: 'Needs attention',
        value: '$atRisk',
        caption: atRisk == 0
            ? 'No one below ${_passingGrade.toStringAsFixed(0)}'
            : 'Below ${_passingGrade.toStringAsFixed(0)} overall',
        color: atRisk == 0 ? AppColors.textSecondary : AppColors.danger,
        background: atRisk == 0 ? AppColors.background : AppColors.dangerBg,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {

        final columns = constraints.maxWidth >= 720 ? items.length : 1;
        const gap = 14.0;
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: itemWidth,
                child: _loading
                    ? const _StatSkeleton()
                    : _StatCard(data: items[i])
                        .animate()
                        .fadeIn(delay: (60 * i).ms, duration: 320.ms)
                        .slideY(begin: 0.10, end: 0, curve: AppMotion.curve),
              ),
          ],
        );
      },
    );
  }

  Widget _rosterHeader(bool isTablet, int visibleCount) {
    final total = _classModel.students.length;
    final filtered = _query.trim().isNotEmpty && visibleCount != total;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Students',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      filtered ? '$visibleCount of $total' : '$total',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a student to see their grade breakdown and attendance '
                'history.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (isTablet && _classModel.students.isNotEmpty) ...[
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _addStudents,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
            label: const Text('Add student'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
          ),
        ],
      ],
    );
  }

  Widget _toolbar(bool isTablet) {
    final search = _SearchField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      onClear: () {
        _searchController.clear();
        setState(() => _query = '');
      },
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortButton(
          value: _sort,
          onChanged: (mode) => setState(() => _sort = mode),
        ),
        if (isTablet) ...[
          const SizedBox(width: 10),
          _ViewToggle(
            value: _view,
            onChanged: (mode) => setState(() => _view = mode),
          ),
        ],
      ],
    );

    if (!isTablet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: controls),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 320, child: search),
        const Spacer(),
        controls,
      ],
    );
  }

  Widget _rosterSliver({
    required List<StudentModel> students,
    required bool hasStudents,
    required bool useTable,
  }) {
    if (_loading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RowSkeleton(table: useTable),
          ),
          childCount: 5,
        ),
      );
    }

    if (!hasStudents) {
      return SliverToBoxAdapter(child: _EmptyRoster(onAdd: _addStudents));
    }

    if (students.isEmpty) {
      return SliverToBoxAdapter(
        child: _NoResults(
          query: _query,
          onClear: () {
            _searchController.clear();
            setState(() => _query = '');
          },
        ),
      );
    }

    final stats = _stats;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final student = students[index];
          final Widget row = useTable
              ? _StudentTableRow(
                  student: student,
                  grade: stats.finalGrade(student.id),
                  attendance: stats.attendancePercent(student.id),
                  passingGrade: _passingGrade,
                  onTap: () => _openStudent(student),
                  onEdit: () => _editStudent(student),
                  onRemove: () => _removeStudent(student),
                )
              : _StudentCard(
                  student: student,
                  grade: stats.finalGrade(student.id),
                  attendance: stats.attendancePercent(student.id),
                  passingGrade: _passingGrade,
                  onTap: () => _openStudent(student),
                  onEdit: () => _editStudent(student),
                  onRemove: () => _removeStudent(student),
                );

          return Padding(
            padding: EdgeInsets.only(bottom: useTable ? 8 : 10),
            child: row
                .animate()
                .fadeIn(
                  delay: (20 * (index > 10 ? 10 : index)).ms,
                  duration: 260.ms,
                )
                .slideY(begin: 0.06, end: 0, curve: AppMotion.curve),
          );
        },
        childCount: students.length,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 20, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final ClassModel classModel;
  final bool compact;
  final VoidCallback onAttendance;
  final VoidCallback onGrades;

  const _Hero({
    required this.classModel,
    required this.compact,
    required this.onAttendance,
    required this.onGrades,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = AccentPalette.gradientFor(
      classModel.subjectCode.isNotEmpty
          ? classModel.subjectCode
          : classModel.subjectName,
    );
    final initials = AccentPalette.initialsFor(
      classModel.subjectCode,
      classModel.subjectName,
    );
    final schedule = classModel.schedule;

    final primaryAction = _HeroButton(
      icon: Icons.checklist_rounded,
      label: 'Take attendance',
      onPressed: onAttendance,
      filled: true,
    );
    final secondaryAction = _HeroButton(
      icon: Icons.assignment_outlined,
      label: 'Open gradebook',
      onPressed: onGrades,
      filled: false,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: DotGridPainter(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 20 : 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 48 : 58,
                      height: compact ? 48 : 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 18 : 21,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classModel.subjectName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 22 : 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (classModel.subjectCode.isNotEmpty)
                                _HeroChip(
                                  icon: Icons.tag_rounded,
                                  label: classModel.subjectCode,
                                ),
                              _HeroChip(
                                icon: Icons.school_outlined,
                                label: '${classModel.course} • '
                                    '${classModel.yearSection}',
                              ),
                              _HeroChip(
                                icon: Icons.schedule_rounded,
                                label: schedule == null
                                    ? 'No schedule set'
                                    : schedule.scheduleLabel,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 20 : 24),
                if (compact)
                  Column(
                    children: [
                      SizedBox(width: double.infinity, child: primaryAction),
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: secondaryAction),
                    ],
                  )
                else
                  Row(
                    children: [
                      primaryAction,
                      const SizedBox(width: 12),
                      secondaryAction,
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 380.ms)
        .slideY(begin: 0.04, end: 0, curve: AppMotion.curve);
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) {
        final bg = filled
            ? (hovered ? Colors.white : Colors.white.withValues(alpha: 0.94))
            : Colors.white.withValues(alpha: hovered ? 0.20 : 0.12);

        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: filled
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.3,
                      ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: filled ? AppColors.brandBlack : Colors.white,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: TextStyle(
                      color: filled ? AppColors.brandBlack : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatData {
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;
  final Color background;

  const _StatData({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.background,
  });
}

class _StatCard extends StatelessWidget {
  final _StatData data;

  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      enableCursor: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color:
                hovered ? data.color.withValues(alpha: 0.35) : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: data.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(data.icon, size: 19, color: data.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              data.value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              data.caption,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 38, height: 38, radius: AppRadius.sm),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 12)),
            ],
          ),
          SizedBox(height: 18),
          SkeletonBox(width: 70, height: 26),
          SizedBox(height: 10),
          SkeletonBox(width: 110, height: 10),
        ],
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  final VoidCallback onSetSchedule;

  const _SetupBanner({required this.onSetSchedule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set the class schedule',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Meeting days and grading period dates let the app generate '
                  'your attendance sheet automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onSetSchedule,
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('Set up'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _ToolRail extends StatelessWidget {
  final VoidCallback onAttendance;
  final VoidCallback onGrades;
  final VoidCallback onCategories;
  final VoidCallback onSchedule;
  final bool scheduleConfigured;
  final int assessmentCount;
  final int sessionCount;

  const _ToolRail({
    required this.onAttendance,
    required this.onGrades,
    required this.onCategories,
    required this.onSchedule,
    required this.scheduleConfigured,
    required this.assessmentCount,
    required this.sessionCount,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ToolTile(
        icon: Icons.checklist_rounded,
        title: 'Attendance',
        caption: sessionCount == 0 ? 'Not started' : '$sessionCount session(s)',
        color: AppColors.primary,
        background: AppColors.primaryLight,
        onTap: onAttendance,
      ),
      _ToolTile(
        icon: Icons.assignment_outlined,
        title: 'Gradebook',
        caption: assessmentCount == 0
            ? 'No assessments yet'
            : '$assessmentCount assessment(s)',
        color: AppColors.info,
        background: AppColors.infoBg,
        onTap: onGrades,
      ),
      _ToolTile(
        icon: Icons.tune_rounded,
        title: 'Categories',
        caption: 'Weights & breakdown',
        color: AppColors.gold,
        background: AppColors.goldLight,
        onTap: onCategories,
      ),
      _ToolTile(
        icon: Icons.calendar_month_outlined,
        title: 'Schedule',
        caption: scheduleConfigured ? 'Configured' : 'Needs setup',
        color: scheduleConfigured ? AppColors.success : AppColors.danger,
        background:
            scheduleConfigured ? AppColors.successBg : AppColors.dangerBg,
        onTap: onSchedule,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860 ? 4 : 2;
        const gap = 12.0;
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: itemWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hovered ? color.withValues(alpha: 0.4) : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSlide(
                    duration: AppMotion.fast,
                    offset: hovered ? const Offset(0.15, 0) : Offset.zero,
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search name or student no.',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: AppColors.textMuted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Clear search',
                onPressed: onClear,
              ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final _SortMode value;
  final ValueChanged<_SortMode> onChanged;

  const _SortButton({required this.value, required this.onChanged});

  static String _labelFor(_SortMode mode) {
    switch (mode) {
      case _SortMode.nameAsc:
        return 'Name A–Z';
      case _SortMode.nameDesc:
        return 'Name Z–A';
      case _SortMode.numberAsc:
        return 'Student no.';
      case _SortMode.gradeHigh:
        return 'Highest grade';
      case _SortMode.gradeLow:
        return 'Lowest grade';
      case _SortMode.attendanceLow:
        return 'Lowest attendance';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortMode>(
      tooltip: 'Sort students',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (context) => [
        for (final mode in _SortMode.values)
          PopupMenuItem<_SortMode>(
            value: mode,
            child: Row(
              children: [
                Icon(
                  mode == value
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: mode == value ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  _labelFor(mode),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        mode == value ? FontWeight.w600 : FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Hoverable(
        builder: (context, hovered) => AnimatedContainer(
          duration: AppMotion.fast,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: hovered ? AppColors.primary : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                _labelFor(value),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final _ViewMode value;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget button(_ViewMode mode, IconData icon, String tooltip) {
      final selected = value == mode;
      return Tooltip(
        message: tooltip,
        child: Hoverable(
          builder: (context, hovered) => GestureDetector(
            onTap: () => onChanged(mode),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: 42,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.surface
                    : (hovered
                        ? AppColors.surface.withValues(alpha: 0.6)
                        : null),
                borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                boxShadow: selected ? AppShadows.card : null,
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(_ViewMode.table, Icons.table_rows_rounded, 'Table view'),
          button(_ViewMode.cards, Icons.grid_view_rounded, 'Card view'),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
      letterSpacing: 0.6,
    );

    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('STUDENT', style: style)),
          Expanded(flex: 3, child: Text('STUDENT NO.', style: style)),
          Expanded(flex: 3, child: Text('ATTENDANCE', style: style)),
          Expanded(flex: 3, child: Text('OVERALL', style: style)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _StudentTableRow extends StatelessWidget {
  final StudentModel student;
  final double? grade;
  final double? attendance;
  final double passingGrade;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _StudentTableRow({
    required this.student,
    required this.grade,
    required this.attendance,
    required this.passingGrade,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final noNumber = student.studentNumber.trim().isEmpty;

    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hovered
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        _Avatar(name: student.name),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            student.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: student.isActive ? AppColors.textPrimary : AppColors.textMuted,
                            ),
                          ),
                        ),
                        if (!student.isActive) ...[
                          const SizedBox(width: 8),
                          const _DroppedBadge(),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      noNumber ? 'Not set' : student.studentNumber,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: noNumber
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        fontStyle:
                            noNumber ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MetricPill(
                        value: attendance,
                        suffix: '%',
                        threshold: 75,
                        icon: Icons.event_available_outlined,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MetricPill(
                        value: grade,
                        suffix: '',
                        threshold: passingGrade,
                        icon: Icons.insights_outlined,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: _RowMenu(onEdit: onEdit, onRemove: onRemove, dropped: !student.isActive),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final StudentModel student;
  final double? grade;
  final double? attendance;
  final double passingGrade;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _StudentCard({
    required this.student,
    required this.grade,
    required this.attendance,
    required this.passingGrade,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hovered
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
            width: 1.2,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Avatar(name: student.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: student.isActive ? AppColors.textPrimary : AppColors.textMuted,
                              ),
                            ),
                            if (!student.isActive) ...[
                              const SizedBox(height: 4),
                              const _DroppedBadge(),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              student.studentNumber.trim().isEmpty
                                  ? 'No student number'
                                  : student.studentNumber,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RowMenu(onEdit: onEdit, onRemove: onRemove, dropped: !student.isActive),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricPill(
                        value: attendance,
                        suffix: '%',
                        threshold: 75,
                        icon: Icons.event_available_outlined,
                      ),
                      const SizedBox(width: 8),
                      _MetricPill(
                        value: grade,
                        suffix: '',
                        threshold: passingGrade,
                        icon: Icons.insights_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = AccentPalette.gradientFor(name);
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      initials = parts.first.substring(0, 1).toUpperCase();
    } else {
      initials = (parts.first.substring(0, 1) + parts.last.substring(0, 1))
          .toUpperCase();
    }

    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final double? value;
  final String suffix;
  final double threshold;
  final IconData icon;

  const _MetricPill({
    required this.value,
    required this.suffix,
    required this.threshold,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;

    if (v == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          '—',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      );
    }

    final Color color;
    final Color background;
    if (v >= threshold + 15) {
      color = AppColors.success;
      background = AppColors.successBg;
    } else if (v >= threshold) {
      color = AppColors.warning;
      background = AppColors.warningBg;
    } else {
      color = AppColors.danger;
      background = AppColors.dangerBg;
    }

    return StatusBadge(
      label: '${v.toStringAsFixed(suffix == '%' ? 0 : 1)}$suffix',
      color: color,
      background: background,
      icon: icon,
    );
  }
}

enum _RemoveChoice { drop, restore, delete }

class _DroppedBadge extends StatelessWidget {
  const _DroppedBadge();

  @override
  Widget build(BuildContext context) {
    return const StatusBadge(
      label: 'Dropped',
      color: AppColors.textMuted,
      background: AppColors.background,
    );
  }
}

class _RowMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  final bool dropped;

  const _RowMenu({required this.onEdit, required this.onRemove, this.dropped = false});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Student options',
      position: PopupMenuPosition.under,
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 20,
        color: AppColors.textMuted,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'remove') onRemove();
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'edit',
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit details'),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: _MenuRow(
            icon: dropped ? Icons.settings_backup_restore_rounded : Icons.person_remove_outlined,
            label: dropped ? 'Restore or delete' : 'Drop or remove',
            destructive: !dropped,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, color: color)),
      ],
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  final bool table;

  const _RowSkeleton({required this.table});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 38, height: 38, radius: 999),
          const SizedBox(width: 12),
          const Expanded(child: SkeletonBox(height: 12)),
          if (table) ...[
            const SizedBox(width: 24),
            const SkeletonBox(width: 80, height: 12),
            const SizedBox(width: 24),
            const SkeletonBox(width: 62, height: 24, radius: 999),
          ],
          const SizedBox(width: 24),
          const SkeletonBox(width: 62, height: 24, radius: 999),
        ],
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyRoster({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primaryLight,
                  AppColors.primaryLight.withValues(alpha: 0.35),
                ],
              ),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              size: 38,
              color: AppColors.primary,
            ),
          )
              .animate()
              .fadeIn(duration: 380.ms)
              .scale(begin: const Offset(0.82, 0.82), curve: AppMotion.curve),
          const SizedBox(height: 22),
          Text(
            'Build your class list',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              'Add students one by one, or paste your whole roster from Excel '
              'in one go. Attendance and grades unlock right after.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 260,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              label: const Text('Add students'),
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _HintChip(
                icon: Icons.content_paste_rounded,
                label: 'Paste a list from Excel',
              ),
              _HintChip(
                icon: Icons.checklist_rounded,
                label: 'Then take attendance',
              ),
              _HintChip(icon: Icons.grade_rounded, label: 'Then record scores'),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 26,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No students match "$query"',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Check the spelling, or try searching by student number.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Clear search'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms);
  }
}

class _HintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

Future<List<StudentModel>?> showStudentFormDialog(
  BuildContext context, {
  StudentModel? existing,
  required Set<String> takenNumbers,
}) {
  return showGeneralDialog<List<StudentModel>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: AppColors.brandBlack.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _StudentFormDialog(
            existing: existing,
            takenNumbers: takenNumbers,
          ),
        ),
      ),
    ),
  );
}

class _StudentFormDialog extends StatefulWidget {
  final StudentModel? existing;
  final Set<String> takenNumbers;

  const _StudentFormDialog({
    required this.existing,
    required this.takenNumbers,
  });

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _bulkController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  final List<StudentModel> _staged = [];
  bool _bulkMode = false;
  List<StudentModel> _parsed = [];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _numberController.text = existing.studentNumber;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _bulkController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _newId(int salt) => '${DateTime.now().microsecondsSinceEpoch}_$salt';

  bool _isTaken(String number) {
    final key = number.trim().toLowerCase();
    if (key.isEmpty) return false;
    if (widget.takenNumbers.contains(key)) return true;
    return _staged.any((s) => s.studentNumber.trim().toLowerCase() == key);
  }

  String? _validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Full name is required.';
    if (v.length < 2) return 'That name looks too short.';
    return null;
  }

  String? _validateNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Student number is required.';
    if (_isTaken(v)) return 'This student number is already in the class.';
    return null;
  }

  List<StudentModel> _parseBulk(String raw) {
    final result = <StudentModel>[];
    final seen = <String>{};
    final lines = raw.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line
          .split(RegExp(r'\s*[,;\t|]\s*|\s+-\s+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (parts.isEmpty) continue;

      String name;
      String number;

      if (parts.length >= 2) {
        final first = parts.first;
        final firstHasDigits = RegExp(r'\d').hasMatch(first);
        final secondHasDigits = RegExp(r'\d').hasMatch(parts[1]);

        if (firstHasDigits && !secondHasDigits) {
          number = first;
          name = parts.sublist(1).join(' ');
        } else {
          name = first;
          number = parts[1];
        }
      } else {
        name = parts.first;
        number = '';
      }

      final key = number.isEmpty ? name.toLowerCase() : number.toLowerCase();
      if (seen.contains(key)) continue;
      if (number.isNotEmpty && _isTaken(number)) continue;
      seen.add(key);

      result.add(
        StudentModel(id: _newId(i), name: name, studentNumber: number),
      );
    }
    return result;
  }

  void _stageCurrent() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _staged.add(
        StudentModel(
          id: _newId(_staged.length),
          name: _nameController.text.trim(),
          studentNumber: _numberController.text.trim(),
        ),
      );
      _nameController.clear();
      _numberController.clear();
    });
    _formKey.currentState?.reset();
    _nameFocus.requestFocus();
  }

  void _submit() {
    if (_bulkMode) {
      if (_parsed.isEmpty) return;
      Navigator.of(context).pop(_parsed);
      return;
    }

    if (_isEditing) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      Navigator.of(context).pop([
        StudentModel(
          id: widget.existing!.id,
          name: _nameController.text.trim(),
          studentNumber: _numberController.text.trim(),
        ),
      ]);
      return;
    }

    final hasInput = _nameController.text.trim().isNotEmpty ||
        _numberController.text.trim().isNotEmpty;

    if (hasInput) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      final all = <StudentModel>[
        ..._staged,
        StudentModel(
          id: _newId(_staged.length),
          name: _nameController.text.trim(),
          studentNumber: _numberController.text.trim(),
        ),
      ];
      Navigator.of(context).pop(all);
      return;
    }

    if (_staged.isEmpty) {
      _formKey.currentState?.validate();
      return;
    }
    Navigator.of(context).pop(List<StudentModel>.from(_staged));
  }

  int get _pendingCount {
    final hasInput = _nameController.text.trim().isNotEmpty &&
        _numberController.text.trim().isNotEmpty;
    return _staged.length + (hasInput ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final String primaryLabel;
    if (_isEditing) {
      primaryLabel = 'Save changes';
    } else if (_bulkMode) {
      primaryLabel = _parsed.isEmpty
          ? 'Add students'
          : 'Add ${_parsed.length} students';
    } else {
      primaryLabel =
          _pendingCount > 1 ? 'Add $_pendingCount students' : 'Add student';
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    _isEditing
                        ? Icons.edit_outlined
                        : Icons.person_add_alt_1_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit student' : 'Add students',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isEditing
                            ? 'Update the name or student number.'
                            : 'Type them in, or paste a list you already have.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (!_isEditing) ...[
              _ModeSwitch(
                bulkMode: _bulkMode,
                onChanged: (bulk) => setState(() => _bulkMode = bulk),
              ),
              const SizedBox(height: 20),
            ],

            if (_bulkMode && !_isEditing)
              _bulkBody(context)
            else
              _singleBody(context),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),

            Row(
              children: [
                if (!_isEditing && !_bulkMode)
                  TextButton.icon(
                    onPressed: _stageCurrent,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add another'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_bulkMode && _parsed.isEmpty) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _singleBody(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            focusNode: _nameFocus,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: _validateName,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Full name',
              hintText: 'Juan Dela Cruz',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _numberController,
            textInputAction: TextInputAction.done,
            validator: _validateNumber,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Student number',
              hintText: '2023-00123',
              prefixIcon: Icon(Icons.tag_rounded, size: 20),
            ),
          ),
          if (_staged.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_staged.length} ready to add',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in List<StudentModel>.from(_staged))
                  Chip(
                    label: Text(s.name),
                    backgroundColor: AppColors.successBg,
                    side: BorderSide(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 15),
                    onDeleted: () => setState(() => _staged.remove(s)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bulkBody(BuildContext context) {
    final missingNumbers = _parsed.where((s) => s.studentNumber.isEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _bulkController,
          maxLines: 7,
          autofocus: true,
          onChanged: (value) => setState(() => _parsed = _parseBulk(value)),
          decoration: const InputDecoration(
            hintText: '2023-00123, Juan Dela Cruz\n'
                '2023-00124, Maria Santos\n'
                '2023-00125, Jose Rizal',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'One student per line. Separate the number and name with a comma, '
          'tab, or dash — pasting straight from Excel works.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_parsed.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_parsed.length} student(s) detected',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (missingNumbers > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$missingNumbers without a student number — you can fill '
                    'those in later.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in _parsed.take(6))
                      _PreviewChip(label: s.name),
                    if (_parsed.length > 6)
                      _PreviewChip(
                        label: '+${_parsed.length - 6} more',
                        emphasized: true,
                      ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 200.ms),
        ],
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final String label;
  final bool emphasized;

  const _PreviewChip({required this.label, this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
          color: emphasized ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final bool bulkMode;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({required this.bulkMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: Hoverable(
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                boxShadow: selected ? AppShadows.card : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          tab(
            'One by one',
            Icons.person_outline_rounded,
            !bulkMode,
            () => onChanged(false),
          ),
          tab(
            'Paste a list',
            Icons.content_paste_rounded,
            bulkMode,
            () => onChanged(true),
          ),
        ],
      ),
    );
  }
}