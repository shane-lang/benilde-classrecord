namespace BenildeClassRecord.Api.Entities;

public class ScheduleMeetingDay
{
    public int Id { get; set; }

    public int ScheduleId { get; set; }
    public ClassSchedule? Schedule { get; set; }

    public byte Weekday { get; set; }

    public TimeOnly? StartTime { get; set; }

    public int? DurationMinutes { get; set; }
}