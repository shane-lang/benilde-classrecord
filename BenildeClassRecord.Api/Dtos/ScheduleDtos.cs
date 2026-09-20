using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class MeetingDayDto
{

    public byte Weekday { get; set; }

    public TimeOnly? StartTime { get; set; }

    [Range(15, 480)]
    public int? DurationMinutes { get; set; }
}

public class ScheduleDto
{

    public TimeOnly StartTime { get; set; }

    public int DurationMinutes { get; set; }

    public List<MeetingDayDto> MeetingDays { get; set; } = new();

    public List<PeriodRangeDto> PeriodRanges { get; set; } = new();
    public List<NoClassDayDto> NoClassDays { get; set; } = new();
    public bool IsComplete { get; set; }
}

public class PeriodRangeDto
{
    public string GradingPeriod { get; set; } = string.Empty;
    public DateOnly StartDate { get; set; }
    public DateOnly EndDate { get; set; }
}

public class NoClassDayDto
{
    public DateOnly Date { get; set; }
    public string? Reason { get; set; }
}

public class SaveScheduleRequest
{
    [Required]
    public TimeOnly StartTime { get; set; } = new(8, 0);

    [Range(15, 480)]
    public int DurationMinutes { get; set; } = 90;

    [Required]
    [MinLength(1, ErrorMessage = "Pick at least one meeting day.")]
    public List<MeetingDayDto> MeetingDays { get; set; } = new();

    public List<PeriodRangeDto> PeriodRanges { get; set; } = new();
}

public class SaveNoClassDayRequest
{
    [Required]
    public DateOnly Date { get; set; }

    [MaxLength(120)]
    public string? Reason { get; set; }
}

public class ClassDayDto
{
    public DateOnly Date { get; set; }
    public string GradingPeriod { get; set; } = string.Empty;
    public int MarkedCount { get; set; }
    public int StudentCount { get; set; }
}