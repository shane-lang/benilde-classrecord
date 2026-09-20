import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/assessment_model.dart';
import '../models/class_model.dart';
import '../models/class_standing.dart';
import '../models/student_model.dart';
import '../models/student_report.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const double _tabletBreakpoint = 760;
const double _passing = 75;

String _periodLabel(GradingPeriod p) => switch (p) {
      GradingPeriod.prelim => 'Prelim',
      GradingPeriod.midterm => 'Midterm',
      GradingPeriod.finals => 'Finals',
    };

Color _gradeColor(double? v) => v == null
    ? AppColors.textMuted
    : (v >= _passing ? AppColors.success : AppColors.danger);

String _pct(double? v, {int digits = 1}) =>
    v == null ? '—' : '${v.toStringAsFixed(digits)}%';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class StudentDetailScreen extends StatefulWidget {
  final ClassModel classModel;
  final StudentModel student;

  const StudentDetailScreen({
    super.key,
    required this.classModel,
    required this.student,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  GradingPeriod _period = GradingPeriod.prelim;
  bool _loading = true;
  String? _error;

  StudentReport _report = StudentReport.empty;

  StudentGrade? _row;

  ClassModel get _class => widget.classModel;
  StudentModel get _student => widget.student;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {

      final results = await Future.wait([
        ClassRepository.instance
            .fetchStudentReport(_class.id, _student.id, period: _period),
        ClassRepository.instance.fetchStanding(_class.id, period: _period),
      ]);

      if (!mounted) return;
      final report = results[0] as StudentReport;
      final standing = results[1] as ClassStanding;

      final matches = standing.students.where((s) => s.enrollmentId == _student.id);

      setState(() {
        _report = report;
        _row = matches.isEmpty ? null : matches.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t load this student’s grades.',
        };
      });
    }
  }

  void _selectPeriod(GradingPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = width >= _tabletBreakpoint;
    final hPad = tablet ? 24.0 : 16.0;

    return Scaffold(
      appBar: _appBar(),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, tablet ? 20 : 14, hPad, 40),
              children: [
                _hero(tablet),
                const SizedBox(height: 16),
                _termStrip(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!, onRetry: _load),
                ],
                const SizedBox(height: 24),
                _PeriodTabs(selected: _period, onChanged: _selectPeriod),
                const SizedBox(height: 20),
                if (_loading)
                  const _BreakdownSkeleton()
                else ...[
                  _periodSummary(tablet),
                  const SizedBox(height: 16),
                  _breakdown(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
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
          Text(
            _student.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
          Text(
            _class.subjectCode.isNotEmpty ? _class.subjectCode : _class.subjectName,
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
    );
  }

  Widget _hero(bool tablet) {
    final finalGrade = _row?.finalGrade ?? _report.finalGrade;
    final remark = _row?.remark ?? _report.remark;

    final identity = Row(
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.24), width: 1.5),
          ),
          child: Text(
            _initials(_student.name),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _student.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_student.studentNumber.isNotEmpty)
                    _HeroChip(icon: Icons.badge_outlined, label: _student.studentNumber),
                  _HeroChip(
                    icon: Icons.menu_book_outlined,
                    label: _class.yearSection.isNotEmpty
                        ? '${_class.subjectName}, ${_class.yearSection}'
                        : _class.subjectName,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final score = Column(
      crossAxisAlignment: tablet ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Final average',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          finalGrade == null ? '—' : finalGrade.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.05,
            letterSpacing: -1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        _RemarkBadge(remark: remark, grade: finalGrade),
      ],
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
                  colors: AccentPalette.gradientFor(
                    _class.subjectCode.isNotEmpty ? _class.subjectCode : _class.subjectName,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: DotGridPainter(color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: tablet
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 20),
                      score,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      const SizedBox(height: 20),
                      score,
                    ],
                  ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms);
  }

  Widget _termStrip() {
    final row = _row;
    final values = [
      (GradingPeriod.prelim, row?.prelim),
      (GradingPeriod.midterm, row?.midterm),
      (GradingPeriod.finals, row?.finals),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0)
                const VerticalDivider(width: 1, indent: 12, endIndent: 12),
              Expanded(
                child: _TermCell(
                  label: _periodLabel(values[i].$1),
                  value: values[i].$2,
                  selected: values[i].$1 == _period,
                  onTap: () => _selectPeriod(values[i].$1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodSummary(bool tablet) {
    final grade = _report.periodGrade;
    final attendance = _report.attendanceRate;
    final period = _periodLabel(_period);

    final tiles = <Widget>[
      _StatTile(
        icon: Icons.calculate_outlined,
        color: _gradeColor(grade),
        background: grade == null
            ? AppColors.background
            : (grade >= _passing ? AppColors.successBg : AppColors.dangerBg),
        label: '$period grade',
        value: _pct(grade),
        caption: grade == null
            ? 'Nothing recorded yet'
            : 'Weighted across the categories with data',
        progress: grade == null ? null : grade / 100,
      ),
      _StatTile(
        icon: Icons.event_available_outlined,
        color: attendance == null ? AppColors.textMuted : _gradeColor(attendance),
        background: attendance == null
            ? AppColors.background
            : (attendance >= _passing ? AppColors.successBg : AppColors.dangerBg),
        label: 'Attendance',
        value: _pct(attendance, digits: 0),
        caption: _report.daysRecorded == 0
            ? 'No class days marked yet'
            : 'Attended ${_report.daysPresent} of ${_report.daysRecorded} days',
        progress: attendance == null ? null : attendance / 100,
      ),
    ];

    if (tablet) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 12),
            Expanded(child: tiles[1]),
          ],
        ),
      );
    }
    return Column(
      children: [
        tiles[0],
        const SizedBox(height: 10),
        tiles[1],
      ],
    );
  }

  Widget _breakdown() {
    if (_report.categories.isEmpty) {
      return _EmptyCard(
        icon: Icons.tune_rounded,
        title: 'No grading categories yet',
        message: 'Set up the breakdown from the syllabus first, and this page '
            'will show where each part of the grade came from.',
      );
    }

    if (_report.isEmpty) {
      return _EmptyCard(
        icon: Icons.hourglass_empty_rounded,
        title: 'Nothing recorded in ${_periodLabel(_period)} yet',
        message: 'Once a quiz is scored or a class day is marked, the breakdown '
            'appears here, category by category.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where the grade came from',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  'Categories with nothing recorded are left out, and the rest '
                  'are scaled up to fill the gap.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final c in _report.categories) _CategoryRow(category: c),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms);
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemarkBadge extends StatelessWidget {
  final String remark;
  final double? grade;

  const _RemarkBadge({required this.remark, required this.grade});

  @override
  Widget build(BuildContext context) {
    final label = remark.isEmpty ? 'No grades' : remark;
    final passing = grade != null && grade! >= _passing;
    final icon = grade == null
        ? Icons.remove_circle_outline_rounded
        : (passing ? Icons.check_circle_rounded : Icons.warning_amber_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _TermCell extends StatelessWidget {
  final String label;
  final double? value;
  final bool selected;
  final VoidCallback onTap;

  const _TermCell({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${value == null ? 'no grade' : value!.toStringAsFixed(1)}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primaryDark : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value == null ? '—' : value!.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: _gradeColor(value),
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _PeriodTabs extends StatelessWidget {
  final GradingPeriod selected;
  final ValueChanged<GradingPeriod> onChanged;

  const _PeriodTabs({required this.selected, required this.onChanged});

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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onChanged(p),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        hoverColor: p == selected
                            ? Colors.transparent
                            : AppColors.primaryLight.withValues(alpha: 0.6),
                        child: Center(
                          child: Text(
                            _periodLabel(p),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: p == selected ? Colors.white : AppColors.textSecondary,
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

class _CategoryRow extends StatelessWidget {
  final CategoryResult category;

  const _CategoryRow({required this.category});

  @override
  Widget build(BuildContext context) {
    final percent = category.percent;
    final hasData = percent != null;
    final accent = category.isAttendance ? AppColors.goldDark : AppColors.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF1EE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: category.isAttendance ? AppColors.goldLight : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  category.isAttendance
                      ? Icons.event_available_rounded
                      : Icons.assignment_outlined,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _subtitle(),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _pct(percent),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _gradeColor(percent),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: hasData ? (percent / 100).clamp(0.0, 1.0) : 0),
              duration: const Duration(milliseconds: 550),
              curve: AppMotion.curve,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: _gradeColor(percent),
                backgroundColor: const Color(0xFFEDF1EE),
              ),
            ),
          ),
          if (category.children.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final child in category.children)
              Padding(
                padding: const EdgeInsets.only(left: 42, bottom: 6),
                child: Row(
                  children: [
                    Container(width: 3, height: 16, color: accent.withValues(alpha: 0.4)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      _pct(child.percent),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _gradeColor(child.percent),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    final share = '${(category.weight * 100).toStringAsFixed(0)}% of the grade';
    if (category.percent == null) return '$share, nothing recorded yet';

    final effective = category.effectiveWeight;
    if (effective == null) return share;

    final nominal = category.weight * 100;
    if ((effective - nominal).abs() < 0.5) return share;
    return '$share, counted as ${effective.toStringAsFixed(0)}% so far';
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String label;
  final String value;
  final String caption;
  final double? progress;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
    required this.value,
    required this.caption,
    this.progress,
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
                  fontSize: 26,
                  height: 1.1,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 550),
                curve: AppMotion.curve,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  color: color,
                  backgroundColor: const Color(0xFFEDF1EE),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms);
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

class _BreakdownSkeleton extends StatelessWidget {
  const _BreakdownSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: child,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: card(const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 100, height: 14),
                  SizedBox(height: 14),
                  SkeletonBox(width: 70, height: 24),
                  SizedBox(height: 10),
                  SkeletonBox(height: 6, radius: 6),
                ],
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: card(const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 100, height: 14),
                  SizedBox(height: 14),
                  SkeletonBox(width: 70, height: 24),
                  SizedBox(height: 10),
                  SkeletonBox(height: 6, radius: 6),
                ],
              )),
            ),
          ],
        ),
        const SizedBox(height: 16),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 180, height: 16),
            const SizedBox(height: 18),
            for (var i = 0; i < 4; i++) ...[
              Row(
                children: [
                  const SkeletonBox(width: 30, height: 30, radius: 8),
                  const SizedBox(width: 12),
                  SkeletonBox(width: 120.0 - (i % 3) * 18, height: 13),
                  const Spacer(),
                  const SkeletonBox(width: 44, height: 15),
                ],
              ),
              const SizedBox(height: 10),
              const SkeletonBox(height: 6, radius: 6),
              const SizedBox(height: 18),
            ],
          ],
        )),
      ],
    );
  }
}