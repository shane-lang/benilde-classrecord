import 'api_enums.dart';
import 'assessment_model.dart';

class PeriodDateRange {
  DateTime start;
  DateTime end;

  PeriodDateRange({required this.start, required this.end});
}

class DayTime {
  final int startHour;
  final int startMinute;
  final int durationMinutes;

  const DayTime({
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
  });

  int get startsAt => startHour * 60 + startMinute;
  int get endsAt => startsAt + durationMinutes;

  String get startLabel => _clock(startHour, startMinute);
  String get endLabel => _clock((endsAt ~/ 60) % 24, endsAt % 60);

  String get rangeLabel => '$startLabel - $endLabel';

  static String _clock(int hour, int minute) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  DayTime copyWith({int? startHour, int? startMinute, int? durationMinutes}) =>
      DayTime(
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is DayTime &&
      other.startHour == startHour &&
      other.startMinute == startMinute &&
      other.durationMinutes == durationMinutes;

  @override
  int get hashCode => Object.hash(startHour, startMinute, durationMinutes);
}

class ClassScheduleModel {

  Set<int> meetingWeekdays;

  int startHour;
  int startMinute;
  int durationMinutes;

  Map<int, DayTime> dayTimes;

  Map<GradingPeriod, PeriodDateRange> periodRanges;

  Set<DateTime> holidayDates;

  Map<DateTime, String> holidayReasons;

  ClassScheduleModel({
    Set<int>? meetingWeekdays,
    this.startHour = 8,
    this.startMinute = 0,
    this.durationMinutes = 90,
    Map<int, DayTime>? dayTimes,
    Map<GradingPeriod, PeriodDateRange>? periodRanges,
    Set<DateTime>? holidayDates,
    Map<DateTime, String>? holidayReasons,
  })  : meetingWeekdays = meetingWeekdays ?? <int>{},
        dayTimes = dayTimes ?? <int, DayTime>{},
        periodRanges = periodRanges ?? <GradingPeriod, PeriodDateRange>{},
        holidayDates = holidayDates ?? <DateTime>{},
        holidayReasons = holidayReasons ?? <DateTime, String>{};

  DayTime get defaultTime => DayTime(
        startHour: startHour,
        startMinute: startMinute,
        durationMinutes: durationMinutes,
      );

  DayTime timeFor(int weekday) => dayTimes[weekday] ?? defaultTime;

  bool get hasPerDayTimes =>
      meetingWeekdays.any((d) => dayTimes[d] != null && dayTimes[d] != defaultTime);

  void setDayTime(int weekday, DayTime? time) {
    if (time == null || time == defaultTime) {
      dayTimes.remove(weekday);
    } else {
      dayTimes[weekday] = time;
    }
  }

  void clearPerDayTimes() => dayTimes.clear();

  static DateTime normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool isHoliday(DateTime date) => holidayDates.contains(normalize(date));

  void setHoliday(DateTime date, bool isHoliday, {String? reason}) {
    final normalized = normalize(date);
    if (isHoliday) {
      holidayDates.add(normalized);
      if (reason != null && reason.trim().isNotEmpty) {
        holidayReasons[normalized] = reason.trim();
      }
    } else {
      holidayDates.remove(normalized);
      holidayReasons.remove(normalized);
    }
  }

  static const List<String> weekdayShortNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String get timeLabel => defaultTime.startLabel;

  String get meetingDaysLabel {
    if (meetingWeekdays.isEmpty) return 'Not set yet';
    final sorted = meetingWeekdays.toList()..sort();
    return sorted.map((d) => weekdayShortNames[d - 1]).join(', ');
  }

  String get scheduleLabel {
    if (meetingWeekdays.isEmpty) return 'Not set yet';
    if (!hasPerDayTimes) return '$meetingDaysLabel · $timeLabel';

    final sorted = meetingWeekdays.toList()..sort();
    final groups = <DayTime, List<int>>{};
    for (final d in sorted) {
      groups.putIfAbsent(timeFor(d), () => []).add(d);
    }

    final parts = groups.entries.toList()
      ..sort((a, b) => a.key.startsAt.compareTo(b.key.startsAt));

    return parts
        .map((e) =>
            '${e.value.map((d) => weekdayShortNames[d - 1]).join(', ')} ${e.key.startLabel}')
        .join(' · ');
  }

  bool get isConfigured =>
      meetingWeekdays.isNotEmpty && periodRanges.length == GradingPeriod.values.length;

  List<DateTime> classDatesFor(GradingPeriod period) {
    final range = periodRanges[period];
    if (range == null || meetingWeekdays.isEmpty) return [];

    final dates = <DateTime>[];
    var d = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);

    while (!d.isAfter(end)) {
      if (meetingWeekdays.contains(d.weekday) && !isHoliday(d)) dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    return dates;
  }

  GradingPeriod? periodForDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    for (final entry in periodRanges.entries) {
      final start =
          DateTime(entry.value.start.year, entry.value.start.month, entry.value.start.day);
      final end =
          DateTime(entry.value.end.year, entry.value.end.month, entry.value.end.day);
      if (!normalized.isBefore(start) && !normalized.isAfter(end)) {
        return entry.key;
      }
    }
    return null;
  }

  factory ClassScheduleModel.fromJson(Map<String, dynamic> json) {
    final ranges = <GradingPeriod, PeriodDateRange>{};
    final rawRanges = json['periodRanges'];
    if (rawRanges is List) {
      for (final r in rawRanges.whereType<Map<String, dynamic>>()) {
        ranges[ApiEnums.periodFromApi(r['gradingPeriod'] as String?)] = PeriodDateRange(
          start: ApiEnums.dateFromApi(r['startDate'] as String?),
          end: ApiEnums.dateFromApi(r['endDate'] as String?),
        );
      }
    }

    final holidays = <DateTime>{};
    final reasons = <DateTime, String>{};
    final rawDays = json['noClassDays'];
    if (rawDays is List) {
      for (final d in rawDays.whereType<Map<String, dynamic>>()) {
        final date = ApiEnums.dateFromApi(d['date'] as String?);
        holidays.add(date);
        final reason = d['reason'] as String?;
        if (reason != null && reason.trim().isNotEmpty) reasons[date] = reason.trim();
      }
    }

    final parts = (json['startTime'] as String? ?? '08:00:00').split(':');
    final defaultHour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
    final defaultMinute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final defaultDuration = (json['durationMinutes'] as num?)?.toInt() ?? 90;

    final weekdays = <int>{};
    final perDay = <int, DayTime>{};

    for (final raw in (json['meetingDays'] as List? ?? const [])) {
      if (raw is num) {
        weekdays.add(raw.toInt());
        continue;
      }
      if (raw is! Map<String, dynamic>) continue;

      final weekday = (raw['weekday'] as num?)?.toInt();
      if (weekday == null) continue;
      weekdays.add(weekday);

      final rawTime = raw['startTime'] as String?;
      final rawDuration = (raw['durationMinutes'] as num?)?.toInt();
      if (rawTime == null && rawDuration == null) continue;

      final bits = (rawTime ?? '').split(':');
      perDay[weekday] = DayTime(
        startHour: int.tryParse(bits.isNotEmpty ? bits[0] : '') ?? defaultHour,
        startMinute: int.tryParse(bits.length > 1 ? bits[1] : '') ?? defaultMinute,
        durationMinutes: rawDuration ?? defaultDuration,
      );
    }

    return ClassScheduleModel(
      meetingWeekdays: weekdays,
      startHour: defaultHour,
      startMinute: defaultMinute,
      durationMinutes: defaultDuration,
      dayTimes: perDay,
      periodRanges: ranges,
      holidayDates: holidays,
      holidayReasons: reasons,
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'startTime': '${startHour.toString().padLeft(2, '0')}:'
            '${startMinute.toString().padLeft(2, '0')}:00',
        'durationMinutes': durationMinutes,
        'meetingDays': [
          for (final weekday in meetingWeekdays.toList()..sort())
            {
              'weekday': weekday,

              'startTime': dayTimes[weekday] == null
                  ? null
                  : '${dayTimes[weekday]!.startHour.toString().padLeft(2, '0')}:'
                      '${dayTimes[weekday]!.startMinute.toString().padLeft(2, '0')}:00',
              'durationMinutes': dayTimes[weekday]?.durationMinutes,
            }
        ],
        'periodRanges': [
          for (final entry in periodRanges.entries)
            {
              'gradingPeriod': ApiEnums.periodToApi(entry.key),
              'startDate': ApiEnums.dateToApi(entry.value.start),
              'endDate': ApiEnums.dateToApi(entry.value.end),
            }
        ],
      };
}