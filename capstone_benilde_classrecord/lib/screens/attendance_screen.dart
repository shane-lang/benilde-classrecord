import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/assessment_model.dart';
import '../models/attendance_record.dart';
import '../models/class_model.dart';
import '../models/class_schedule_model.dart';
import '../models/student_model.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'class_schedule_screen.dart';

const double _tabletBreakpoint = 760;
const double _desktopBreakpoint = 1120;
const double _lowThreshold = 75;

const Color _headerSurface = Color(0xFFF8FAF9);
const Color _gridLine = Color(0xFFEDF1EE);

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _weekdaysLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String _shortDate(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}';
String _longDate(DateTime d) =>
    '${_weekdaysLong[d.weekday - 1]}, ${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';
DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

Color _rateColor(double pct) =>
    pct >= _lowThreshold ? AppColors.success : AppColors.danger;

class _StatusStyle {
  final String label;
  final String abbrev;
  final IconData icon;
  final Color color;
  final Color background;

  const _StatusStyle(this.label, this.abbrev, this.icon, this.color, this.background);
}

const Map<AttendanceStatus, _StatusStyle> _statusStyles = {
  AttendanceStatus.present: _StatusStyle(
    'Present', 'P', Icons.check_rounded, Color(0xFF15803D), Color(0xFFDCFCE7)),
  AttendanceStatus.absent: _StatusStyle(
    'Absent', 'A', Icons.close_rounded, Color(0xFFB91C1C), Color(0xFFFEE2E2)),
  AttendanceStatus.late: _StatusStyle(
    'Late', 'L', Icons.schedule_rounded, Color(0xFFB45309), Color(0xFFFEF3C7)),
  AttendanceStatus.excused: _StatusStyle(
    'Excused', 'E', Icons.description_outlined, Color(0xFF475569), Color(0xFFE2E8F0)),
};

_StatusStyle _styleOf(AttendanceStatus s) => _statusStyles[s]!;

class _GridMetrics {
  final double nameWidth;
  final double dateWidth;
  final double rateWidth;
  final double rowHeight;
  final double headerHeight;
  final bool showAvatar;
  final bool showRateBar;

  const _GridMetrics({
    required this.nameWidth,
    required this.dateWidth,
    required this.rateWidth,
    required this.rowHeight,
    required this.headerHeight,
    required this.showAvatar,
    required this.showRateBar,
  });

  static const tablet = _GridMetrics(
    nameWidth: 256,
    dateWidth: 68,
    rateWidth: 136,
    rowHeight: 58,
    headerHeight: 64,
    showAvatar: true,
    showRateBar: true,
  );

  static const mobile = _GridMetrics(
    nameWidth: 128,
    dateWidth: 56,
    rateWidth: 58,
    rowHeight: 54,
    headerHeight: 60,
    showAvatar: false,
    showRateBar: false,
  );
}

class _PeriodSummary {
  final int classDays;
  final int recordedDays;
  final double? average;
  final DateTime? latestDate;
  final int latestAttended;
  final int latestMarked;
  final int lowCount;

  const _PeriodSummary({
    required this.classDays,
    required this.recordedDays,
    required this.average,
    required this.latestDate,
    required this.latestAttended,
    required this.latestMarked,
    required this.lowCount,
  });
}

class AttendanceScreen extends StatefulWidget {
  final ClassModel classModel;

  const AttendanceScreen({super.key, required this.classModel});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  GradingPeriod _selectedPeriod = GradingPeriod.prelim;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnlyLow = false;
  bool _loading = true;

  static const List<AttendanceStatus> _cycleOrder = [
    AttendanceStatus.present,
    AttendanceStatus.absent,
    AttendanceStatus.late,
    AttendanceStatus.excused,
  ];

  final ScrollController _hHeaderCtrl = ScrollController();
  final ScrollController _hBodyCtrl = ScrollController();
  final ScrollController _vNameCtrl = ScrollController();
  final ScrollController _vBodyCtrl = ScrollController();
  final ScrollController _vRateCtrl = ScrollController();
  bool _syncing = false;

  double _currentDateWidth = _GridMetrics.tablet.dateWidth;

  Map<String, AttendanceRecord> _index = {};

  ClassModel get _class => widget.classModel;
  ClassScheduleModel? get _schedule => _class.schedule;

  bool get _locked => _class.lockedFor(_selectedPeriod);

  bool _blockedByLock() {
    if (!_locked) return false;
    AppToast.show(
      context,
      '${_periodLabel(_selectedPeriod)} is finalized. Reopen it on the grades page first.',
      type: ToastType.info,
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _linkScroll([_hHeaderCtrl, _hBodyCtrl]);
    _linkScroll([_vNameCtrl, _vBodyCtrl, _vRateCtrl]);

    Future.delayed(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      setState(() => _loading = false);
      _scrollToTodayAfterLayout();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hHeaderCtrl.dispose();
    _hBodyCtrl.dispose();
    _vNameCtrl.dispose();
    _vBodyCtrl.dispose();
    _vRateCtrl.dispose();
    super.dispose();
  }

  void _linkScroll(List<ScrollController> group) {
    for (final source in group) {
      source.addListener(() {
        if (_syncing || !source.hasClients) return;
        _syncing = true;
        for (final target in group) {
          if (identical(target, source) || !target.hasClients) continue;
          final pos = target.position;
          final offset =
              source.offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
          if (offset != target.offset) target.jumpTo(offset);
        }
        _syncing = false;
      });
    }
  }

  void _scrollToTodayAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDate(DateTime.now(), animate: false);
    });
  }

  void _scrollToDate(DateTime date, {bool animate = true}) {
    if (!_hBodyCtrl.hasClients) return;
    final index = _datesForPeriod.indexWhere((d) => _sameDay(d, date));
    if (index < 0) return;
    final pos = _hBodyCtrl.position;
    final target = (index * _currentDateWidth - _currentDateWidth * 1.5)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (animate) {
      _hBodyCtrl.animateTo(target,
          duration: const Duration(milliseconds: 380), curve: AppMotion.curve);
    } else {
      _hBodyCtrl.jumpTo(target);
    }
  }

  String _key(String studentId, DateTime d) =>
      '$studentId|${d.year}-${d.month}-${d.day}';

  void _rebuildIndex() {
    final map = <String, AttendanceRecord>{};
    for (final r in _class.attendanceRecords) {
      if (r.gradingPeriod == _selectedPeriod) map[_key(r.studentId, r.date)] = r;
    }
    _index = map;
  }

  AttendanceRecord? _cell(String studentId, DateTime date) =>
      _index[_key(studentId, date)];

  AttendanceRecord? _recordOn(String studentId, DateTime date) {
    for (final r in _class.attendanceRecords) {
      if (r.studentId == studentId &&
          r.isSameDate(date) &&
          r.gradingPeriod == _selectedPeriod) {
        return r;
      }
    }
    return null;
  }

  List<DateTime> _datesFor(GradingPeriod period) {
    final dates = <DateTime>{};
    dates.addAll(_schedule?.classDatesFor(period) ?? const []);
    for (final r in _class.attendanceRecords) {
      if (r.gradingPeriod == period) dates.add(_dayOnly(r.date));
    }
    return dates.toList()..sort();
  }

  List<DateTime> get _datesForPeriod => _datesFor(_selectedPeriod);

  double? _percentForStudent(String studentId) {
    var total = 0;
    var attended = 0;
    for (final r in _class.attendanceRecords) {
      if (r.studentId != studentId || r.gradingPeriod != _selectedPeriod) continue;
      total++;
      if (r.status != AttendanceStatus.absent) attended++;
    }
    if (total == 0) return null;
    return attended / total * 100;
  }

  bool _isLow(String studentId) {
    final pct = _percentForStudent(studentId);
    return pct != null && pct < _lowThreshold;
  }

  List<StudentModel> get _filteredStudents {
    final q = _searchQuery.trim().toLowerCase();
    return _class.activeStudents.where((s) {
      final matches = q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.studentNumber.toLowerCase().contains(q);
      if (!matches) return false;
      return !_showOnlyLow || _isLow(s.id);
    }).toList();
  }

  _PeriodSummary _summary(List<DateTime> dates) {
    final records = _class.attendanceRecords
        .where((r) => r.gradingPeriod == _selectedPeriod)
        .toList();
    final recordedDays = <DateTime>{for (final r in records) _dayOnly(r.date)};

    double? average;
    if (records.isNotEmpty) {
      final attended =
          records.where((r) => r.status != AttendanceStatus.absent).length;
      average = attended / records.length * 100;
    }

    final today = _dayOnly(DateTime.now());
    final sorted = recordedDays.toList()..sort();
    DateTime? latest;
    for (final d in sorted) {
      if (!d.isAfter(today)) latest = d;
    }
    latest ??= sorted.isNotEmpty ? sorted.last : null;

    var latestAttended = 0;
    var latestMarked = 0;
    if (latest != null) {
      for (final r in records) {
        if (!_sameDay(r.date, latest)) continue;
        latestMarked++;
        if (r.status != AttendanceStatus.absent) latestAttended++;
      }
    }

    return _PeriodSummary(
      classDays: dates.length,
      recordedDays: recordedDays.length,
      average: average,
      latestDate: latest,
      latestAttended: latestAttended,
      latestMarked: latestMarked,
      lowCount: _class.activeStudents.where((s) => _isLow(s.id)).length,
    );
  }

  String _studentName(String id) {
    final match = _class.activeStudents.where((s) => s.id == id);
    return match.isNotEmpty ? match.first.name : 'student';
  }

  String _messageFor(Object error) => switch (error) {
        ApiException e => e.message,
        NetworkException e => e.message,
        _ => 'Couldn’t save that. Check your connection.',
      };

  Future<bool> _push(
    List<({
      String enrollmentId,
      DateTime date,
      AttendanceStatus? status,
      GradingPeriod period,
      String? remarks,
    })> records,
  ) async {
    try {
      await ClassRepository.instance.saveAttendance(_class.id, records);
      return true;
    } catch (e) {
      if (mounted) AppToast.show(context, _messageFor(e), type: ToastType.error);
      return false;
    }
  }

  Future<void> _setStatus(String studentId, DateTime date, AttendanceStatus status,
      {String? remarks}) async {
    if (_blockedByLock()) return;
    final previous = _recordOn(studentId, date);
    final cleanRemarks = remarks ?? previous?.remarks;
    final tidied = (cleanRemarks == null || cleanRemarks.trim().isEmpty)
        ? null
        : cleanRemarks.trim();

    final updated = AttendanceRecord(
      studentId: studentId,
      date: _dayOnly(date),
      status: status,
      gradingPeriod: _selectedPeriod,
      remarks: tidied,
    );

    setState(() {
      if (previous != null) _class.attendanceRecords.remove(previous);
      _class.attendanceRecords.add(updated);
    });

    final ok = await _push([
      (
        enrollmentId: studentId,
        date: _dayOnly(date),
        status: status,
        period: _selectedPeriod,
        remarks: tidied,
      )
    ]);

    if (!ok && mounted) {
      setState(() {
        _class.attendanceRecords.remove(updated);
        if (previous != null) _class.attendanceRecords.add(previous);
      });
    }
  }

  void _cycleStatus(String studentId, DateTime date) {
    if (_blockedByLock()) return;
    HapticFeedback.selectionClick();
    final existing = _recordOn(studentId, date);
    final next = existing == null
        ? AttendanceStatus.present
        : _cycleOrder[(_cycleOrder.indexOf(existing.status) + 1) % _cycleOrder.length];
    _setStatus(studentId, date, next, remarks: existing?.remarks);
  }

  Future<void> _clearRecord(AttendanceRecord record) async {
    if (_blockedByLock()) return;
    setState(() => _class.attendanceRecords.remove(record));

    final ok = await _push([
      (
        enrollmentId: record.studentId,
        date: record.date,
        status: null,
        period: record.gradingPeriod,
        remarks: null,
      )
    ]);

    if (!ok) {
      if (mounted) setState(() => _class.attendanceRecords.add(record));
      return;
    }
    if (!mounted) return;

    AppToast.show(
      context,
      'Cleared ${_studentName(record.studentId)} on ${_shortDate(record.date)}',
      actionLabel: 'Undo',
      onAction: () => _setStatus(
        record.studentId,
        record.date,
        record.status,
        remarks: record.remarks,
      ),
    );
  }

  Future<void> _markAllPresent(DateTime date) async {
    if (_blockedByLock()) return;
    final added = <AttendanceRecord>[];
    setState(() {
      for (final s in _class.activeStudents) {
        if (_recordOn(s.id, date) != null) continue;
        final r = AttendanceRecord(
          studentId: s.id,
          date: _dayOnly(date),
          status: AttendanceStatus.present,
          gradingPeriod: _selectedPeriod,
        );
        _class.attendanceRecords.add(r);
        added.add(r);
      }
    });

    if (added.isEmpty) {
      AppToast.show(context, 'Everyone already has a status on ${_shortDate(date)}');
      return;
    }

    final ok = await _push([
      for (final r in added)
        (
          enrollmentId: r.studentId,
          date: r.date,
          status: r.status,
          period: r.gradingPeriod,
          remarks: null,
        )
    ]);

    if (!ok) {
      if (mounted) {
        setState(() => _class.attendanceRecords.removeWhere(added.contains));
      }
      return;
    }
    if (!mounted) return;

    AppToast.show(
      context,
      'Marked ${added.length} student${added.length == 1 ? '' : 's'} present on ${_shortDate(date)}',
      type: ToastType.success,
    );
  }

  Future<void> _addDate() async {
    if (_blockedByLock()) return;
    final now = DateTime.now();
    final first = DateTime(2024);
    final last = DateTime(2030, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: now.isBefore(first) ? first : (now.isAfter(last) ? last : now),
      firstDate: first,
      lastDate: last,
      helpText: 'Add a class day to ${_periodLabel(_selectedPeriod)}',
      confirmText: 'Add date',
    );
    if (picked == null || !mounted) return;
    final day = _dayOnly(picked);

    if (_datesForPeriod.any((d) => _sameDay(d, day))) {
      AppToast.show(context, '${_shortDate(day)} is already on the sheet');
      _scrollToDate(day);
      return;
    }

    final belongsTo = _schedule?.periodForDate(day);
    if (belongsTo != null && belongsTo != _selectedPeriod) {
      final ok = await showConfirmDialog(
        context,
        title: 'This date falls in ${_periodLabel(belongsTo)}',
        message:
            'Your class schedule places ${_shortDate(day)} in ${_periodLabel(belongsTo)}. '
            'Add it to ${_periodLabel(_selectedPeriod)} anyway?',
        confirmLabel: 'Add to ${_periodLabel(_selectedPeriod)}',
        icon: Icons.event_note_rounded,
      );
      if (!ok || !mounted) return;
    }

    final added = [
      for (final s in _class.activeStudents)
        AttendanceRecord(
          studentId: s.id,
          date: day,
          status: AttendanceStatus.present,
          gradingPeriod: _selectedPeriod,
        ),
    ];
    setState(() => _class.attendanceRecords.addAll(added));

    final ok = await _push([
      for (final r in added)
        (
          enrollmentId: r.studentId,
          date: r.date,
          status: r.status,
          period: r.gradingPeriod,
          remarks: null,
        )
    ]);

    if (!ok) {
      if (mounted) {
        setState(() => _class.attendanceRecords.removeWhere(added.contains));
      }
      return;
    }
    if (!mounted) return;

    AppToast.show(
      context,
      'Added ${_shortDate(day)}. Everyone starts as present.',
      type: ToastType.success,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDate(day));
  }

  Future<void> _deleteDate(DateTime date) async {
    if (_blockedByLock()) return;
    final count = _class.attendanceRecords
        .where((r) => r.isSameDate(date) && r.gradingPeriod == _selectedPeriod)
        .length;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_shortDate(date)}?',
      message: count == 0
          ? 'This removes the column from ${_periodLabel(_selectedPeriod)}.'
          : 'This deletes $count attendance record${count == 1 ? '' : 's'} for '
              '${_longDate(date)} in ${_periodLabel(_selectedPeriod)}.',
      confirmLabel: 'Delete day',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    final removed = _class.attendanceRecords
        .where((r) => r.isSameDate(date) && r.gradingPeriod == _selectedPeriod)
        .toList();
    final wasScheduled =
        _schedule?.classDatesFor(_selectedPeriod).any((d) => _sameDay(d, date)) ?? false;

    setState(() {
      _class.attendanceRecords.removeWhere(removed.contains);

      if (wasScheduled) _schedule!.setHoliday(date, true, reason: 'Removed');
    });

    try {
      await ClassRepository.instance.deleteAttendanceDay(_class.id, date);
      if (wasScheduled) {
        await ClassRepository.instance.addNoClassDay(_class.id, date, 'Removed');
      }
      if (!mounted) return;

      AppToast.show(context, 'Deleted ${_shortDate(date)}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _class.attendanceRecords.addAll(removed);
        if (wasScheduled) _schedule!.setHoliday(date, false);
      });
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  static const List<String> _suspensionReasons = [
    'Class suspended',
    'Typhoon / bad weather',
    'Holiday',
    'School event',
  ];

  Future<void> _pickSuspendedDate() async {
    if (_blockedByLock()) return;
    final now = DateTime.now();
    final first = DateTime(2024);
    final last = DateTime(2030, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: now.isBefore(first) ? first : (now.isAfter(last) ? last : now),
      firstDate: first,
      lastDate: last,
      helpText: 'Which day was the class suspended?',
      confirmText: 'Next',
    );
    if (picked == null || !mounted) return;
    final day = _dayOnly(picked);
    if (_schedule?.isHoliday(day) ?? false) {
      AppToast.show(context, '${_shortDate(day)} is already marked as no class');
      return;
    }
    await _toggleHoliday(day, true);
  }

  Future<void> _toggleHoliday(DateTime date, bool makeHoliday) async {
    if (_blockedByLock()) return;
    String? reason;

    final saved = _class.attendanceRecords.where((r) => r.isSameDate(date)).toList();

    if (makeHoliday) {
      final controller = TextEditingController(text: _suspensionReasons.first);
      reason = await _showAppDialog<String>(
        context,
        maxWidth: 460,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => _DialogFrame(
            icon: Icons.event_busy_rounded,
            iconColor: AppColors.warning,
            iconBackground: AppColors.warningBg,
            title: 'No class on ${_shortDate(date)}',
            subtitle: saved.isEmpty
                ? 'Use this when the class is suspended or cancelled. The day will '
                    'not count in anyone\'s attendance.'
                : 'The day will not count in anyone\'s attendance. The '
                    '${saved.length} mark${saved.length == 1 ? '' : 's'} already '
                    'saved for this day will be cleared.',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in _suspensionReasons)
                      ChoiceChip(
                        label: Text(r),
                        selected: controller.text.trim() == r,
                        onSelected: (_) => setLocal(() => controller.text = r),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. Class suspended due to typhoon',
                  ),
                  onChanged: (_) => setLocal(() {}),
                  onSubmitted: (v) => Navigator.of(ctx).pop(v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Mark as no class'),
              ),
            ],
          ),
        ),
      );
      Future.delayed(const Duration(milliseconds: 400), controller.dispose);
      if (reason == null || !mounted) return;
      if (reason.trim().isEmpty) reason = _suspensionReasons.first;
    }

    setState(() {
      _class.schedule ??= ClassScheduleModel();
      _class.schedule!.setHoliday(date, makeHoliday, reason: reason);
      if (makeHoliday) _class.attendanceRecords.removeWhere(saved.contains);
    });

    try {
      if (makeHoliday) {
        if (saved.isNotEmpty) {
          await ClassRepository.instance.deleteAttendanceDay(_class.id, date);
        }
        await ClassRepository.instance.addNoClassDay(_class.id, date, reason);
      } else {
        await ClassRepository.instance.removeNoClassDay(_class.id, date);
      }
      if (!mounted) return;
      AppToast.show(
        context,
        makeHoliday
            ? '${_shortDate(date)} marked as no class (${reason!.trim()})'
            : '${_shortDate(date)} is a class day again',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _class.schedule!.setHoliday(date, !makeHoliday);
        if (makeHoliday) _class.attendanceRecords.addAll(saved);
      });
      AppToast.show(context, _messageFor(e), type: ToastType.error);
    }
  }

  List<DateTime> get _suspendedDays {
    final schedule = _schedule;
    if (schedule == null) return const [];
    final days = schedule.holidayDates.where((d) {
      if (schedule.holidayReasons[d] == 'Removed') return false;
      final period = schedule.periodForDate(d);
      return period == null || period == _selectedPeriod;
    }).toList()
      ..sort();
    return days;
  }

  Widget _suspendedStrip(bool isTablet) {
    final days = _suspendedDays;
    if (days.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: isTablet ? 12 : 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_rounded, size: 16, color: AppColors.warning),
                SizedBox(width: 6),
                Text(
                  'No class (not counted):',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            for (final d in days)
              InputChip(
                label: Text(
                  _schedule!.holidayReasons[d] == null
                      ? _shortDate(d)
                      : '${_shortDate(d)} · ${_schedule!.holidayReasons[d]}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                backgroundColor: AppColors.surface,
                visualDensity: VisualDensity.compact,
                deleteIcon: _locked ? null : const Icon(Icons.undo_rounded, size: 16),
                deleteButtonTooltipMessage: 'Make it a class day again',
                onDeleted: _locked ? null : () => _toggleHoliday(d, false),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openClassSchedule() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClassScheduleScreen(classModel: _class)),
    );
    if (!mounted) return;
    setState(() {});
    _scrollToTodayAfterLayout();
  }

  void _selectPeriod(GradingPeriod p) {
    if (p == _selectedPeriod) return;
    setState(() {
      _selectedPeriod = p;
      _showOnlyLow = false;
    });
    _scrollToTodayAfterLayout();
  }

  Future<void> _openCellDetail(StudentModel student, DateTime date) async {
    final existing = _recordOn(student.id, date);
    var selected = existing?.status ?? AttendanceStatus.present;
    final remarks = TextEditingController(text: existing?.remarks ?? '');

    await _showAppDialog<void>(
      context,
      maxWidth: 500,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void save() {
            Navigator.of(ctx).pop();
            _setStatus(student.id, date, selected, remarks: remarks.text);
            AppToast.show(context, 'Saved ${student.name} as ${_styleOf(selected).label}',
                type: ToastType.success);
          }

          return _DialogFrame(
            leading: _Avatar(name: student.name, size: 44),
            title: student.name,
            subtitle: student.studentNumber.isEmpty
                ? _longDate(date)
                : 'Student no. ${student.studentNumber}\n${_longDate(date)}',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _FieldLabel('Status'),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, c) {
                  final perRow = c.maxWidth < 360 ? 2 : 4;
                  final gap = 8.0;
                  final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final s in AttendanceStatus.values)
                        SizedBox(
                          width: w,
                          child: _StatusOption(
                            status: s,
                            selected: selected == s,
                            onTap: _locked ? null : () => setLocal(() => selected = s),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 20),
                TextField(
                  controller: remarks,
                  minLines: 2,
                  maxLines: 4,
                  readOnly: _locked,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    hintText: 'e.g. Sick, submitted an excuse letter',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_locked) ...[
                  const SizedBox(height: 14),
                  _InlineLockNote(period: _periodLabel(_selectedPeriod)),
                ],
              ],
            ),
            actions: [
              if (existing != null && !_locked) ...[
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _clearRecord(existing);
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  label: const Text('Clear'),
                ),
                const Spacer(),
              ],
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: Text(_locked ? 'Close' : 'Cancel'),
              ),
              if (!_locked) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: save,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ],
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), remarks.dispose);
  }

  Future<void> _showDateOptions(DateTime date) async {
    final isHoliday = _schedule?.isHoliday(date) ?? false;
    final reason = _schedule?.holidayReasons[ClassScheduleModel.normalize(date)];
    final counts = <AttendanceStatus, int>{for (final s in AttendanceStatus.values) s: 0};
    for (final s in _class.activeStudents) {
      final r = _cell(s.id, date);
      if (r != null) counts[r.status] = counts[r.status]! + 1;
    }
    final marked = counts.values.fold<int>(0, (a, b) => a + b);
    final unmarked = _class.activeStudents.length - marked;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg + 4)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_longDate(date), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${_periodLabel(_selectedPeriod)}, $marked of ${_class.activeStudents.length} marked',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (isHoliday) ...[
                const SizedBox(height: 10),
                StatusBadge(
                  label: reason == null ? 'No class' : 'No class: $reason',
                  color: AppColors.warning,
                  background: AppColors.warningBg,
                  icon: Icons.event_busy_rounded,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in AttendanceStatus.values)
                    _CountPill(style: _styleOf(s), count: counts[s]!),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              if (_locked)
                _InlineLockNote(period: _periodLabel(_selectedPeriod))
              else ...[
                _SheetAction(
                  icon: Icons.done_all_rounded,
                  color: AppColors.primary,
                  label: 'Mark everyone present',
                  description: unmarked == 0
                      ? 'Every student already has a status'
                      : 'Fills the $unmarked empty cell${unmarked == 1 ? '' : 's'}. Existing marks stay.',
                  enabled: unmarked > 0,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _markAllPresent(date);
                  },
                ),
                _SheetAction(
                  icon: isHoliday ? Icons.event_available_rounded : Icons.event_busy_rounded,
                  color: AppColors.warning,
                  label: isHoliday ? 'Make it a class day again' : 'Class suspended / no class',
                  description: isHoliday
                      ? 'Show this date in the schedule again'
                      : 'Typhoon, holiday or cancelled class. Won\'t count in attendance.',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _toggleHoliday(date, !isHoliday);
                  },
                ),
                _SheetAction(
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  label: 'Delete this day',
                  description: 'Removes the column and its records. You can undo.',
                  destructive: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _deleteDate(date);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _buildCsv(List<DateTime> dates) {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('Student,Student No.');
    for (final d in dates) {
      b.write(',${d.month}/${d.day}/${d.year}');
    }
    b.write(',Percent\n');
    for (final s in _class.activeStudents) {
      b.write('${esc(s.name)},${esc(s.studentNumber)}');
      for (final d in dates) {
        final r = _cell(s.id, d);
        b.write(',${r != null ? _styleOf(r.status).abbrev : ''}');
      }
      final pct = _percentForStudent(s.id);
      b.write(',${pct != null ? pct.toStringAsFixed(0) : ''}\n');
    }
    return b.toString();
  }

  Future<void> _exportCsv() async {
    final dates = _datesForPeriod;
    if (dates.isEmpty || _class.activeStudents.isEmpty) {
      AppToast.show(context, 'Nothing to export yet. Add a class day first.');
      return;
    }
    final csv = _buildCsv(dates);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;

    await _showAppDialog<void>(
      context,
      maxWidth: 620,
      builder: (ctx) => _DialogFrame(
        icon: Icons.task_alt_rounded,
        iconColor: AppColors.success,
        iconBackground: AppColors.successBg,
        title: 'CSV copied to clipboard',
        subtitle:
            '${_class.activeStudents.length} students and ${dates.length} class days from '
            '${_periodLabel(_selectedPeriod)}. Paste it into Excel or Google Sheets.',
        body: Container(
          constraints: const BoxConstraints(maxHeight: 260),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));

              if (ctx.mounted) {
                AppToast.show(ctx, 'Copied again', type: ToastType.success);
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy again'),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= _tabletBreakpoint;
    final isDesktop = width >= _desktopBreakpoint;
    final hPad = isDesktop ? 32.0 : (isTablet ? 24.0 : 12.0);

    _rebuildIndex();
    final dates = _datesForPeriod;
    final summary = _summary(dates);
    final hasSheet = _class.activeStudents.isNotEmpty && dates.isNotEmpty;

    return Scaffold(
      appBar: _appBar(isTablet),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, isTablet ? 18 : 12, hPad, isTablet ? 24 : 12),
              child: LayoutBuilder(builder: (context, c) {

                final roomy = c.maxHeight >= 560;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerRow(isTablet),
                    if (_locked) ...[
                      SizedBox(height: isTablet ? 14 : 10),
                      _LockedAttendanceBanner(period: _periodLabel(_selectedPeriod)),
                    ],
                    if (hasSheet && roomy) ...[
                      SizedBox(height: isTablet ? 16 : 12),
                      _loading
                          ? _StatsSkeleton(compact: !isTablet)
                          : _statsRow(summary, isTablet),
                    ],
                    if (hasSheet) ...[
                      SizedBox(height: isTablet ? 16 : 12),
                      _toolbar(summary, isTablet, isDesktop),
                    ],
                    _suspendedStrip(isTablet),
                    SizedBox(height: isTablet ? 14 : 10),
                    Expanded(child: _sheetCard(dates, isTablet, isDesktop)),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool isTablet) {
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
            'Attendance',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.15,
            ),
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
        if (!_locked)
          IconButton(
            icon: const Icon(Icons.event_busy_rounded),
            tooltip: 'Class suspended / no class',
            onPressed: _pickSuspendedDate,
          ),
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Class schedule',
          onPressed: _openClassSchedule,
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Export as CSV',
          onPressed: _exportCsv,
        ),
        const SizedBox(width: 4),
        if (_locked)
          const Padding(
            padding: EdgeInsets.only(right: 12, left: 4),
            child: _FinalizedChip(),
          )
        else if (isTablet)
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: ElevatedButton.icon(
              onPressed: _addDate,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Add date'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          )
        else ...[
          IconButton.filled(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add date',
            onPressed: _addDate,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(42, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _headerRow(bool isTablet) {
    final tabs = _PeriodTabs(
      selected: _selectedPeriod,
      counts: {for (final p in GradingPeriod.values) p: _datesFor(p).length},
      onChanged: _selectPeriod,
    );

    if (!isTablet) return tabs;

    return Row(
      children: [
        Expanded(child: _breadcrumb()),
        const SizedBox(width: 16),
        _ScheduleChip(schedule: _schedule, onTap: _openClassSchedule),
        const SizedBox(width: 12),
        SizedBox(width: 360, child: tabs),
      ],
    );
  }

  Widget _breadcrumb() {
    final classLabel =
        _class.subjectCode.isNotEmpty ? _class.subjectCode : _class.subjectName;
    return Row(
      children: [
        Flexible(
          child: Hoverable(
          builder: (context, hovered) => GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Text(
              classLabel,
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
        const Flexible(
          child: Text(
            'Attendance',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statsRow(_PeriodSummary s, bool isTablet) {
    final avg = s.average;
    final tiles = <Widget>[
      _StatTile(
        compact: !isTablet,
        icon: Icons.event_note_outlined,
        color: AppColors.primary,
        background: AppColors.primaryLight,
        label: 'Class days',
        value: '${s.classDays}',
        caption: s.recordedDays == 0
            ? 'None recorded yet'
            : '${s.recordedDays} with records',
      ),
      _StatTile(
        compact: !isTablet,
        icon: Icons.insights_rounded,
        color: avg == null ? AppColors.textMuted : _rateColor(avg),
        background: avg == null
            ? AppColors.background
            : (avg >= _lowThreshold ? AppColors.successBg : AppColors.dangerBg),
        label: 'Average attendance',
        value: avg == null ? '—' : '${avg.toStringAsFixed(0)}%',
        caption: avg == null ? 'Mark a day to see this' : 'Late and excused count as attended',
        progress: avg == null ? null : avg / 100,
      ),
      _StatTile(
        compact: !isTablet,
        icon: Icons.how_to_reg_outlined,
        color: AppColors.goldDark,
        background: AppColors.goldLight,
        label: 'Latest session',
        value: s.latestDate == null ? '—' : '${s.latestAttended}/${_class.activeStudents.length}',
        caption: s.latestDate == null
            ? 'No sessions yet'
            : 'Attended on ${_shortDate(s.latestDate!)}',
      ),
      _StatTile(
        compact: !isTablet,
        icon: s.lowCount == 0 ? Icons.verified_outlined : Icons.warning_amber_rounded,
        color: s.lowCount == 0 ? AppColors.success : AppColors.danger,
        background: s.lowCount == 0 ? AppColors.successBg : AppColors.dangerBg,
        label: 'Below ${_lowThreshold.toStringAsFixed(0)}%',
        value: '${s.lowCount}',
        caption: s.lowCount == 0
            ? 'Everyone is on track'
            : (_showOnlyLow ? 'Showing only these. Tap to show all.' : 'Tap to show only these'),
        selected: _showOnlyLow,
        onTap: s.lowCount == 0 ? null : () => setState(() => _showOnlyLow = !_showOnlyLow),
      ),
    ];

    if (isTablet) {
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

  Widget _toolbar(_PeriodSummary s, bool isTablet, bool isDesktop) {
    final search = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'Search by name or student no.',
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
        ),
      ),
    );

    final filter = _FilterToggle(
      label: 'Below ${_lowThreshold.toStringAsFixed(0)}%',
      count: s.lowCount,
      selected: _showOnlyLow,
      onTap: () => setState(() => _showOnlyLow = !_showOnlyLow),
    );

    return Row(
      children: [
        if (isTablet)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: search,
          )
        else
          Expanded(child: search),
        const SizedBox(width: 10),
        filter,
        if (isDesktop) ...[
          const Spacer(),
          const _Legend(),
        ] else if (isTablet)
          const Spacer(),
      ],
    );
  }

  Widget _sheetCard(List<DateTime> dates, bool isTablet, bool isDesktop) {
    Widget child;
    if (_loading) {
      child = _GridSkeleton(metrics: isTablet ? _GridMetrics.tablet : _GridMetrics.mobile);
    } else if (_class.activeStudents.isEmpty) {
      child = _EmptyState(
        icon: Icons.group_add_outlined,
        title: 'No students in this class yet',
        message: 'Add students from the class page, then come back here to take attendance.',
        primaryLabel: 'Back to class',
        primaryIcon: Icons.arrow_back_rounded,
        onPrimary: () => Navigator.of(context).maybePop(),
      );
    } else if (dates.isEmpty) {
      child = _NoDatesState(
        period: _periodLabel(_selectedPeriod),
        hasSchedule: _schedule != null && _schedule!.meetingWeekdays.isNotEmpty,
        periodHasRange: _schedule?.periodRanges[_selectedPeriod] != null,
        wide: isTablet,
        onSchedule: _openClassSchedule,
        onAddDate: _addDate,
      );
    } else {
      final students = _filteredStudents;
      if (students.isEmpty) {
        final q = _searchQuery.trim();
        child = _EmptyState(
          icon: Icons.person_search_outlined,
          title: q.isNotEmpty ? 'No students match “$q”' : 'No students below ${_lowThreshold.toStringAsFixed(0)}%',
          message: q.isNotEmpty
              ? 'Check the spelling, or search by student number instead.'
              : 'Everyone in this view is at or above the threshold.',
          primaryLabel: q.isNotEmpty ? 'Clear search' : 'Show all students',
          primaryIcon: Icons.filter_alt_off_outlined,
          onPrimary: () {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
              _showOnlyLow = false;
            });
          },
        );
      } else {
        child = KeyedSubtree(
          key: ValueKey(_selectedPeriod),
          child: _grid(students, dates, isTablet, isDesktop)
              .animate()
              .fadeIn(duration: 220.ms, curve: AppMotion.curve),
        );
      }
    }

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

  Widget _grid(List<StudentModel> students, List<DateTime> dates, bool isTablet,
      bool isDesktop) {
    final m = isTablet ? _GridMetrics.tablet : _GridMetrics.mobile;
    _currentDateWidth = m.dateWidth;
    final today = DateTime.now();
    final noScrollbars = ScrollConfiguration.of(context).copyWith(scrollbars: false);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final midWidth = math.max(0.0, c.maxWidth - m.nameWidth - m.rateWidth);
            final contentWidth = math.max(dates.length * m.dateWidth, midWidth);

            return Column(
              children: [

                SizedBox(
                  height: m.headerHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cornerCell(students.length, m),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: noScrollbars,
                          child: SingleChildScrollView(
                            controller: _hHeaderCtrl,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: contentWidth,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final d in dates)
                                    _DateHeaderCell(
                                      date: d,
                                      width: m.dateWidth,
                                      isToday: _sameDay(d, today),
                                      isHoliday: _schedule?.isHoliday(d) ?? false,
                                      completion: _class.activeStudents.isEmpty
                                          ? 0.0
                                          : _class.activeStudents
                                                  .where((s) => _cell(s.id, d) != null)
                                                  .length /
                                              _class.activeStudents.length,
                                      onTap: () => _showDateOptions(d),
                                    ),
                                  Expanded(child: _headerFiller()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _rateHeader(m),
                    ],
                  ),
                ),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: m.nameWidth,
                        child: ScrollConfiguration(
                          behavior: noScrollbars,
                          child: ListView.builder(
                            controller: _vNameCtrl,
                            physics: const ClampingScrollPhysics(),
                            itemExtent: m.rowHeight,
                            itemCount: students.length,
                            itemBuilder: (_, i) => _nameCell(students[i], m),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _vBodyCtrl,
                          notificationPredicate: (n) =>
                              n.depth == 1 && n.metrics.axis == Axis.vertical,
                          child: Scrollbar(
                            controller: _hBodyCtrl,
                            thumbVisibility: isDesktop,
                            child: ScrollConfiguration(
                              behavior: noScrollbars,
                              child: SingleChildScrollView(
                                controller: _hBodyCtrl,
                                scrollDirection: Axis.horizontal,
                                physics: const ClampingScrollPhysics(),
                                child: SizedBox(
                                  width: contentWidth,
                                  child: ListView.builder(
                                    controller: _vBodyCtrl,
                                    physics: const ClampingScrollPhysics(),
                                    itemExtent: m.rowHeight,
                                    itemCount: students.length,
                                    itemBuilder: (_, i) {
                                      final s = students[i];
                                      return DecoratedBox(
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: _gridLine)),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            for (final d in dates)
                                              _StatusCell(
                                                width: m.dateWidth,
                                                record: _cell(s.id, d),
                                                isToday: _sameDay(d, today),
                                                isHoliday: _schedule?.isHoliday(d) ?? false,
                                                semanticLabel:
                                                    '${s.name}, ${_longDate(d)}',
                                                onTap: () => _cycleStatus(s.id, d),
                                                onDetails: () => _openCellDetail(s, d),
                                                onKey: (status) {
                                                  if (status == null) {
                                                    final r = _recordOn(s.id, d);
                                                    if (r != null) _clearRecord(r);
                                                  } else {
                                                    _setStatus(s.id, d, status);
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: m.rateWidth,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: AppColors.border)),
                          ),
                          child: ScrollConfiguration(
                            behavior: noScrollbars,
                            child: ListView.builder(
                              controller: _vRateCtrl,
                              physics: const ClampingScrollPhysics(),
                              itemExtent: m.rowHeight,
                              itemCount: students.length,
                              itemBuilder: (_, i) =>
                                  _RateCell(pct: _percentForStudent(students[i].id), metrics: m),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        _gridFooter(isTablet, isDesktop),
      ],
    );
  }

  Widget _headerFiller() => const DecoratedBox(
        decoration: BoxDecoration(
          color: _headerSurface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox.expand(),
      );

  Widget _cornerCell(int count, _GridMetrics m) {
    return Container(
      width: m.nameWidth,
      height: m.headerHeight,
      padding: EdgeInsets.symmetric(horizontal: m.showAvatar ? 18 : 12),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'Student',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateHeader(_GridMetrics m) {
    return Container(
      width: m.rateWidth,
      height: m.headerHeight,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(
          left: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Tooltip(
        message: 'Share of recorded days attended in ${_periodLabel(_selectedPeriod)}',
        child: Text(
          m.showRateBar ? 'Attendance' : 'Rate',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _nameCell(StudentModel s, _GridMetrics m) {
    final low = _isLow(s.id);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.showAvatar ? 16 : 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: _gridLine),
        ),
      ),
      child: Row(
        children: [
          if (m.showAvatar) ...[
            _Avatar(name: s.name, size: 34, warning: low),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.showAvatar ? 14 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (low && !m.showAvatar) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger),
                    ],
                  ],
                ),
                if (s.studentNumber.isNotEmpty)
                  Text(
                    s.studentNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridFooter(bool isTablet, bool isDesktop) {
    final hint = isTablet
        ? 'Click a cell to change its status. Right-click to add remarks.'
            '${isDesktop ? ' With a cell focused, press P, A, L or E.' : ''}'
        : 'Tap a cell to change its status. Long-press to add remarks.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 12, vertical: 10),
      decoration: const BoxDecoration(
        color: _headerSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          if (!isDesktop) const _Legend(),
          Text(hint, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_done_outlined, size: 15, color: AppColors.success),
              SizedBox(width: 6),
              Text(
                'Changes save automatically',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateHeaderCell extends StatelessWidget {
  final DateTime date;
  final double width;
  final bool isToday;
  final bool isHoliday;
  final double completion;
  final VoidCallback onTap;

  const _DateHeaderCell({
    required this.date,
    required this.width,
    required this.isToday,
    required this.isHoliday,
    required this.completion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isToday
        ? AppColors.primaryLight
        : (isHoliday ? AppColors.goldLight : _headerSurface);

    return Tooltip(
      message: isToday ? 'Today. Click for day options.' : 'Options for ${_shortDate(date)}',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.primary.withValues(alpha: 0.06),
          child: Container(
            width: width,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: _gridLine),
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isToday ? 'Today' : _weekdaysShort[date.weekday - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isToday ? AppColors.primary : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _shortDate(date),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isToday ? AppColors.primaryDark : AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (isHoliday)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.event_busy_rounded, size: 12, color: AppColors.warning),
                        ),
                    ],
                  ),
                ),
                if (isToday)
                  const Positioned(
                    top: 0,
                    left: 10,
                    right: 10,
                    child: SizedBox(
                      height: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: AppMotion.base,
                      curve: AppMotion.curve,
                      height: 2,
                      width: width * completion.clamp(0.0, 1.0),
                      color: AppColors.primary.withValues(alpha: 0.55),
                    ),
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

class _StatusCell extends StatelessWidget {
  final double width;
  final AttendanceRecord? record;
  final bool isToday;
  final bool isHoliday;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback onDetails;
  final void Function(AttendanceStatus? status) onKey;

  const _StatusCell({
    required this.width,
    required this.record,
    required this.isToday,
    required this.isHoliday,
    required this.semanticLabel,
    required this.onTap,
    required this.onDetails,
    required this.onKey,
  });

  static final Map<LogicalKeyboardKey, AttendanceStatus> _keys = {
    LogicalKeyboardKey.keyP: AttendanceStatus.present,
    LogicalKeyboardKey.keyA: AttendanceStatus.absent,
    LogicalKeyboardKey.keyL: AttendanceStatus.late,
    LogicalKeyboardKey.keyE: AttendanceStatus.excused,
  };

  @override
  Widget build(BuildContext context) {
    final status = record?.status;
    final style = status == null ? null : _styleOf(status);
    final hasRemarks = record?.remarks != null && record!.remarks!.trim().isNotEmpty;
    final columnTint = isToday
        ? AppColors.primaryLight.withValues(alpha: 0.45)
        : (isHoliday ? AppColors.goldLight.withValues(alpha: 0.6) : Colors.transparent);

    Widget chip = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      width: 36,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style?.background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: style == null ? AppColors.border : style.color.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Text(
          style?.abbrev ?? '',
          key: ValueKey(status),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: style?.color,
          ),
        ),
      ),
    );

    if (hasRemarks) {
      chip = Tooltip(
        message: record!.remarks!,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            chip,
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$semanticLabel: ${style?.label ?? 'not marked'}'
          '${hasRemarks ? ', remarks: ${record!.remarks}' : ''}',
      hint: 'Tap to change status',
      excludeSemantics: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (_keys.containsKey(key)) {
            onKey(_keys[key]);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
            onKey(null);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: columnTint,
          child: InkWell(
            onTap: onTap,
            onLongPress: onDetails,
            onSecondaryTap: onDetails,
            hoverColor: AppColors.primary.withValues(alpha: 0.05),
            focusColor: AppColors.primary.withValues(alpha: 0.12),
            splashColor: AppColors.primary.withValues(alpha: 0.10),
            child: Container(
              width: width,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: _gridLine)),
              ),
              child: chip,
            ),
          ),
        ),
      ),
    );
  }
}

class _RateCell extends StatelessWidget {
  final double? pct;
  final _GridMetrics metrics;

  const _RateCell({required this.pct, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final value = pct;
    final text = Text(
      value == null ? '—' : '${value.toStringAsFixed(0)}%',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: value == null ? AppColors.textMuted : _rateColor(value),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.showRateBar ? 16 : 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: _gridLine)),
      ),
      alignment: metrics.showRateBar ? Alignment.center : Alignment.centerRight,
      child: !metrics.showRateBar
          ? text
          : Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Stack(
                      children: [
                        Container(height: 6, color: _gridLine),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ((value ?? 0) / 100).clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            color: value == null ? Colors.transparent : _rateColor(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 40, child: text),
              ],
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
                    child: _PeriodSegment(
                      label: _periodLabel(p),
                      count: counts[p] ?? 0,
                      selected: p == selected,
                      onTap: () => onChanged(p),
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

class _PeriodSegment extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodSegment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$label, $count class days',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          hoverColor: selected ? Colors.transparent : AppColors.primaryLight.withValues(alpha: 0.6),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: AppMotion.base,
                  style: TextStyle(
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                  child: Text(label),
                ),
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: AppMotion.base,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.textMuted,
                    ),
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

class _ScheduleChip extends StatelessWidget {
  final ClassScheduleModel? schedule;
  final VoidCallback onTap;

  const _ScheduleChip({required this.schedule, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final configured = schedule != null && schedule!.meetingWeekdays.isNotEmpty;
    final label = configured
        ? schedule!.scheduleLabel
        : 'Set class schedule';
    final fg = configured ? AppColors.textSecondary : AppColors.warning;
    final bg = configured ? AppColors.surface : AppColors.warningBg;

    return Tooltip(
      message: configured ? 'Edit class schedule' : 'Set meeting days so class days fill in automatically',
      child: Hoverable(
        builder: (context, hovered) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: hovered
                      ? (configured ? AppColors.primary : AppColors.warning)
                      : (configured ? AppColors.border : AppColors.warning.withValues(alpha: 0.35)),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    configured ? Icons.schedule_rounded : Icons.event_note_outlined,
                    size: 16,
                    color: fg,
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
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

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String label;
  final String value;
  final String caption;
  final double? progress;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
    required this.value,
    required this.caption,
    this.progress,
    this.selected = false,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      enableCursor: onTap != null,
      builder: (context, hovered) {
        final active = onTap != null && hovered;
        return AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: selected ? AppColors.dangerBg : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.danger.withValues(alpha: 0.55)
                  : (active ? AppColors.textMuted.withValues(alpha: 0.6) : AppColors.border),
              width: 1.2,
            ),
            boxShadow: active ? AppShadows.lifted : AppShadows.card,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            color: progress != null || onTap != null
                                ? color
                                : AppColors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress!.clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 600),
                          curve: AppMotion.curve,
                          builder: (_, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 4,
                            color: color,
                            backgroundColor: _gridLine,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      caption,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterToggle({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 || selected;
    final fg = selected
        ? AppColors.danger
        : (enabled ? AppColors.textSecondary : AppColors.textMuted.withValues(alpha: 0.7));

    return Tooltip(
      message: !enabled
          ? 'No students are below the threshold'
          : (selected ? 'Show all students' : 'Show only students below the threshold'),
      child: Semantics(
        toggled: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.dangerBg : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? AppColors.danger.withValues(alpha: 0.5) : AppColors.border,
                  width: 1.3,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
                    size: 17,
                    color: fg,
                  ),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final s in AttendanceStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _styleOf(s).background,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _styleOf(s).abbrev,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _styleOf(s).color,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _styleOf(s).label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool warning;

  const _Avatar({required this.name, required this.size, this.warning = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(name),
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          if (warning)
            Positioned(
              right: -2,
              bottom: -2,
              child: Tooltip(
                message: 'Below ${_lowThreshold.toStringAsFixed(0)}% attendance',
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: const Icon(Icons.priority_high_rounded, size: 9, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoDatesState extends StatelessWidget {
  final String period;
  final bool hasSchedule;
  final bool periodHasRange;
  final bool wide;
  final VoidCallback onSchedule;
  final VoidCallback onAddDate;

  const _NoDatesState({
    required this.period,
    required this.hasSchedule,
    required this.periodHasRange,
    required this.wide,
    required this.onSchedule,
    required this.onAddDate,
  });

  @override
  Widget build(BuildContext context) {
    final String title;
    final String message;
    final String scheduleTitle;
    final String scheduleDesc;

    if (!hasSchedule) {
      title = 'No class days in $period yet';
      message = 'Set your meeting days once and every class day for the term appears '
          'here automatically. For a one-off session, add a single date instead.';
      scheduleTitle = 'Set up class schedule';
      scheduleDesc = 'Fills in every meeting day for Prelim, Midterm and Finals';
    } else if (!periodHasRange) {
      title = '$period dates aren’t set yet';
      message = 'Your meeting days are saved, but $period has no start and end date. '
          'Add them and the class days will fill in automatically.';
      scheduleTitle = 'Set $period dates';
      scheduleDesc = 'Pick when $period starts and ends';
    } else {
      title = 'No class days in $period';
      message = 'None of your meeting days fall inside the $period date range. '
          'Check the schedule, or add a date manually.';
      scheduleTitle = 'Review class schedule';
      scheduleDesc = 'Check meeting days and the $period date range';
    }

    final primary = _OptionCard(
      icon: Icons.calendar_month_rounded,
      title: scheduleTitle,
      description: scheduleDesc,
      recommended: true,
      onTap: onSchedule,
    );
    final secondary = _OptionCard(
      icon: Icons.add_rounded,
      title: 'Add a single date',
      description: 'For make-up classes or extra sessions',
      onTap: onAddDate,
    );

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CalendarGlyph(),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: wide ? 22 : 19),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: primary),
                      const SizedBox(width: 12),
                      Expanded(child: secondary),
                    ],
                  ),
                )
              else ...[
                primary,
                const SizedBox(height: 10),
                secondary,
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 260.ms);
  }
}

class _CalendarGlyph extends StatelessWidget {
  const _CalendarGlyph();

  @override
  Widget build(BuildContext context) {
    const rows = 4;
    const cols = 7;
    const cell = 13.0;
    const gap = 5.0;

    bool isMeeting(int c) => c == 0 || c == 2;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                SizedBox(
                  width: cell,
                  child: Text(
                    'MTWTFSS'[c],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: isMeeting(c) ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  (() {
                    final box = Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        color: isMeeting(c) ? AppColors.primary : AppColors.background,
                        borderRadius: BorderRadius.circular(4),
                        border: isMeeting(c) ? null : Border.all(color: AppColors.border),
                      ),
                    );
                    if (!isMeeting(c)) return box;
                    final i = r * 2 + (c == 0 ? 0 : 1);
                    return box
                        .animate()
                        .fadeIn(delay: (220 + i * 70).ms, duration: 240.ms)
                        .scale(begin: const Offset(0.5, 0.5), curve: Curves.easeOutBack);
                  })(),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool recommended;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: recommended ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: recommended
                ? AppColors.primary
                : (hovered ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
            width: 1.3,
          ),
          boxShadow: hovered ? AppShadows.lifted : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            focusColor: recommended
                ? Colors.white.withValues(alpha: 0.12)
                : AppColors.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: recommended
                          ? Colors.white.withValues(alpha: 0.16)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon,
                        size: 21, color: recommended ? Colors.white : AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: recommended ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            if (recommended)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: const Text(
                                  'Recommended',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandBlack,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: recommended
                                ? Colors.white.withValues(alpha: 0.82)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSlide(
                    duration: AppMotion.fast,
                    offset: Offset(hovered ? 0.15 : 0, 0),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: recommended ? Colors.white : AppColors.textMuted,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
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
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onPrimary,
                icon: Icon(primaryIcon, size: 18),
                label: Text(primaryLabel),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tile()),
        ],
      ],
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  final _GridMetrics metrics;

  const _GridSkeleton({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: metrics.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: _headerSurface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              SizedBox(width: metrics.nameWidth - 32, child: const Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 80, height: 14),
              )),
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Row(
                      children: [
                        for (var i = 0; i < 14; i++)
                          SizedBox(
                            width: metrics.dateWidth,
                            child: const Center(child: SkeletonBox(width: 40, height: 22, radius: 6)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            itemExtent: metrics.rowHeight,
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _gridLine)),
              ),
              child: Row(
                children: [
                  if (metrics.showAvatar) ...[
                    const SkeletonBox(width: 34, height: 34, radius: 17),
                    const SizedBox(width: 12),
                  ],
                  SkeletonBox(width: metrics.showAvatar ? 150.0 - (i % 3) * 22 : 80, height: 13),
                  const Spacer(),
                  SkeletonBox(width: metrics.showAvatar ? 90 : 36, height: 10),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<T?> _showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 480,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: AppColors.brandBlack.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) {
      final insets = MediaQuery.viewInsetsOf(ctx);
      return SafeArea(
        child: AnimatedPadding(
          duration: AppMotion.fast,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: AppColors.surface,
                elevation: 0,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(child: builder(ctx)),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DialogFrame extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  const _DialogFrame({
    this.icon,
    this.iconColor,
    this.iconBackground,
    this.leading,
    required this.title,
    this.subtitle,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ??
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconBackground ?? AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 20),
                style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          body,
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      );
}

class _StatusOption extends StatelessWidget {
  final AttendanceStatus status;
  final bool selected;
  final VoidCallback? onTap;

  const _StatusOption({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _styleOf(status);
    return Semantics(
      selected: selected,
      button: true,
      label: s.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? s.background : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? s.color : AppColors.border,
                width: selected ? 1.8 : 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.icon, size: 20, color: selected ? s.color : AppColors.textMuted),
                const SizedBox(height: 4),
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? s.color : AppColors.textSecondary,
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

class _CountPill extends StatelessWidget {
  final _StatusStyle style;
  final int count;

  const _CountPill({required this.style, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: count == 0 ? AppColors.background : style.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: style.color.withValues(alpha: 0.25)),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: style.color),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: count == 0 ? AppColors.textMuted : style.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  const _SheetAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: destructive ? AppColors.danger : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
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

class _FinalizedChip extends StatelessWidget {
  const _FinalizedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.warning),
          SizedBox(width: 6),
          Text(
            'Finalized',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedAttendanceBanner extends StatelessWidget {
  final String period;

  const _LockedAttendanceBanner({required this.period});

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
              '$period is finalized, so attendance here is read-only. Reopen the period from '
              'the grades page if you still need to change a mark.',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineLockNote extends StatelessWidget {
  final String period;

  const _InlineLockNote({required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$period is finalized. Reopen it on the grades page to make changes.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}