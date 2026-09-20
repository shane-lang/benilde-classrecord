using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class AttendanceRecord
{
    public int Id { get; set; }

    public int EnrollmentId { get; set; }
    public Enrollment? Enrollment { get; set; }

    public DateOnly Date { get; set; }

    public AttendanceStatus Status { get; set; }

    public GradingPeriod GradingPeriod { get; set; }

    [MaxLength(255)]
    public string? Remarks { get; set; }

    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
}