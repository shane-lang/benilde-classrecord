using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class TeacherInvite
{
    public int Id { get; set; }

    [Required]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(120)]
    public string? Department { get; set; }

    public bool IsAdmin { get; set; }

    [Required]
    [MaxLength(255)]
    public string CodeHash { get; set; } = string.Empty;

    public int InvitedByTeacherId { get; set; }
    public Teacher? InvitedBy { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime ExpiresAt { get; set; }

    public DateTime? AcceptedAt { get; set; }

    public bool IsPending(DateTime now) => AcceptedAt is null && ExpiresAt > now;
}