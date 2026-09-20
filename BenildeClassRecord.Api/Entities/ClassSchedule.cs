namespace BenildeClassRecord.Api.Entities;

public class ClassSchedule
{
    public int Id { get; set; }

    public int ClassId { get; set; }
    public Class? Class { get; set; }

    public TimeOnly StartTime { get; set; } = new(8, 0);

    public int DurationMinutes { get; set; } = 90;

    public ICollection<ScheduleMeetingDay> MeetingDays { get; set; } = new List<ScheduleMeetingDay>();
}