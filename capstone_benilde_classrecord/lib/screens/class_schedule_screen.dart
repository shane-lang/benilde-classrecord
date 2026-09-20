import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assessment_model.dart';
import '../models/class_model.dart';
import '../models/class_schedule_model.dart';
import '../services/api_exception.dart';
import '../services/class_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const double _wideBreakpoint = 1000;
const double _tabletBreakpoint = 760;

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _fmt(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';
String _fmtShort(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

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

String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

class _DayPreset {
  final String label;
  final Set<int> days;
  const _DayPreset(this.label, this.days);
}

const List<_DayPreset> _dayPresets = [
  _DayPreset('Mon, Wed, Fri', {1, 3, 5}),
  _DayPreset('Tue, Thu', {2, 4}),
  _DayPreset('Weekdays', {1, 2, 3, 4, 5}),
  _DayPreset('Saturday', {6}),
];

const List<int> _durationPresets = [60, 90, 120, 180];

class ClassScheduleScreen extends StatefulWidget {
  final ClassModel classModel;

  const ClassScheduleScreen({super.key, required this.classModel});

  @override
  State<ClassScheduleScreen> createState() => _ClassScheduleScreenState();
}

class _ClassScheduleScreenState extends State<ClassScheduleScreen> {
  late Set<int> _days;
  late int _startHour;
  late int _startMinute;
  late int _duration;

  late Map<int, DayTime> _dayTimes;
  late Map<GradingPeriod, PeriodDateRange> _ranges;
  bool _dirty = false;
  bool _saving = false;

  final _daysKey = GlobalKey();
  final _timeKey = GlobalKey();
  final _periodsKey = GlobalKey();

  late DateTime _previewMonth;

  ClassScheduleModel? get _existing => widget.classModel.schedule;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _days = {...?e?.meetingWeekdays};
    _startHour = e?.startHour ?? 8;
    _startMinute = e?.startMinute ?? 0;
    _duration = e?.durationMinutes ?? 90;
    _dayTimes = {...?e?.dayTimes};
    _ranges = {
      for (final entry in (e?.periodRanges ?? {}).entries)
        entry.key: PeriodDateRange(start: entry.value.start, end: entry.value.end),
    };
    final firstStart = _ranges[GradingPeriod.prelim]?.start;
    final now = DateTime.now();
    _previewMonth = DateTime((firstStart ?? now).year, (firstStart ?? now).month);
  }

  bool get _daysDone => _days.isNotEmpty;

  String? _periodIssue(GradingPeriod p) {
    final r = _ranges[p];
    if (r == null) return null;
    if (r.end.isBefore(r.start)) return 'End date is before the start date';
    final i = GradingPeriod.values.indexOf(p);
    if (i > 0) {
      final prev = GradingPeriod.values[i - 1];
      final pr = _ranges[prev];
      if (pr != null && !_day(r.start).isAfter(_day(pr.end))) {
        return 'Starts before ${_periodLabel(prev)} ends (${_fmtShort(pr.end)})';
      }
    }
    return null;
  }

  bool get _periodsDone => GradingPeriod.values
      .every((p) => _ranges[p] != null && _periodIssue(p) == null);

  bool get _complete => _daysDone && _periodsDone;

  int get _stepsDone => (_daysDone ? 1 : 0) + 1 + (_periodsDone ? 1 : 0);

  List<String> get _missing {
    final list = <String>[];
    if (!_daysDone) list.add('meeting days');
    for (final p in GradingPeriod.values) {
      if (_ranges[p] == null) {
        list.add('${_periodLabel(p)} dates');
      } else if (_periodIssue(p) != null) {
        list.add('fix ${_periodLabel(p)} dates');
      }
    }
    return list;
  }

  ClassScheduleModel get _draft => ClassScheduleModel(
        meetingWeekdays: {..._days},
        startHour: _startHour,
        startMinute: _startMinute,
        durationMinutes: _duration,
        dayTimes: {

          for (final entry in _dayTimes.entries)
            if (_days.contains(entry.key)) entry.key: entry.value,
        },
        periodRanges: {..._ranges},
        holidayDates: {...?_existing?.holidayDates},
        holidayReasons: {...?_existing?.holidayReasons},
      );

  TimeOfDay get _start => TimeOfDay(hour: _startHour, minute: _startMinute);
  TimeOfDay get _end {
    final total = _startHour * 60 + _startMinute + _duration;
    return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
  }

  DayTime get _defaultTime => DayTime(
        startHour: _startHour,
        startMinute: _startMinute,
        durationMinutes: _duration,
      );

  bool get _perDay => _days.any((d) => _dayTimes.containsKey(d));

  DayTime _timeOf(int weekday) => _dayTimes[weekday] ?? _defaultTime;

  List<int> get _sortedDays => _days.toList()..sort();

  void _change(VoidCallback fn) {
    setState(() {
      fn();
      _dirty = true;
    });
  }

  void _toggleDay(int weekday) {
    HapticFeedback.selectionClick();
    _change(() {
      if (!_days.remove(weekday)) _days.add(weekday);
    });
  }

  bool get _isPreset => _dayPresets
      .any((p) => p.days.length == _days.length && p.days.containsAll(_days));

  String _daysLabel() {
    final sorted = _days.toList()..sort();
    return sorted.map((d) => _weekdayShort[d - 1]).join(', ');
  }

  void _applyPreset(Set<int> days) {
    HapticFeedback.selectionClick();
    _change(() => _days = {...days});
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start,
      helpText: 'Class starts at',
    );
    if (picked == null) return;
    _change(() {
      _startHour = picked.hour;
      _startMinute = picked.minute;
    });
  }

  void _setPerDay(bool on) {
    HapticFeedback.selectionClick();
    _change(() {
      if (on) {
        for (final d in _days) {
          _dayTimes[d] = _dayTimes[d] ?? _defaultTime;
        }
      } else {
        _dayTimes.clear();
      }
    });
  }

  Future<void> _pickDayTime(int weekday) async {
    final current = _timeOf(weekday);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.startHour, minute: current.startMinute),
      helpText: '${_weekdayLong[weekday - 1]} starts at',
    );
    if (picked == null) return;
    _change(() {
      _dayTimes[weekday] = current.copyWith(
        startHour: picked.hour,
        startMinute: picked.minute,
      );
    });
  }

  void _changeDayDuration(int weekday, int minutes) {
    final clamped = minutes.clamp(15, 300);
    _change(() {
      _dayTimes[weekday] = _timeOf(weekday).copyWith(durationMinutes: clamped);
    });
  }

  Future<void> _pickRange(GradingPeriod p, {DateTime? suggestedStart}) async {
    final existing = _ranges[p];
    final first = DateTime(2024);
    final last = DateTime(2030, 12, 31);
    DateTimeRange? initial;
    if (existing != null && !existing.end.isBefore(existing.start)) {
      initial = DateTimeRange(start: existing.start, end: existing.end);
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
      currentDate: suggestedStart,
      helpText: '${_periodLabel(p)} dates',
      saveText: 'Set dates',
      fieldStartLabelText: 'Starts',
      fieldEndLabelText: 'Ends',
      builder: (context, child) {

        final wide = MediaQuery.sizeOf(context).width >= _tabletBreakpoint;
        if (!wide) return child!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: child,
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    _change(() => _ranges[p] = PeriodDateRange(start: _day(picked.start), end: _day(picked.end)));
    setState(() => _previewMonth = DateTime(picked.start.year, picked.start.month));
  }

  DateTimeRange? _suggestionFor(GradingPeriod p) {
    final i = GradingPeriod.values.indexOf(p);
    if (i == 0 || _ranges[p] != null) return null;
    final prev = _ranges[GradingPeriod.values[i - 1]];
    if (prev == null || prev.end.isBefore(prev.start)) return null;
    final start = _day(prev.end).add(const Duration(days: 1));
    final length = _day(prev.end).difference(_day(prev.start)).inDays;
    return DateTimeRange(start: start, end: start.add(Duration(days: length)));
  }

  void _applySuggestion(GradingPeriod p, DateTimeRange r) {
    HapticFeedback.selectionClick();
    _change(() => _ranges[p] = PeriodDateRange(start: r.start, end: r.end));
    AppToast.show(
      context,
      '${_periodLabel(p)} set to ${_fmtShort(r.start)} – ${_fmtShort(r.end)}',
      type: ToastType.success,
      actionLabel: 'Undo',
      onAction: () => setState(() => _ranges.remove(p)),
    );
  }

  void _clearRange(GradingPeriod p) {
    final removed = _ranges[p];
    if (removed == null) return;
    _change(() => _ranges.remove(p));
    AppToast.show(
      context,
      'Cleared ${_periodLabel(p)} dates',
      actionLabel: 'Undo',
      onAction: () => setState(() => _ranges[p] = removed),
    );
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: AppMotion.curve,
      alignment: 0.05,
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!_daysDone) {
      HapticFeedback.mediumImpact();
      AppToast.show(context, 'Pick at least one meeting day.', type: ToastType.error);
      _scrollTo(_daysKey);
      return;
    }
    for (final p in GradingPeriod.values) {
      if (_ranges[p] == null) {
        HapticFeedback.mediumImpact();
        AppToast.show(context, 'Set the ${_periodLabel(p)} start and end dates.',
            type: ToastType.error);
        _scrollTo(_periodsKey);
        return;
      }
      final issue = _periodIssue(p);
      if (issue != null) {
        HapticFeedback.mediumImpact();
        AppToast.show(context, '${_periodLabel(p)}: $issue.', type: ToastType.error);
        _scrollTo(_periodsKey);
        return;
      }
    }

    setState(() => _saving = true);

    try {

      final saved = await ClassRepository.instance
          .saveSchedule(widget.classModel.id, _draft);
      if (!mounted) return;

      widget.classModel.schedule = saved;
      final total = GradingPeriod.values
          .fold<int>(0, (sum, p) => sum + saved.classDatesFor(p).length);

      HapticFeedback.lightImpact();
      _dirty = false;
      AppToast.show(
        context,
        'Schedule saved. $total class days are ready in Attendance.',
        type: ToastType.success,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      HapticFeedback.mediumImpact();
      AppToast.show(
        context,
        switch (e) {
          ApiException err => err.message,
          NetworkException err => err.message,
          _ => 'Couldn’t save the schedule. Try again.',
        },
        type: ToastType.error,
      );
    }
  }

  Future<void> _confirmLeave() async {
    final discard = await showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your schedule changes haven’t been saved yet.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
      icon: Icons.edit_off_outlined,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _wideBreakpoint;
    final tablet = width >= _tabletBreakpoint;
    final hPad = wide ? 32.0 : (tablet ? 24.0 : 16.0);
    final draft = _draft;

    final form = <Widget>[
      _intro(tablet),
      const SizedBox(height: 20),
      _daysSection(tablet),
      const SizedBox(height: 16),
      _timeSection(tablet),
      const SizedBox(height: 16),
      _periodsSection(tablet),
    ];

    final preview = _PreviewPanel(
      schedule: draft,
      days: _days,
      start: _start,
      end: _end,
      month: _previewMonth,
      onMonthChanged: (m) => setState(() => _previewMonth = m),
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: _appBar(),
        bottomNavigationBar: _bottomBar(draft, tablet),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(hPad, 24, 12, 32),
                          children: form,
                        ),
                      ),
                      SizedBox(
                        width: 360,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(12, 24, hPad, 32),
                          child: preview,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(hPad, tablet ? 24 : 16, hPad, 32),
                    children: [
                      ...form,
                      const SizedBox(height: 16),
                      preview,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final c = widget.classModel;
    final subtitle = c.subjectCode.isNotEmpty ? '${c.subjectCode}  ${c.subjectName}' : c.subjectName;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 4,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Class schedule',
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
    );
  }

  Widget _intro(bool tablet) {
    final steps = [
      ('Meeting days', _daysDone, _daysKey),
      ('Class time', true, _timeKey),
      ('Grading periods', _periodsDone, _periodsKey),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set it once, attendance fills itself in',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: tablet ? 24 : 20),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Choose when the class meets and when each grading period runs. '
            'Every class day then appears in Attendance automatically.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++)
              _StepPill(
                number: i + 1,
                label: steps[i].$1,
                done: steps[i].$2,
                onTap: () => _scrollTo(steps[i].$3),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '$_stepsDone of 3 done',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _daysSection(bool tablet) {
    return _SectionCard(
      key: _daysKey,
      step: 1,
      done: _daysDone,
      title: 'Meeting days',
      subtitle: 'Tap each day the class meets. Any combination works, for example Mon, Thu, Sat.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            const gap = 8.0;
            final w = ((c.maxWidth - gap * 6) / 7).clamp(36.0, 72.0);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var d = 1; d <= 7; d++)
                  _DayToggle(
                    label: _weekdayShort[d - 1],
                    width: w,
                    selected: _days.contains(d),
                    onTap: () => _toggleDay(d),
                  ),
              ],
            );
          }),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Common patterns',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
              for (final p in _dayPresets)
                _ChoicePill(
                  label: p.label,
                  selected: _days.length == p.days.length && _days.containsAll(p.days),
                  onTap: () => _applyPreset(p.days),
                ),
              if (_days.isNotEmpty)
                _ChoicePill(
                  label: 'Clear',
                  selected: false,
                  onTap: () => _applyPreset(const <int>{}),
                ),
            ],
          ),
          if (_days.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InlineNote(
              icon: _isPreset ? Icons.event_repeat_rounded : Icons.tune_rounded,
              color: AppColors.primary,
              text: _isPreset
                  ? 'Meets every ${_daysLabel()}.'
                  : 'Your own combination: ${_daysLabel()}.',
            ),
          ],
          if (!_daysDone) ...[
            const SizedBox(height: 12),
            const _InlineNote(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              text: 'Pick at least one day.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeSection(bool tablet) {
    final startField = _FieldButton(
      icon: Icons.schedule_rounded,
      label: 'Starts at',
      value: _start.format(context),
      onTap: _pickTime,
    );
    final endField = _FieldButton(
      icon: Icons.flag_outlined,
      label: 'Ends at',
      value: _end.format(context),
      readOnly: true,
    );

    return _SectionCard(
      key: _timeKey,
      step: 2,
      done: true,
      title: 'Class time',
      subtitle: 'When each session starts and how long it runs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _TimeModeChoice(
            perDay: _perDay,
            dayCount: _days.length,
            onChanged: _setPerDay,
          ),
          const SizedBox(height: 16),
          if (!_perDay) ...[
            Row(
              children: [
                Expanded(child: startField),
                const SizedBox(width: 10),
                Expanded(child: endField),
              ],
            ),
            const SizedBox(height: 16),
            const _SubLabel('Length'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final m in _durationPresets)
                  _ChoicePill(
                    label: _durationLabel(m),
                    selected: _duration == m,
                    onTap: () => _change(() => _duration = m),
                  ),
                _Stepper(
                  value: _durationLabel(_duration),
                  highlighted: !_durationPresets.contains(_duration),
                  onMinus: _duration > 15 ? () => _change(() => _duration -= 15) : null,
                  onPlus: _duration < 300 ? () => _change(() => _duration += 15) : null,
                ),
              ],
            ),
          ] else if (_days.isEmpty)
            const _InlineNote(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              text: 'Pick your meeting days first, then set a time for each one.',
            )
          else
            Column(
              children: [
                for (final d in _sortedDays) ...[
                  if (d != _sortedDays.first) const SizedBox(height: 10),
                  _DayTimeRow(
                    weekday: d,
                    time: _timeOf(d),
                    compact: !tablet,
                    onPickTime: () => _pickDayTime(d),
                    onMinus: _timeOf(d).durationMinutes > 15
                        ? () => _changeDayDuration(d, _timeOf(d).durationMinutes - 15)
                        : null,
                    onPlus: _timeOf(d).durationMinutes < 300
                        ? () => _changeDayDuration(d, _timeOf(d).durationMinutes + 15)
                        : null,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _periodsSection(bool tablet) {
    return _SectionCard(
      key: _periodsKey,
      step: 3,
      done: _periodsDone,
      title: 'Grading periods',
      subtitle: 'The start and end of each period. Finals ends the class year.',
      child: Column(
        children: [
          for (final p in GradingPeriod.values) ...[
            if (p != GradingPeriod.prelim) const SizedBox(height: 10),
            _PeriodRow(
              label: _periodLabel(p),
              range: _ranges[p],
              issue: _periodIssue(p),
              classDays: _ranges[p] == null || _periodIssue(p) != null
                  ? null
                  : _draft.classDatesFor(p).length,
              daysChosen: _daysDone,
              suggestion: _suggestionFor(p),
              suggestionFrom: p == GradingPeriod.prelim
                  ? null
                  : _periodLabel(GradingPeriod.values[GradingPeriod.values.indexOf(p) - 1]),
              compact: !tablet,
              onPick: () => _pickRange(p),
              onClear: () => _clearRange(p),
              onApplySuggestion: (r) => _applySuggestion(p, r),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(ClassScheduleModel draft, bool tablet) {
    final total = _complete
        ? GradingPeriod.values.fold<int>(0, (s, p) => s + draft.classDatesFor(p).length)
        : 0;
    final missing = _missing;

    final status = Row(
      children: [
        Icon(
          _complete ? Icons.check_circle_rounded : Icons.pending_outlined,
          size: 18,
          color: _complete ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _complete
                ? 'Ready. $total class days across 3 grading periods.'
                : 'Still needed: ${missing.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _complete ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );

    final save = ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : const Icon(Icons.check_rounded, size: 20),
      label: Text(_saving ? 'Saving…' : 'Save schedule'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlack.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,

        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tablet ? 32 : 16, vertical: 12),
              child: tablet
                  ? Row(
                      children: [
                        Expanded(child: status),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        save,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        status,
                        const SizedBox(height: 10),
                        save,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final int step;
  final bool done;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    super.key,
    required this.step,
    required this.done,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepBadge(number: step, done: done),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final int number;
  final bool done;

  const _StepBadge({required this.number, required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.primary : AppColors.surface,
        border: Border.all(color: done ? AppColors.primary : AppColors.border, width: 1.5),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.base,
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: done
            ? const Icon(Icons.check_rounded, key: ValueKey('done'), size: 16, color: Colors.white)
            : Text(
                '$number',
                key: const ValueKey('num'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final int number;
  final String label;
  final bool done;
  final VoidCallback onTap;

  const _StepPill({required this.number, required this.label, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: AppMotion.base,
          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
          decoration: BoxDecoration(
            color: done ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: done ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.primary : AppColors.background,
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                    : Text('$number',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: done ? AppColors.primaryDark : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String label;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  const _DayToggle({required this.label, required this.width, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Hoverable(
        builder: (context, hovered) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.curve,
              width: width,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : (hovered ? AppColors.primaryLight : AppColors.surface),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : (hovered ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
                  width: 1.3,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          hoverColor: AppColors.primaryLight.withValues(alpha: 0.6),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1.2,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? AppColors.primaryDark : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String value;
  final bool highlighted;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _Stepper({required this.value, required this.highlighted, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap, String tip) => IconButton(
          onPressed: onTap,
          tooltip: tip,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textMuted.withValues(alpha: 0.5),
          ),
        );

    return AnimatedContainer(
      duration: AppMotion.fast,
      height: 38,
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: highlighted ? AppColors.primary : AppColors.border,
          width: highlighted ? 1.5 : 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, onMinus, '15 minutes shorter'),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 84),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: highlighted ? AppColors.primaryDark : AppColors.textPrimary,
              ),
            ),
          ),
          btn(Icons.add_rounded, onPlus, '15 minutes longer'),
        ],
      ),
    );
  }
}

class _FieldButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool readOnly;

  const _FieldButton({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      enableCursor: !readOnly,
      builder: (context, hovered) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: readOnly ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: readOnly ? AppColors.background : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: !readOnly && hovered ? AppColors.primary : AppColors.border,
                width: 1.3,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: readOnly ? AppColors.textMuted : AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 1),
                      Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: readOnly ? AppColors.textSecondary : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!readOnly)
                  const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final String label;
  final PeriodDateRange? range;
  final String? issue;
  final int? classDays;
  final bool daysChosen;
  final DateTimeRange? suggestion;
  final String? suggestionFrom;
  final bool compact;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<DateTimeRange> onApplySuggestion;

  const _PeriodRow({
    required this.label,
    required this.range,
    required this.issue,
    required this.classDays,
    required this.daysChosen,
    required this.suggestion,
    required this.suggestionFrom,
    required this.compact,
    required this.onPick,
    required this.onClear,
    required this.onApplySuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final r = range;
    final hasError = issue != null;
    final isSet = r != null && !hasError;

    final Widget badge;
    if (hasError) {
      badge = const StatusBadge(
        label: 'Needs fixing',
        color: AppColors.danger,
        background: AppColors.dangerBg,
        icon: Icons.error_outline_rounded,
      );
    } else if (isSet) {
      badge = StatusBadge(
        label: daysChosen ? '$classDays class days' : '${r.end.difference(r.start).inDays + 1} days',
        color: AppColors.success,
        background: AppColors.successBg,
      );
    } else {
      badge = const StatusBadge(
        label: 'Not set',
        color: AppColors.warning,
        background: AppColors.warningBg,
      );
    }

    final rangeButton = Hoverable(
      builder: (context, hovered) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: hasError
                  ? AppColors.dangerBg
                  : (isSet ? AppColors.surface : AppColors.background),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: hasError
                    ? AppColors.danger
                    : (hovered ? AppColors.primary : AppColors.border),
                width: 1.3,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.date_range_rounded,
                  size: 19,
                  color: hasError ? AppColors.danger : (r != null ? AppColors.primary : AppColors.textMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: r == null
                      ? const Text(
                          'Choose start and end dates',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(_fmt(r.start), style: _dateStyle(hasError)),
                            const Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.textMuted),
                            Text(_fmt(r.end), style: _dateStyle(hasError)),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  r == null ? 'Set' : 'Change',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: AppMotion.base,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasError ? AppColors.dangerBg.withValues(alpha: 0.5) : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: hasError ? AppColors.danger.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 10),
              badge,
              const Spacer(),
              if (r != null)
                IconButton(
                  onPressed: onClear,
                  tooltip: 'Clear $label dates',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: IconButton.styleFrom(minimumSize: const Size(34, 34)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          rangeButton,
          if (hasError) ...[
            const SizedBox(height: 8),
            _InlineNote(icon: Icons.error_outline_rounded, color: AppColors.danger, text: '$issue.'),
          ],
          if (suggestion != null) ...[
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onApplySuggestion(suggestion!),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.goldLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 17, color: AppColors.goldDark),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use ${_fmtShort(suggestion!.start)} – ${_fmt(suggestion!.end)}, '
                          'right after $suggestionFrom with the same length',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandBlack,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Apply',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldDark),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _dateStyle(bool error) => TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: error ? AppColors.danger : AppColors.textPrimary,
      );
}

class _InlineNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InlineNote({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

class _SubLabel extends StatelessWidget {
  final String text;

  const _SubLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      );
}

class _PreviewPanel extends StatelessWidget {
  final ClassScheduleModel schedule;
  final Set<int> days;
  final TimeOfDay start;
  final TimeOfDay end;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  const _PreviewPanel({
    required this.schedule,
    required this.days,
    required this.start,
    required this.end,
    required this.month,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final perPeriod = {
      for (final p in GradingPeriod.values) p: schedule.classDatesFor(p),
    };
    final classDates = <DateTime>{for (final list in perPeriod.values) ...list};
    final total = classDates.length;
    final sortedDays = days.toList()..sort();

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

          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: total.toDouble()),
                  duration: const Duration(milliseconds: 450),
                  curve: AppMotion.curve,
                  builder: (_, v, _) => Text(
                    total == 0 ? 'No class days yet' : '${v.round()} class days',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sortedDays.isEmpty
                      ? 'Pick meeting days to see them here'
                      : (schedule.hasPerDayTimes

                          ? schedule.scheduleLabel
                          : '${sortedDays.map((d) => _weekdayShort[d - 1]).join(', ')}, '
                              '${start.format(context)} to ${end.format(context)}'),
                  style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Column(
              children: [
                for (final p in GradingPeriod.values)
                  _PreviewPeriodLine(
                    label: _periodLabel(p),
                    range: schedule.periodRanges[p],
                    count: perPeriod[p]!.length,
                  ),
              ],
            ),
          ),
          const Divider(height: 24, indent: 20, endIndent: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: _MiniMonth(
              month: month,
              classDates: classDates,
              holidays: schedule.holidayDates,
              onChanged: onMonthChanged,
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            color: AppColors.background,
            child: const Text(
              'You can still add or remove single days, and mark no-class days, from Attendance.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPeriodLine extends StatelessWidget {
  final String label;
  final PeriodDateRange? range;
  final int count;

  const _PreviewPeriodLine({required this.label, required this.range, required this.count});

  @override
  Widget build(BuildContext context) {
    final r = range;
    final valid = r != null && !r.end.isBefore(r.start);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: valid ? AppColors.primary : AppColors.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(
                  valid ? '${_fmtShort(r.start)} to ${_fmt(r.end)}' : 'Dates not set',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            valid ? '$count' : '—',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valid ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  final DateTime month;
  final Set<DateTime> classDates;
  final Set<DateTime> holidays;
  final ValueChanged<DateTime> onChanged;

  const _MiniMonth({
    required this.month,
    required this.classDates,
    required this.holidays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = _day(DateTime.now());
    final inMonth = classDates.where((d) => d.year == month.year && d.month == month.month).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_monthsLong[month.month - 1]} ${month.year}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  Text(
                    inMonth == 0 ? 'No class days this month' : '$inMonth class days this month',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final w in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(w,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: AppMotion.base,
          child: Column(
            key: ValueKey(month),
            children: [
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _dayCell(r * 7 + c - leading + 1, daysInMonth, today),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            _LegendDot(color: AppColors.primary, label: 'Class day'),
            SizedBox(width: 14),
            _LegendDot(color: AppColors.gold, label: 'No-class day', outlined: true),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(int dayNum, int daysInMonth, DateTime today) {
    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
    final date = DateTime(month.year, month.month, dayNum);
    final isClass = classDates.contains(date);
    final isHoliday = holidays.contains(date);
    final isToday = date == today;

    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: AnimatedContainer(
        duration: AppMotion.base,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isClass ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
          border: isHoliday
              ? Border.all(color: AppColors.gold, width: 1.6)
              : (isToday && !isClass ? Border.all(color: AppColors.textMuted, width: 1.2) : null),
        ),
        child: Text(
          '$dayNum',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isClass || isToday ? FontWeight.w700 : FontWeight.w500,
            color: isClass ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool outlined;

  const _LegendDot({required this.color, required this.label, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: outlined ? Colors.transparent : color,
            border: outlined ? Border.all(color: color, width: 1.6) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }
}

class _TimeModeChoice extends StatelessWidget {
  final bool perDay;
  final int dayCount;
  final ValueChanged<bool> onChanged;

  const _TimeModeChoice({
    required this.perDay,
    required this.dayCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            icon: Icons.schedule_rounded,
            title: 'Same time every day',
            description: dayCount <= 1
                ? 'One start time and length'
                : 'All $dayCount days start together',
            selected: !perDay,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeCard(
            icon: Icons.more_time_rounded,
            title: 'Different per day',
            description: 'e.g. lecture Mon, lab Sat',
            selected: perDay,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1.3,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: selected ? AppColors.primary : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: selected ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.3,
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

class _DayTimeRow extends StatelessWidget {
  final int weekday;
  final DayTime time;
  final bool compact;
  final VoidCallback onPickTime;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _DayTimeRow({
    required this.weekday,
    required this.time,
    required this.compact,
    required this.onPickTime,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final name = Container(
      width: compact ? 46 : 96,
      alignment: Alignment.centerLeft,
      child: Text(
        compact ? _weekdayShort[weekday - 1] : _weekdayLong[weekday - 1],
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );

    final timeButton = Expanded(
      child: _FieldButton(
        icon: Icons.schedule_rounded,
        label: 'Starts at',
        value: time.startLabel,
        onTap: onPickTime,
      ),
    );

    final length = _Stepper(
      value: _durationLabel(time.durationMinutes),
      highlighted: false,
      onMinus: onMinus,
      onPlus: onPlus,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              name,
              const SizedBox(width: 8),
              timeButton,
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!compact) const SizedBox(width: 104),
              length,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ends ${time.endLabel}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}