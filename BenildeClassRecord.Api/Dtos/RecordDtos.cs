using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class ScoreDto
{
    public int AssessmentId { get; set; }
    public int EnrollmentId { get; set; }
    public decimal Score { get; set; }
}

public class SaveScoreRequest
{
    [Required]
    public int AssessmentId { get; set; }

    [Required]
    public int EnrollmentId { get; set; }

    public decimal? Score { get; set; }
}

public class SaveScoresRequest
{
    [Required]
    [MinLength(1)]
    public List<SaveScoreRequest> Scores { get; set; } = new();
}

public class AttendanceRecordDto
{
    public int Id { get; set; }
    public int EnrollmentId { get; set; }
    public DateOnly Date { get; set; }
    public string Status { get; set; } = string.Empty;
    public string GradingPeriod { get; set; } = string.Empty;
    public string? Remarks { get; set; }
}

public class SaveAttendanceRequest
{
    [Required]
    public int EnrollmentId { get; set; }

    [Required]
    public DateOnly Date { get; set; }

    public string? Status { get; set; }

    [Required]
    public string GradingPeriod { get; set; } = "Prelim";

    [MaxLength(255)]
    public string? Remarks { get; set; }
}

public class SaveAttendanceBatchRequest
{
    [Required]
    [MinLength(1)]
    public List<SaveAttendanceRequest> Records { get; set; } = new();
}