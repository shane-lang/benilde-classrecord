namespace BenildeClassRecord.Api.Entities;

public class Enrollment
{
    public int Id { get; set; }

    public int ClassId { get; set; }
    public Class? Class { get; set; }

    public int StudentId { get; set; }
    public Student? Student { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime EnrolledAt { get; set; } = DateTime.UtcNow;

    public ICollection<Score> Scores { get; set; } = new List<Score>();
    public ICollection<AttendanceRecord> AttendanceRecords { get; set; } = new List<AttendanceRecord>();
}