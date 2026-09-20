using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Dtos;

public class EnrolledStudentDto
{
    public int EnrollmentId { get; set; }
    public int StudentId { get; set; }
    public string StudentNumber { get; set; } = string.Empty;
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}

public class EnrollStudentRequest
{
    [Required]
    [MaxLength(30)]
    public string StudentNumber { get; set; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string FirstName { get; set; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string LastName { get; set; } = string.Empty;
}

public class EnrollManyRequest
{
    [Required]
    [MinLength(1, ErrorMessage = "Add at least one student.")]
    public List<EnrollStudentRequest> Students { get; set; } = new();
}

public class UpdateStudentRequest
{
    [Required]
    [MaxLength(60)]
    public string FirstName { get; set; } = string.Empty;

    [Required]
    [MaxLength(60)]
    public string LastName { get; set; } = string.Empty;

    [Required]
    [MaxLength(30)]
    public string StudentNumber { get; set; } = string.Empty;

    public bool IsActive { get; set; } = true;
}