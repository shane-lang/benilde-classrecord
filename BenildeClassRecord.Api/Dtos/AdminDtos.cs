using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class TeacherListItemDto
{
    public int Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? Department { get; set; }
    public bool IsActive { get; set; }
    public bool IsAdmin { get; set; }
    public bool MustChangePassword { get; set; }
    public int ClassCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
}

public class CreateTeacherRequest
{
    [Required]
    [EmailAddress]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(120)]
    public string? Department { get; set; }

    [MinLength(8, ErrorMessage = "The password must be at least 8 characters.")]
    [MaxLength(72, ErrorMessage = "The password must be 72 characters or fewer.")]
    public string? Password { get; set; }

    public bool IsAdmin { get; set; }
}

public class SetActiveRequest
{
    public bool Active { get; set; }
}

public class TemporaryPasswordResponse
{
    public int TeacherId { get; set; }
    public string Email { get; set; } = string.Empty;
    public string TemporaryPassword { get; set; } = string.Empty;
    public string Message { get; set; } =
        "Give this password to the teacher in person. The app asks them to set their own password at the next sign-in.";
}

public class SetAdminRequest
{
    public bool IsAdmin { get; set; }
}

public class InviteDto
{
    public int Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? Department { get; set; }
    public bool IsAdmin { get; set; }
    public string InvitedBy { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? AcceptedAt { get; set; }

    public string Status { get; set; } = string.Empty;
}

public class CreateInviteRequest
{
    [Required]
    [EmailAddress]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(120)]
    public string? Department { get; set; }

    public bool IsAdmin { get; set; }

    [Range(1, 60)]
    public int DaysValid { get; set; } = 7;
}

public class InviteCodeResponse
{
    public InviteDto Invite { get; set; } = new();
    public string Code { get; set; } = string.Empty;
    public string Message { get; set; } =
        "Give this code to the teacher together with the e-mail address it was issued for. They choose their own password, so nobody else ever knows it.";
}

public class AcceptInviteRequest
{
    [Required]
    [EmailAddress]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MaxLength(40)]
    public string Code { get; set; } = string.Empty;

    [Required]
    [MinLength(8, ErrorMessage = "Password must be at least 8 characters.")]
    [MaxLength(72, ErrorMessage = "Password must be 72 characters or fewer.")]
    public string Password { get; set; } = string.Empty;
}

public class AdminClassDto
{
    public int Id { get; set; }
    public string SubjectCode { get; set; } = string.Empty;
    public string SubjectName { get; set; } = string.Empty;
    public string Course { get; set; } = string.Empty;
    public string YearSection { get; set; } = string.Empty;
    public string SchoolYear { get; set; } = string.Empty;
    public bool IsArchived { get; set; }
    public int StudentCount { get; set; }
    public DateTime CreatedAt { get; set; }

    public int TeacherId { get; set; }
    public string TeacherName { get; set; } = string.Empty;
    public string TeacherEmail { get; set; } = string.Empty;

    public bool OwnerIsInactive { get; set; }
}

public class TransferClassRequest
{
    [Required]
    public int TeacherId { get; set; }

    [MaxLength(120)]
    public string? Reason { get; set; }
}