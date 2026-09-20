using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class Student
{
    public int Id { get; set; }

    [Required]
    [MaxLength(30)]
    public string StudentNumber { get; set; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string LastName { get; set; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string FirstName { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Enrollment> Enrollments { get; set; } = new List<Enrollment>();

    public string FullName => $"{FirstName} {LastName}".Trim();
}