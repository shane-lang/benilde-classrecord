namespace BenildeClassRecord.Api.Entities;

public class Score
{
    public int Id { get; set; }

    public int AssessmentId { get; set; }
    public Assessment? Assessment { get; set; }

    public int EnrollmentId { get; set; }
    public Enrollment? Enrollment { get; set; }

    public decimal Value { get; set; }

    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
}