import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/assessment_model.dart';
import '../models/class_model.dart';
import '../models/audit_entry.dart';
import '../models/class_standing.dart';
import '../models/grading_category_model.dart';
import '../models/student_report.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import '../services/class_repository.dart';
import '../services/sheet_printer.dart';
import '../utils/grade_sheet_html.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'attendance_screen.dart';
import 'category_grade_sheet_screen.dart';
import 'grading_categories_screen.dart';
import 'student_detail_screen.dart';

const double _tabletBreakpoint = 760;
const double _desktopBreakpoint = 1120;
const double _passing = 75;

String _periodLabel(GradingPeriod p) {
  switch (p) {
    case GradingPeriod.prelim:
      return 'Prelim';
    case GradingPeriod.midterm:
      return 'Midterm';
    case GradingPeriod.finals:
      return 'Finals';
  }
}

Color _gradeColor(double? v) =>
    v == null ? AppColors.textMuted : (v >= _passing ? AppColors.success : AppColors.danger);

String _pct(double? v, {int digits = 1}) => v == null ? '—' : '${v.toStringAsFixed(digits)}%';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

IconData _iconForCategory(GradingCategoryModel category) {
  final n = category.name.toLowerCase();
  if (category.isAttendance) return Icons.event_available_rounded;
  if (n.contains('quiz')) return Icons.quiz_outlined;
  if (n.contains('exam')) return Icons.fact_check_outlined;
  if (n.contains('project')) return Icons.folder_special_outlined;
  if (n.contains('performance') || n.contains('task')) return Icons.task_alt_rounded;
  if (n.contains('activit') || n.contains('seatwork')) return Icons.edit_note_rounded;
  if (n.contains('recit')) return Icons.record_voice_over_outlined;
  if (n.contains('assign')) return Icons.assignment_outlined;
  return Icons.grid_view_rounded;
}

enum _SortMode { name, highest, lowest }

class GradesScreen extends StatefulWidget {
  final ClassModel classModel;

  const GradesScreen({super.key, required this.classModel});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  GradingPeriod _period = GradingPeriod.prelim;
  bool _loading = true;
  String? _loadError;

  ClassStanding _standing = ClassStanding.empty;
  String _query = '';
  _SortMode _sort = _SortMode.name;
  final TextEditingController _searchCtrl = TextEditingController();

  String? _selectedId;
  String _selectedName = '';
  StudentReport? _selectedReport;
  bool _selectedLoading = false;

  ClassModel get _class => widget.classModel;

  Future<void> _selectStudent(String enrollmentId, String name) async {
    if (_selectedId == enrollmentId) {
      _clearSelection();
      return;
    }
    setState(() {
      _selectedId = enrollmentId;
      _selectedName = name;
      _selectedReport = null;
      _selectedLoading = true;
    });
    await _loadSelectedReport();
  }

  Future<void> _loadSelectedReport() async {
    final id = _selectedId;
    if (id == null) return;
    try {
      final report = await ClassRepository.instance
          .fetchStudentReport(_class.id, id, period: _period);
      if (!mounted || _selectedId != id) return;
      setState(() {
        _selectedReport = report;
        _selectedLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedId != id) return;
      setState(() => _selectedLoading = false);
      final msg = switch (e) {
        ApiException err => err.message,
        NetworkException err => err.message,
        _ => 'Couldn’t load this student’s grades.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedId = null;
      _selectedName = '';
      _selectedReport = null;
      _selectedLoading = false;
    });
  }

  double? _studentCategoryPercent(String categoryId) {
    CategoryResult? find(List<CategoryResult> list) {
      for (final c in list) {
        if (c.categoryId == categoryId) return c;
        final inner = find(c.children);
        if (inner != null) return inner;
      }
      return null;
    }

    final report = _selectedReport;
    if (report == null) return null;
    return find(report.categories)?.percent;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final standing = await ClassRepository.instance
          .fetchStanding(_class.id, period: _period);
      if (!mounted) return;
      setState(() {
        _standing = standing;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t load grades. Try again.',
        };
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<GradingCategoryModel> _childrenOf(String parentId) =>
      _class.gradingCategories.where((c) => c.parentId == parentId).toList();

  List<GradingCategoryModel> get _sheetCategories => _class.gradingCategories
      .where((c) => !c.isAttendance && _childrenOf(c.id).isEmpty)
      .toList();

  GradingCategoryModel? get _attendanceCategory {
    for (final c in _class.gradingCategories) {
      if (c.isAttendance) return c;
    }
    return null;
  }

  double? _classCategoryAverage(GradingCategoryModel c) =>
      _standing.averageFor(c.id);

  int _itemCountFor(GradingCategoryModel c) => _standing.itemCountFor(c.id);

  List<AssessmentModel> _itemsOf(GradingCategoryModel c) => _class.assessments
      .where((a) => a.gradingPeriod == _period && a.categoryId == c.id)
      .toList();

  List<_MissingRow> _missingScores(GradingCategoryModel c) {
    final items = _itemsOf(c);
    if (items.isEmpty) return const [];

    final scored = <String>{
      for (final s in _class.scores) '${s.studentId}|${s.assessmentId}',
    };

    final rows = <_MissingRow>[];
    for (final student in _class.activeStudents) {
      final missing = [
        for (final a in items)
          if (!scored.contains('${student.id}|${a.id}')) a.name,
      ];
      if (missing.isNotEmpty) {
        rows.add(_MissingRow(name: student.name, detail: student.studentNumber, missing: missing));
      }
    }
    return rows;
  }

  List<_MissingRow> _missingAttendance() {
    final days = <DateTime>{
      for (final r in _class.attendanceRecords)
        if (r.gradingPeriod == _period) DateTime(r.date.year, r.date.month, r.date.day),
    }.toList()
      ..sort();
    if (days.isEmpty) return const [];

    final marked = <String>{
      for (final r in _class.attendanceRecords)
        if (r.gradingPeriod == _period)
          '${r.studentId}|${r.date.year}-${r.date.month}-${r.date.day}',
    };

    final rows = <_MissingRow>[];
    for (final student in _class.activeStudents) {
      final missing = [
        for (final d in days)
          if (!marked.contains('${student.id}|${d.year}-${d.month}-${d.day}'))
            _shortDate(d),
      ];
      if (missing.isNotEmpty) {
        rows.add(_MissingRow(name: student.name, detail: student.studentNumber, missing: missing));
      }
    }
    return rows;
  }

  Future<void> _showMissing({
    required String title,
    required String noun,
    required List<_MissingRow> rows,
    required VoidCallback onOpenSheet,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => _MissingDialog(title: title, noun: noun, rows: rows),
    );
    if (go == true && mounted) onOpenSheet();
  }

  double get _topLevelWeightTotal => _standing.weightTotal;

  Future<void> _openSheet(GradingCategoryModel c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CategoryGradeSheetScreen(classModel: _class, category: c, period: _period),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openAttendance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AttendanceScreen(classModel: _class)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GradingCategoriesScreen(classModel: _class)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openStudentByEnrollment(String enrollmentId) async {

    final match = _class.students.where((s) => s.id == enrollmentId);
    if (match.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentDetailScreen(classModel: _class, student: match.first),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = width >= _tabletBreakpoint;
    final desktop = width >= _desktopBreakpoint;
    final hPad = desktop ? 32.0 : (tablet ? 24.0 : 16.0);

    Widget body;
    if (_class.students.isEmpty) {
      body = _EmptyState(
        icon: Icons.group_add_outlined,
        title: 'No students in this class yet',
        message: 'Add students from the class page, then come back to record grades.',
        actionLabel: 'Back to class',
        actionIcon: Icons.arrow_back_rounded,
        onAction: () => Navigator.of(context).maybePop(),
      );
    } else if (_sheetCategories.isEmpty && _attendanceCategory == null) {
      body = _EmptyState(
        icon: Icons.dashboard_customize_outlined,
        title: 'No grading categories yet',
        message: 'Create categories like Quizzes or Exams. Each one becomes its own gradebook sheet.',
        actionLabel: 'Set up categories',
        actionIcon: Icons.tune_rounded,
        onAction: _openCategories,
      );
    } else {
      body = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, tablet ? 20 : 14, hPad, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _header(tablet),
                SizedBox(height: tablet ? 18 : 14),
                if (_periodLocked) ...[
                  _LockedBanner(period: _periodLabel(_period)),
                  const SizedBox(height: 14),
                ],
                _loading ? _StatsSkeleton(compact: !tablet) : _stats(tablet),
                if (!_loading && _loadError != null) ...[
                  const SizedBox(height: 14),
                  _GradesErrorBanner(message: _loadError!, onRetry: _load),
                ],
                if (!_loading && (_topLevelWeightTotal - 1).abs() > 0.001) ...[
                  const SizedBox(height: 14),
                  _weightWarning(),
                ],
                const SizedBox(height: 28),
                _sectionTitle(
                  'Grading sheets',
                  'Open a sheet to add items and record scores for ${_periodLabel(_period)}.',
                  trailing: tablet
                      ? TextButton.icon(
                          onPressed: _openCategories,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Manage categories'),
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                _loading ? _SheetGridSkeleton(columns: _columns(width)) : _sheetGrid(width),
                const SizedBox(height: 32),
                KeyedSubtree(
                  key: ValueKey(_period),
                  child: _standingSection(desktop, tablet),
                ),
              ]),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: _appBar(tablet),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: body,
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool tablet) {
    final subtitle = _class.subjectCode.isNotEmpty
        ? '${_class.subjectCode}  ${_class.subjectName}'
        : _class.subjectName;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back to class',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 4,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Gradebook',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.15),
          ),
          Text(
            subtitle,
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

        IconButton(
          icon: const Icon(Icons.print_outlined),
          tooltip: 'Print grade sheet',
          onPressed: _printGradeSheet,
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Export grades to Excel',
          onPressed: _exportGrades,
        ),
        PopupMenuButton<String>(
          tooltip: 'Period options',
          position: PopupMenuPosition.under,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            if (value == 'lock') _togglePeriodLock();
            if (value == 'history') _openHistory();
          },
          itemBuilder: (context) => [

            PopupMenuItem<String>(
              value: 'lock',
              child: Row(
                children: [
                  Icon(
                    _periodLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                    size: 18,
                    color: _periodLocked ? AppColors.warning : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(_periodLocked
                      ? 'Reopen ${_periodLabel(_period)}'
                      : 'Finalize ${_periodLabel(_period)}'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'history',
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Text('Class history'),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.event_available_outlined),
          tooltip: 'Attendance',
          onPressed: _openAttendance,
        ),

        if (!tablet)
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Grading categories',
            onPressed: _openCategories,
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  bool get _periodLocked => _class.lockedFor(_period);

  Future<void> _togglePeriodLock() async {
    final locking = !_periodLocked;
    final label = _periodLabel(_period);

    final ok = await showConfirmDialog(
      context,
      title: locking ? 'Finalize $label?' : 'Reopen $label?',
      message: locking
          ? 'Scores, items and attendance in $label can no longer be changed. '
              'You can reopen it later, and both actions are recorded in the class history.'
          : 'Changes to $label will be allowed again. This is recorded in the class history, '
              'so a correction after submission can always be traced.',
      confirmLabel: locking ? 'Finalize' : 'Reopen',
      icon: locking ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _class.setLock(_period, locking));
    try {
      await ClassRepository.instance.setPeriodLock(_class.id, _period, locking);
      if (!mounted) return;
      AppToast.show(
        context,
        locking ? '$label is finalized' : '$label is open again',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _class.setLock(_period, !locking));
      AppToast.show(
        context,
        switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t change the lock. Try again.',
        },
        type: ToastType.error,
      );
    }
  }

  Future<void> _openHistory() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(classModel: _class),
    );
  }

  String _gradesCsv() {
    String cell(String v) =>
        (v.contains(',') || v.contains('"')) ? '"${v.replaceAll('"', '""')}"' : v;
    String fmt(double? v) => v == null ? '' : v.toStringAsFixed(2);

    final rows = [..._standing.students]
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    final buffer = StringBuffer()
      ..writeln('Student number,Name,Prelim,Midterm,Finals,Final grade,Remark');
    for (final r in rows) {
      buffer.writeln([
        cell(r.studentNumber),
        cell(r.fullName),
        fmt(r.prelim),
        fmt(r.midterm),
        fmt(r.finals),
        fmt(r.finalGrade),
        cell(r.remark),
      ].join(','));
    }
    return buffer.toString();
  }

  Future<void> _printGradeSheet() async {
    if (_loading) return;
    if (_standing.students.isEmpty) {
      AppToast.show(context, 'Nothing to print yet. Add students first.');
      return;
    }

    final html = buildGradeSheetHtml(
      classModel: _class,
      standing: _standing,
      teacherName: AuthService.instance.currentUser?.fullName ?? '',
    );

    final opened = await openPrintableSheet(html);
    if (!mounted) return;

    if (!opened) {

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          icon: const Icon(Icons.print_disabled_outlined,
              color: AppColors.warning, size: 30),
          title: const Text('Couldn\u2019t open the print page'),
          content: const SizedBox(
            width: 380,
            child: Text(
              'Your browser may have blocked the new tab. Allow pop-ups for this '
              'site and try again.\n\nIn the meantime, “Export grades” copies the '
              'same figures for Excel, which prints just as well.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _exportGrades();
              },
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Export instead'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _exportGrades() async {
    if (_loading) return;
    if (_standing.students.isEmpty) {
      AppToast.show(context, 'Nothing to export yet. Add students first.');
      return;
    }
    final csv = _gradesCsv();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;

    final code = _class.subjectCode.isNotEmpty ? _class.subjectCode : _class.subjectName;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: const Icon(Icons.task_alt_rounded, color: AppColors.success, size: 32),
        title: const Text('Grades copied'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$code: ${_standing.students.length} students with Prelim, Midterm, Finals and '
                'final grades. Open Excel or Google Sheets and press Ctrl+V to paste. '
                'Dropped students are not included.',
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    csv,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _header(bool tablet) {
    final tabs = _PeriodTabs(
      selected: _period,
      counts: {
        for (final p in GradingPeriod.values)
          p: _class.assessments.where((a) => a.gradingPeriod == p).length,
      },
      onChanged: (p) {
        setState(() => _period = p);
        _load();
        if (_selectedId != null) {
          setState(() {
            _selectedReport = null;
            _selectedLoading = true;
          });
          _loadSelectedReport();
        }
      },
    );
    if (!tablet) return tabs;

    final code = _class.subjectCode.isNotEmpty ? _class.subjectCode : _class.subjectName;
    return Row(
      children: [
        Flexible(
          child: Hoverable(
            builder: (context, hovered) => GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Text(
                code,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hovered ? AppColors.primary : AppColors.textMuted,
                  decoration: hovered ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
        ),
        const Text(
          'Gradebook',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const Spacer(),
        SizedBox(width: 360, child: tabs),
      ],
    );
  }

  Widget _stats(bool tablet) {
    final grades = _standing.students
        .map((s) => s.gradeFor(GradingPeriod.values.indexOf(_period)))
        .whereType<double>()
        .toList();
    final passing = grades.where((g) => g >= _passing).length;
    final atRisk = grades.length - passing;
    final items = _standing.categoryAverages
        .fold<int>(0, (sum, c) => sum + c.itemCount);
    final tiles = <Widget>[
      _StatTile(
        icon: Icons.verified_outlined,
        color: AppColors.primary,
        background: AppColors.primaryLight,
        label: 'Passing',
        value: grades.isEmpty ? '—' : '$passing/${grades.length}',
        caption: 'At ${_passing.toStringAsFixed(0)}% or higher',
        compact: !tablet,
      ),
      _StatTile(
        icon: atRisk == 0 ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
        color: atRisk == 0 ? AppColors.success : AppColors.danger,
        background: atRisk == 0 ? AppColors.successBg : AppColors.dangerBg,
        label: 'Below ${_passing.toStringAsFixed(0)}%',
        value: grades.isEmpty ? '—' : '$atRisk',
        caption: grades.isEmpty
            ? 'Shows once scores are in'
            : (atRisk == 0 ? 'Everyone is passing' : 'Need attention this period'),
        compact: !tablet,
      ),
      _StatTile(
        icon: Icons.library_books_outlined,
        color: AppColors.goldDark,
        background: AppColors.goldLight,
        label: 'Items this period',
        value: '$items',
        caption: 'Across ${_sheetCategories.length} sheets',
        compact: !tablet,
      ),
    ];

    if (tablet) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(width: 176, child: tiles[i]),
      ),
    );
  }

  Widget _weightWarning() {
    final total = (_topLevelWeightTotal * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.balance_rounded, size: 20, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Category weights add up to $total%, not 100%. Grades are scaled to '
              'the categories that have data, so adjust the weights for accurate results.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _openCategories,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning),
            ),
            child: const Text('Fix weights'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle, {Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  int _columns(double width) => width >= _desktopBreakpoint ? 3 : (width >= 640 ? 2 : 1);

  Widget _sheetGrid(double width) {
    final cards = <Widget>[
      for (final c in _sheetCategories) _sheetCard(c),
      if (_attendanceCategory != null) _attendanceCard(_attendanceCategory!),
    ];
    return _Grid(columns: _columns(width), children: cards)
        .animate(key: ValueKey(_period))
        .fadeIn(duration: 220.ms);
  }

  Widget _sheetCard(GradingCategoryModel c) {
    String? parent;
    if (c.parentId != null) {
      for (final p in _class.gradingCategories) {
        if (p.id == c.parentId) parent = p.name;
      }
    }
    final count = _itemCountFor(c);
    final missing = _missingScores(c);
    return _SheetCard(
      icon: _iconForCategory(c),
      accent: AppColors.primary,
      accentBg: AppColors.primaryLight,
      title: c.name,
      weightLabel: parent != null
          ? '${(c.weight * 100).toStringAsFixed(0)}% of $parent'
          : '${(c.weight * 100).toStringAsFixed(0)}% of grade',
      meta: count == 0 ? 'No items yet' : '$count item${count == 1 ? '' : 's'}',
      average: _classCategoryAverage(c),
      emptyHint: count == 0 ? 'Open to add the first item' : 'No scores recorded yet',
      onTap: () => _openSheet(c),
      missingCount: missing.length,
      onMissingTap: missing.isEmpty
          ? null
          : () => _showMissing(
                title: '${c.name}, ${_periodLabel(_period)}',
                noun: 'item',
                rows: missing,
                onOpenSheet: () => _openSheet(c),
              ),
    );
  }

  Widget _attendanceCard(GradingCategoryModel c) {
    final days = <DateTime>{
      for (final r in _class.attendanceRecords)
        if (r.gradingPeriod == _period) DateTime(r.date.year, r.date.month, r.date.day),
    }.length;
    final missing = _missingAttendance();
    return _SheetCard(
      icon: Icons.event_available_rounded,
      accent: AppColors.goldDark,
      accentBg: AppColors.goldLight,
      title: c.name,
      weightLabel: '${(c.weight * 100).toStringAsFixed(0)}% of grade',
      meta: days == 0 ? 'Synced from Attendance' : '$days class day${days == 1 ? '' : 's'} recorded',
      average: _classCategoryAverage(c),
      emptyHint: 'Take attendance to fill this in',
      onTap: _openAttendance,
      badge: 'Auto',
      missingCount: missing.length,
      onMissingTap: missing.isEmpty
          ? null
          : () => _showMissing(
                title: '${c.name}, ${_periodLabel(_period)}',
                noun: 'day',
                rows: missing,
                onOpenSheet: _openAttendance,
              ),
    );
  }

  String _finalGradeRule() {
    if (!_class.hasPeriodWeights) {
      return 'Grades for every period. Final grade is the mean of the periods with data.';
    }
    String pct(double w) {
      final v = w * 100;
      return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    }

    return 'Grades for every period. Final grade is weighted: '
        'Prelim ${pct(_class.prelimWeight)}%, Midterm ${pct(_class.midtermWeight)}%, '
        'Finals ${pct(_class.finalsWeight)}%.';
  }

  Widget _standingSection(bool desktop, bool tablet) {
    final table = _standingTable(tablet);
    final student = _selectedId != null;
    double? value(GradingCategoryModel c) =>
        student ? _studentCategoryPercent(c.id) : _classCategoryAverage(c);
    final chart = _CategoryAverages(
      period: _periodLabel(_period),
      studentName: student ? _selectedName : null,
      periodGrade: student ? _selectedReport?.periodGrade : null,
      loading: student && _selectedLoading,
      onClear: _clearSelection,
      onOpenReport: student ? () => _openStudentByEnrollment(_selectedId!) : null,
      rows: [
        for (final c in _sheetCategories) (c.name, value(c)),
        if (_attendanceCategory != null)
          (_attendanceCategory!.name, value(_attendanceCategory!)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Class standing',
          _finalGradeRule(),
        ),
        const SizedBox(height: 14),
        if (desktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: table),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: chart),
            ],
          )
        else ...[
          table,
          const SizedBox(height: 16),
          chart,
        ],
      ],
    );
  }

  Widget _standingTable(bool tablet) {
    final q = _query.trim().toLowerCase();
    final rows = _standing.students
        .where((s) =>
            q.isEmpty ||
            s.fullName.toLowerCase().contains(q) ||
            s.studentNumber.toLowerCase().contains(q))
        .map((s) => (
              student: s,
              periods: {
                for (final p in GradingPeriod.values)
                  p: s.gradeFor(GradingPeriod.values.indexOf(p))
              },
              finalGrade: s.finalGrade,
            ))
        .toList();

    switch (_sort) {
      case _SortMode.name:
        rows.sort((a, b) =>
            a.student.fullName.toLowerCase().compareTo(b.student.fullName.toLowerCase()));
      case _SortMode.highest:
        rows.sort((a, b) => (b.finalGrade ?? -1).compareTo(a.finalGrade ?? -1));
      case _SortMode.lowest:
        rows.sort((a, b) => (a.finalGrade ?? 999).compareTo(b.finalGrade ?? 999));
    }

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Search students',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<_SortMode>(
            tooltip: 'Sort students',
            initialValue: _sort,
            position: PopupMenuPosition.under,
            onSelected: (m) => setState(() => _sort = m),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.border),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.name, child: Text('Name A to Z')),
              PopupMenuItem(value: _SortMode.highest, child: Text('Highest final average')),
              PopupMenuItem(value: _SortMode.lowest, child: Text('Lowest final average')),
            ],
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border, width: 1.3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded, size: 18, color: AppColors.textSecondary),
                  if (tablet) ...[
                    const SizedBox(width: 8),
                    Text(
                      switch (_sort) {
                        _SortMode.name => 'Name',
                        _SortMode.highest => 'Highest',
                        _SortMode.lowest => 'Lowest',
                      },
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    const nameMin = 200.0;
    const numW = 92.0;
    const finalW = 150.0;

    Widget headerCell(String text, double w, {bool active = false, TextAlign align = TextAlign.right}) =>
        SizedBox(
          width: w,
          child: Text(
            text,
            textAlign: align,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        );

    Widget tableBody(double available) {
      final nameW = (available - numW * 3 - finalW - 32).clamp(nameMin, 420.0);
      final total = nameW + numW * 3 + finalW + 32;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total < available ? available : total,
          child: Column(
            children: [
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAF9),
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    headerCell('Student', nameW, align: TextAlign.left),
                    for (final p in GradingPeriod.values)
                      headerCell(_periodLabel(p), numW, active: p == _period),
                    headerCell('Final average', finalW),
                  ],
                ),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    'No students match “${_query.trim()}”',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                )
              else
                for (final r in rows)
                  _StandingRow(
                    name: r.student.fullName,
                    number: r.student.studentNumber,
                    nameWidth: nameW,
                    numWidth: numW,
                    finalWidth: finalW,
                    periods: [for (final p in GradingPeriod.values) r.periods[p]],
                    activeIndex: GradingPeriod.values.indexOf(_period),
                    finalGrade: r.finalGrade,
                    selected: r.student.enrollmentId == _selectedId,
                    onTap: () => _selectStudent(r.student.enrollmentId, r.student.fullName),
                  ),
            ],
          ),
        ),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          LayoutBuilder(builder: (context, c) => tableBody(c.maxWidth)),
        ],
      ),
    );
  }
}

class _GradesErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GradesErrorBanner({required this.message, required this.onRetry});

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

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Grid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _Grid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
            ],
          ],
        ),
      ));
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}

class _SheetCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final Color accentBg;
  final String title;
  final String weightLabel;
  final String meta;
  final double? average;
  final String emptyHint;
  final VoidCallback onTap;
  final String? badge;

  final int missingCount;
  final VoidCallback? onMissingTap;

  const _SheetCard({
    required this.icon,
    required this.accent,
    required this.accentBg,
    required this.title,
    required this.weightLabel,
    required this.meta,
    required this.average,
    required this.emptyHint,
    required this.onTap,
    this.badge,
    this.missingCount = 0,
    this.onMissingTap,
  });

  @override
  Widget build(BuildContext context) {
    final avg = average;
    return Semantics(
      button: true,
      label: '$title sheet, $weightLabel, ${avg == null ? 'no average yet' : 'class average ${avg.toStringAsFixed(1)} percent'}',
      excludeSemantics: true,
      child: Hoverable(
        builder: (context, hovered) => AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.curve,
          transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hovered ? accent.withValues(alpha: 0.45) : AppColors.border,
              width: 1.2,
            ),
            boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accentBg,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(icon, size: 21, color: accent),
                        ),
                        const Spacer(),
                        if (missingCount > 0) ...[
                          _MissingBadge(
                            count: missingCount,
                            onTap: onMissingTap,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (badge != null) ...[
                          Tooltip(
                            message: 'Calculated automatically from attendance records',
                            child: StatusBadge(
                              label: badge!,
                              color: AppColors.goldDark,
                              background: AppColors.goldLight,
                              icon: Icons.sync_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        AnimatedSlide(
                          duration: AppMotion.fast,
                          offset: Offset(hovered ? 0.2 : 0, 0),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 19,
                            color: hovered ? accent : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$weightLabel, $meta',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    const Spacer(),
                    if (avg == null)
                      Row(
                        children: [
                          const Icon(Icons.hourglass_empty_rounded, size: 15, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              emptyHint,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${avg.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: _gradeColor(avg),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'class average',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _Bar(value: avg / 100, color: _gradeColor(avg)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const _Bar({required this.value, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 550),
        curve: AppMotion.curve,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color,
          backgroundColor: const Color(0xFFEDF1EE),
        ),
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  final String name;
  final String number;
  final double nameWidth;
  final double numWidth;
  final double finalWidth;
  final List<double?> periods;
  final int activeIndex;
  final double? finalGrade;
  final bool selected;
  final VoidCallback onTap;

  const _StandingRow({
    required this.name,
    required this.number,
    required this.nameWidth,
    required this.numWidth,
    required this.finalWidth,
    required this.periods,
    required this.activeIndex,
    required this.finalGrade,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = finalGrade;
    final Widget remark = f == null
        ? const StatusBadge(label: 'No grades', color: AppColors.textMuted, background: AppColors.background)
        : (f >= _passing
            ? const StatusBadge(label: 'Passing', color: AppColors.success, background: AppColors.successBg)
            : const StatusBadge(label: 'At risk', color: AppColors.danger, background: AppColors.dangerBg));

    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.primaryLight.withValues(alpha: 0.45),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEDF1EE))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: nameWidth,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (number.isNotEmpty)
                            Text(
                              number,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < periods.length; i++)
                SizedBox(
                  width: numWidth,
                  child: Text(
                    periods[i] == null ? '—' : periods[i]!.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == activeIndex ? FontWeight.w700 : FontWeight.w500,
                      color: periods[i] == null
                          ? AppColors.textMuted
                          : (i == activeIndex ? AppColors.textPrimary : AppColors.textSecondary),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              SizedBox(
                width: finalWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    remark,
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 42,
                      child: Text(
                        f == null ? '—' : f.toStringAsFixed(1),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: _gradeColor(f),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryAverages extends StatelessWidget {
  final String period;
  final List<(String, double?)> rows;

  final String? studentName;
  final double? periodGrade;
  final bool loading;
  final VoidCallback onClear;
  final VoidCallback? onOpenReport;

  const _CategoryAverages({
    required this.period,
    required this.rows,
    this.studentName,
    this.periodGrade,
    this.loading = false,
    required this.onClear,
    this.onOpenReport,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    studentName == null ? 'Category averages' : 'Student categories',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (studentName != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Whole class'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              studentName == null ? '$period, whole class' : '$period, $studentName',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            if (studentName == null) ...[
              const SizedBox(height: 4),
              const Text(
                'Tap a student in the table to see their categories.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
            if (studentName != null && !loading) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Period grade',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text(
                    _pct(periodGrade),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _gradeColor(periodGrade),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else
            for (final r in rows) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    _pct(r.$2),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _gradeColor(r.$2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _Bar(value: (r.$2 ?? 0) / 100, color: _gradeColor(r.$2), height: 8),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${_passing.toStringAsFixed(0)}% and up',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 14),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Below ${_passing.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
            if (onOpenReport != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenReport,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open full report'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  final GradingPeriod selected;
  final Map<GradingPeriod, int> counts;
  final ValueChanged<GradingPeriod> onChanged;

  const _PeriodTabs({required this.selected, required this.counts, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const periods = GradingPeriod.values;
    final index = periods.indexOf(selected);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final segW = c.maxWidth / periods.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: AppMotion.base,
              curve: AppMotion.curve,
              left: segW * index,
              top: 0,
              bottom: 0,
              width: segW,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (final p in periods)
                  Expanded(
                    child: Semantics(
                      selected: p == selected,
                      button: true,
                      label: '${_periodLabel(p)}, ${counts[p] ?? 0} items',
                      excludeSemantics: true,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onChanged(p),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          hoverColor: p == selected
                              ? Colors.transparent
                              : AppColors.primaryLight.withValues(alpha: 0.6),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _periodLabel(p),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: p == selected ? Colors.white : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: p == selected
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    '${counts[p] ?? 0}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: p == selected ? Colors.white : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String label;
  final String value;
  final String caption;
  final bool compact;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
    required this.value,
    required this.caption,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  height: 1.1,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 30, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 240.ms);
  }
}

class _StatsSkeleton extends StatelessWidget {
  final bool compact;

  const _StatsSkeleton({required this.compact});

  @override
  Widget build(BuildContext context) {
    Widget tile() => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 110, height: 14),
              SizedBox(height: 14),
              SkeletonBox(width: 64, height: 22),
              SizedBox(height: 10),
              SkeletonBox(width: 120, height: 11),
            ],
          ),
        );
    if (compact) {
      return SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, _) => SizedBox(width: 176, child: tile()),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tile()),
        ],
      ],
    );
  }
}

class _SheetGridSkeleton extends StatelessWidget {
  final int columns;

  const _SheetGridSkeleton({required this.columns});

  @override
  Widget build(BuildContext context) {
    Widget card() => Container(
          height: 178,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 40, height: 40, radius: 10),
              SizedBox(height: 16),
              SkeletonBox(width: 140, height: 15),
              SizedBox(height: 8),
              SkeletonBox(width: 180, height: 12),
              Spacer(),
              SkeletonBox(height: 6, radius: 6),
            ],
          ),
        );
    return _Grid(columns: columns, children: [for (var i = 0; i < columns * 2; i++) card()]);
  }
}

class _LockedBanner extends StatelessWidget {
  final String period;

  const _LockedBanner({required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$period is finalized. Scores, items and attendance in it can no longer be changed.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  final ClassModel classModel;

  const _HistoryDialog({required this.classModel});

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<AuditEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ClassRepository.instance.fetchHistory(widget.classModel.id);
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t load the history.',
        };
      });
    }
  }

  String _when(DateTime at) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '${months[at.month - 1]} ${at.day}, ${at.year}  $h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: const Text('Class history'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : _error != null
                ? Center(
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  )
                : _entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Nothing recorded yet. Every change to scores, items,\nattendance and locks appears here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 18),
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.action,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _when(e.at),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                              if ((e.target ?? '').isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  e.target!,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                              if (e.change.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  e.change,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                'by ${e.by}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            ],
                          );
                        },
                      ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

Size _dialogSize(BuildContext context) {
  final screen = MediaQuery.sizeOf(context);
  final width = (screen.width - 80).clamp(260.0, 440.0);
  final height = (screen.height - 260).clamp(180.0, 380.0);
  return Size(width, height);
}

class _MissingRow {
  final String name;
  final String detail;
  final List<String> missing;

  const _MissingRow({
    required this.name,
    required this.detail,
    required this.missing,
  });
}

class _MissingBadge extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _MissingBadge({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$count student${count == 1 ? '' : 's'} with nothing recorded yet. '
          'Tap to see who.',
      child: Material(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(

          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingDialog extends StatelessWidget {
  final String title;

  final String noun;
  final List<_MissingRow> rows;

  const _MissingDialog({
    required this.title,
    required this.noun,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.danger),
              const SizedBox(width: 8),
              Text('${rows.length} still to record'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),

      content: SizedBox(
        width: _dialogSize(context).width,
        height: _dialogSize(context).height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A blank is not a zero — it only means nothing has been recorded yet. '
              'Type 0 on the sheet for a student who missed it.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _MissingTile(row: rows[i], noun: noun),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Open sheet'),
        ),
      ],
    );
  }
}

class _MissingTile extends StatelessWidget {
  final _MissingRow row;
  final String noun;

  const _MissingTile({required this.row, required this.noun});

  @override
  Widget build(BuildContext context) {

    final shown = row.missing.take(3).join(', ');
    final extra = row.missing.length - 3;
    final detail = extra > 0 ? '$shown +$extra more' : shown;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (row.detail.isNotEmpty)
                  Text(
                    row.detail,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.dangerBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${row.missing.length} $noun${row.missing.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}