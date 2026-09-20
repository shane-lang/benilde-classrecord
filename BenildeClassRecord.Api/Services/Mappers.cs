using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;

namespace BenildeClassRecord.Api.Services;

public static class CategoryMapper
{

    public static List<GradingCategoryDto> ToTree(
        IEnumerable<GradingCategory> categories,
        IReadOnlyDictionary<int, int>? assessmentCounts = null)
    {
        var all = categories.OrderBy(c => c.SortOrder).ThenBy(c => c.Id).ToList();

        GradingCategoryDto Map(GradingCategory c) => new()
        {
            Id = c.Id,
            ParentId = c.ParentId,
            Name = c.Name,
            Weight = c.Weight,
            IsAttendance = c.IsAttendance,
            SortOrder = c.SortOrder,
            AssessmentCount = assessmentCounts is not null && assessmentCounts.TryGetValue(c.Id, out var n) ? n : 0
        };

        var result = new List<GradingCategoryDto>();
        foreach (var parent in all.Where(c => c.ParentId is null))
        {
            var dto = Map(parent);
            dto.Children = all.Where(c => c.ParentId == parent.Id).Select(Map).ToList();
            result.Add(dto);
        }
        return result;
    }
}

public static class ScheduleMapper
{
    public static ScheduleDto? ToDto(Class cls)
    {
        if (cls.Schedule is null) return null;

        var dto = new ScheduleDto
        {
            StartTime = cls.Schedule.StartTime,
            DurationMinutes = cls.Schedule.DurationMinutes,
            MeetingDays = cls.Schedule.MeetingDays
                .OrderBy(d => d.Weekday)
                .Select(d => new MeetingDayDto
                {
                    Weekday = d.Weekday,
                    StartTime = d.StartTime,
                    DurationMinutes = d.DurationMinutes
                })
                .ToList(),
            PeriodRanges = cls.PeriodRanges
                .OrderBy(r => r.GradingPeriod)
                .Select(r => new PeriodRangeDto
                {
                    GradingPeriod = r.GradingPeriod.ToString(),
                    StartDate = r.StartDate,
                    EndDate = r.EndDate
                })
                .ToList(),
            NoClassDays = cls.NoClassDays
                .OrderBy(d => d.Date)
                .Select(d => new NoClassDayDto { Date = d.Date, Reason = d.Reason })
                .ToList()
        };

        dto.IsComplete = dto.MeetingDays.Count > 0
            && dto.PeriodRanges.Count == Enum.GetValues<GradingPeriod>().Length;

        return dto;
    }

    public static List<DateOnly> ClassDates(Class cls, GradingPeriod period)
    {
        if (cls.Schedule is null) return new List<DateOnly>();

        var weekdays = cls.Schedule.MeetingDays.Select(d => d.Weekday).ToHashSet();
        if (weekdays.Count == 0) return new List<DateOnly>();

        var range = cls.PeriodRanges.FirstOrDefault(r => r.GradingPeriod == period);
        if (range is null || range.EndDate < range.StartDate) return new List<DateOnly>();

        var skip = cls.NoClassDays.Select(d => d.Date).ToHashSet();

        var dates = new List<DateOnly>();
        for (var d = range.StartDate; d <= range.EndDate; d = d.AddDays(1))
        {

            var iso = d.DayOfWeek == DayOfWeek.Sunday ? (byte)7 : (byte)d.DayOfWeek;
            if (weekdays.Contains(iso) && !skip.Contains(d)) dates.Add(d);
        }
        return dates;
    }
}