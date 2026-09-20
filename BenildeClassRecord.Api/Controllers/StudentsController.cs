using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Controllers;

[ApiController]

[Authorize(Roles = "Teacher")]
[Route("api/classes/{classId:int}/students")]
public class StudentsController : ControllerBase
{
    private readonly AppDbContext _db;

    public StudentsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<EnrolledStudentDto>>> GetRoster(int classId)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var roster = await _db.Enrollments
            .AsNoTracking()
            .Include(e => e.Student)
            .Where(e => e.ClassId == classId)
            .OrderBy(e => e.Student!.LastName).ThenBy(e => e.Student!.FirstName)
            .Select(e => new EnrolledStudentDto
            {
                EnrollmentId = e.Id,
                StudentId = e.StudentId,
                StudentNumber = e.Student!.StudentNumber,
                FirstName = e.Student.FirstName,
                LastName = e.Student.LastName,
                FullName = e.Student.FirstName + " " + e.Student.LastName,
                IsActive = e.IsActive
            })
            .ToListAsync();

        return Ok(roster);
    }

    [HttpPost]
    public async Task<ActionResult<List<EnrolledStudentDto>>> Enroll(
        int classId, [FromBody] EnrollManyRequest request)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var numbers = request.Students
            .Select(s => s.StudentNumber.Trim())
            .Where(n => n.Length > 0)
            .ToList();

        if (numbers.Count == 0)
            return BadRequest(new ApiError("Every student needs a student number."));

        if (numbers.Count != numbers.Distinct(StringComparer.OrdinalIgnoreCase).Count())
            return BadRequest(new ApiError("The same student number appears twice in this list."));

        var existingStudents = await _db.Students
            .Where(s => numbers.Contains(s.StudentNumber))
            .ToListAsync();

        var alreadyEnrolled = await _db.Enrollments
            .Where(e => e.ClassId == classId)
            .Select(e => e.StudentId)
            .ToListAsync();

        var added = new List<Enrollment>();

        foreach (var input in request.Students)
        {
            var number = input.StudentNumber.Trim();
            if (number.Length == 0) continue;

            var student = existingStudents
                .FirstOrDefault(s => string.Equals(s.StudentNumber, number, StringComparison.OrdinalIgnoreCase));

            if (student is null)
            {
                student = new Student
                {
                    StudentNumber = number,
                    FirstName = input.FirstName.Trim(),
                    LastName = input.LastName.Trim(),
                    CreatedAt = DateTime.UtcNow
                };
                _db.Students.Add(student);
                existingStudents.Add(student);
            }
            else if (alreadyEnrolled.Contains(student.Id))
            {

                continue;
            }

            var enrollment = new Enrollment
            {
                ClassId = classId,
                Student = student,
                IsActive = true,
                EnrolledAt = DateTime.UtcNow
            };
            _db.Enrollments.Add(enrollment);
            added.Add(enrollment);
        }

        if (added.Count == 0)
            return BadRequest(new ApiError("Everyone on that list is already enrolled in this class."));

        await _db.SaveChangesAsync();

        return Ok(added.Select(e => new EnrolledStudentDto
        {
            EnrollmentId = e.Id,
            StudentId = e.StudentId,
            StudentNumber = e.Student!.StudentNumber,
            FirstName = e.Student.FirstName,
            LastName = e.Student.LastName,
            FullName = $"{e.Student.FirstName} {e.Student.LastName}".Trim(),
            IsActive = e.IsActive
        }).ToList());
    }

    [HttpPut("{enrollmentId:int}")]
    public async Task<IActionResult> Update(
        int classId, int enrollmentId, [FromBody] UpdateStudentRequest request)
    {
        var enrollment = await this.OwnedEnrollmentAsync(_db, enrollmentId);
        if (enrollment is null || enrollment.ClassId != classId)
            return NotFound(new ApiError("That student wasn't found in this class."));

        var number = request.StudentNumber.Trim();
        var clash = await _db.Students
            .AnyAsync(s => s.StudentNumber == number && s.Id != enrollment.StudentId);
        if (clash)
            return Conflict(new ApiError($"Student number {number} already belongs to someone else."));

        enrollment.Student!.FirstName = request.FirstName.Trim();
        enrollment.Student.LastName = request.LastName.Trim();
        enrollment.Student.StudentNumber = number;
        enrollment.IsActive = request.IsActive;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{enrollmentId:int}")]
    public async Task<IActionResult> Remove(int classId, int enrollmentId)
    {
        var enrollment = await this.OwnedEnrollmentAsync(_db, enrollmentId);
        if (enrollment is null || enrollment.ClassId != classId)
            return NotFound(new ApiError("That student wasn't found in this class."));

        _db.Enrollments.Remove(enrollment);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}