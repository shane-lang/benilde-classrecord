using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class Assessment
{
    public int Id { get; set; }

    public int CategoryId { get; set; }
    public GradingCategory? Category { get; set; }

    public GradingPeriod GradingPeriod { get; set; }

    [Required]
    [MaxLength(80)]
    public string Name { get; set; } = string.Empty;

    public decimal MaxScore { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Score> Scores { get; set; } = new List<Score>();
}