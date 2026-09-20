using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class Teacher
{
    public int Id { get; set; }

    [Required]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(255)]
    public string PasswordHash { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(120)]
    public string? Department { get; set; }

    public bool IsActive { get; set; } = true;

    public bool IsAdmin { get; set; }

    public bool MustChangePassword { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? LastLoginAt { get; set; }

    public ICollection<Class> Classes { get; set; } = new List<Class>();
}