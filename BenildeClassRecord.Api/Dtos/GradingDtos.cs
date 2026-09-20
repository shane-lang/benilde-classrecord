using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class GradingCategoryDto
{
    public int Id { get; set; }
    public int? ParentId { get; set; }
    public string Name { get; set; } = string.Empty;

    public decimal Weight { get; set; }

    public bool IsAttendance { get; set; }
    public int SortOrder { get; set; }
    public int AssessmentCount { get; set; }
    public List<GradingCategoryDto> Children { get; set; } = new();
}

public class SaveCategoryRequest
{
    [Required]
    [MaxLength(80)]
    public string Name { get; set; } = string.Empty;

    [Range(0.0001, 1.0, ErrorMessage = "Weight must be between 0 and 1, where 0.20 means 20%.")]
    public decimal Weight { get; set; }

    public int? ParentId { get; set; }

    public int SortOrder { get; set; }
}

public class AssessmentDto
{
    public int Id { get; set; }
    public int CategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string GradingPeriod { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public decimal MaxScore { get; set; }
    public int ScoredCount { get; set; }
}

public class SaveAssessmentRequest
{
    [Required]
    [MaxLength(80)]
    public string Name { get; set; } = string.Empty;

    [Range(0.01, 10000, ErrorMessage = "The perfect score must be more than 0.")]
    public decimal MaxScore { get; set; } = 100;

    [Required]
    public string GradingPeriod { get; set; } = "Prelim";
}

public class CreateAssessmentSeriesRequest
{
    [Required]
    [MaxLength(60)]
    public string NamePrefix { get; set; } = string.Empty;

    [Range(1, 50)]
    public int Count { get; set; } = 4;

    [Range(0.01, 10000)]
    public decimal MaxScore { get; set; } = 100;

    [Required]
    public string GradingPeriod { get; set; } = "Prelim";
}