using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class AuditLog
{
    public int Id { get; set; }

    public int TeacherId { get; set; }
    public Teacher? Teacher { get; set; }

    public int? ClassId { get; set; }

    [Required]
    [MaxLength(60)]
    public string Action { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? Target { get; set; }

    [MaxLength(120)]
    public string? OldValue { get; set; }

    [MaxLength(120)]
    public string? NewValue { get; set; }

    public DateTime At { get; set; } = DateTime.UtcNow;
}