using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class Class
{
    public int Id { get; set; }

    public int TeacherId { get; set; }
    public Teacher? Teacher { get; set; }

    [MaxLength(20)]
    public string SubjectCode { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string SubjectName { get; set; } = string.Empty;

    [MaxLength(80)]
    public string Course { get; set; } = string.Empty;

    [MaxLength(40)]
    public string YearSection { get; set; } = string.Empty;

    [MaxLength(12)]
    public string SchoolYear { get; set; } = string.Empty;

    public decimal PrelimWeight { get; set; }
    public decimal MidtermWeight { get; set; }
    public decimal FinalsWeight { get; set; }

    public bool IsArchived { get; set; }

    public bool PrelimLocked { get; set; }
    public bool MidtermLocked { get; set; }
    public bool FinalsLocked { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Enrollment> Enrollments { get; set; } = new List<Enrollment>();
    public ICollection<GradingCategory> GradingCategories { get; set; } = new List<GradingCategory>();
    public ICollection<GradingPeriodRange> PeriodRanges { get; set; } = new List<GradingPeriodRange>();
    public ICollection<NoClassDay> NoClassDays { get; set; } = new List<NoClassDay>();
    public ClassSchedule? Schedule { get; set; }
}