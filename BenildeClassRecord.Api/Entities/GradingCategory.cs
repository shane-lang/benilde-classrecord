using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class GradingCategory
{
    public int Id { get; set; }

    public int ClassId { get; set; }
    public Class? Class { get; set; }

    public int? ParentId { get; set; }
    public GradingCategory? Parent { get; set; }
    public ICollection<GradingCategory> Children { get; set; } = new List<GradingCategory>();

    [Required]
    [MaxLength(80)]
    public string Name { get; set; } = string.Empty;

    public decimal Weight { get; set; }

    public bool IsAttendance { get; set; }

    public int SortOrder { get; set; }

    public ICollection<Assessment> Assessments { get; set; } = new List<Assessment>();
}