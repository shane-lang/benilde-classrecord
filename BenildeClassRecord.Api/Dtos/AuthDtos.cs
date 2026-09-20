using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class LoginRequest
{
    [Required(ErrorMessage = "E-mail is required.")]
    [EmailAddress(ErrorMessage = "Enter a valid e-mail address.")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Password is required.")]
    public string Password { get; set; } = string.Empty;
}

public class RegisterRequest
{
    [Required]
    [EmailAddress]
    [MaxLength(160)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [MinLength(8, ErrorMessage = "Password must be at least 8 characters.")]
    [MaxLength(72, ErrorMessage = "Password must be 72 characters or fewer.")]
    public string Password { get; set; } = string.Empty;

    [Required]
    [MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(120)]
    public string? Department { get; set; }
}

public class ChangePasswordRequest
{
    [Required]
    public string CurrentPassword { get; set; } = string.Empty;

    [Required]
    [MinLength(8, ErrorMessage = "The new password must be at least 8 characters.")]
    [MaxLength(72, ErrorMessage = "The new password must be 72 characters or fewer.")]
    public string NewPassword { get; set; } = string.Empty;
}

public class TeacherDto
{

    public bool IsAdmin { get; set; }

    public bool MustChangePassword { get; set; }

    public int Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? Department { get; set; }
}

public class LoginResponse
{
    public string Token { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public TeacherDto Teacher { get; set; } = new();
}

public class ApiError
{
    public string Message { get; set; } = string.Empty;
    public Dictionary<string, string[]>? Errors { get; set; }

    public ApiError() { }
    public ApiError(string message) => Message = message;
}