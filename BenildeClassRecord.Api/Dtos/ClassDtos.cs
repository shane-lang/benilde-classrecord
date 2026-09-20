using System.ComponentModel.DataAnnotations;
using BenildeClassRecord.Api.Entities;

namespace BenildeClassRecord.Api.Dtos;

public class ClassDto
{
    public int Id { get; set; }
    public string SubjectCode { get; set; } = string.Empty;
    public string SubjectName { get; set; } = string.Empty;
    public string Course { get; set; } = string.Empty;
    public string YearSection { get; set; } = string.Empty;
    public string SchoolYear { get; set; } = string.Empty;
    public int StudentCount { get; set; }
    public bool HasSchedule { get; set; }

    public decimal PrelimWeight { get; set; }
    public decimal MidtermWeight { get; set; }
    public decimal FinalsWeight { get; set; }

    public bool IsArchived { get; set; }

    public bool PrelimLocked { get; set; }
    public bool MidtermLocked { get; set; }
    public bool FinalsLocked { get; set; }

    public DateTime CreatedAt { get; set; }
}

public class AuditLogDto
{
    public int Id { get; set; }
    public string Action { get; set; } = string.Empty;
    public string? Target { get; set; }
    public string? OldValue { get; set; }
    public string? NewValue { get; set; }
    public string By { get; set; } = string.Empty;
    public DateTime At { get; set; }
}

public class SetArchivedRequest
{
    public bool Archived { get; set; }
}

public class SetPeriodLockRequest
{
    public bool Locked { get; set; }
}

public class ClassDetailDto : ClassDto
{
    public ScheduleDto? Schedule { get; set; }
    public List<GradingCategoryDto> Categories { get; set; } = new();
}

public class SaveClassRequest
{
    [Required]
    [MaxLength(120)]
    public string SubjectName { get; set; } = string.Empty;

    [MaxLength(20)]
    public string SubjectCode { get; set; } = string.Empty;

    [MaxLength(80)]
    public string Course { get; set; } = string.Empty;

    [MaxLength(40)]
    public string YearSection { get; set; } = string.Empty;

    [MaxLength(12)]
    public string SchoolYear { get; set; } = string.Empty;

    [Range(0, 1)]
    public decimal PrelimWeight { get; set; }

    [Range(0, 1)]
    public decimal MidtermWeight { get; set; }

    [Range(0, 1)]
    public decimal FinalsWeight { get; set; }
}