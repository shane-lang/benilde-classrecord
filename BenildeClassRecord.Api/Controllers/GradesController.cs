using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BenildeClassRecord.Api.Controllers;

[ApiController]

[Authorize(Roles = "Teacher")]
[Route("api/classes/{classId:int}/grades")]
public class GradesController : ControllerBase
{
    private readonly AppDbContext _db;

    public GradesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<ClassStandingDto>> GetStanding(
        int classId, [FromQuery] string period = "Prelim")
    {
        var cls = await this.OwnedClassAsync(_db, classId);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        if (!TeacherContext.TryParsePeriod(period, out var parsedPeriod))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        var book = await GradeCalculator.LoadAsync(_db, classId);

        var rows = book.Enrollments
            .Where(e => e.IsActive)
            .Select(book.StudentRow)
            .OrderBy(r => r.FullName)
            .ToList();

        var finals = rows.Where(r => r.FinalGrade is not null).Select(r => r.FinalGrade!.Value).ToList();

        var standing = new ClassStandingDto
        {
            ClassId = classId,
            SubjectName = cls.SubjectName,
            PassingGrade = GradeCalculator.PassingGrade,
            PrelimAverage = Average(rows.Select(r => r.Prelim)),
            MidtermAverage = Average(rows.Select(r => r.Midterm)),
            FinalsAverage = Average(rows.Select(r => r.Finals)),
            ClassAverage = finals.Count == 0 ? null : GradeBook.Round(finals.Average()),
            PassingCount = finals.Count(g => g >= GradeCalculator.PassingGrade),
            AtRiskCount = finals.Count(g => g < GradeCalculator.PassingGrade),
            WeightTotal = book.WeightTotal(),
            WeightsUnbalanced = Math.Abs(book.WeightTotal() - 1m) > 0.0005m,
            GradingPeriod = parsedPeriod.ToString(),
            CategoryAverages = book.Categories
                .Select(c => new CategoryAverageDto
                {
                    CategoryId = c.Id,
                    ParentId = c.ParentId,
                    Name = c.Name,
                    Weight = c.Weight,
                    IsAttendance = c.IsAttendance,
                    Average = book.ClassCategoryAverage(c, parsedPeriod),
                    ItemCount = book.ItemCount(c.Id, parsedPeriod)
                })
                .ToList(),
            Students = rows
        };

        return Ok(standing);
    }

    [HttpGet("{enrollmentId:int}")]
    public async Task<ActionResult<StudentReportDto>> GetStudent(
        int classId, int enrollmentId, [FromQuery] string period = "Prelim")
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        if (!TeacherContext.TryParsePeriod(period, out var parsed))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        var book = await GradeCalculator.LoadAsync(_db, classId);

        var enrollment = book.Enrollments.FirstOrDefault(e => e.Id == enrollmentId);
        if (enrollment is null)
            return NotFound(new ApiError("That student wasn't found in this class."));

        var (present, recorded) = book.AttendanceCounts(enrollmentId, parsed);
        var final = book.FinalGrade(enrollmentId);

        return Ok(new StudentReportDto
        {
            EnrollmentId = enrollmentId,
            StudentNumber = enrollment.Student?.StudentNumber ?? string.Empty,
            FullName = enrollment.Student is null
                ? string.Empty
                : $"{enrollment.Student.FirstName} {enrollment.Student.LastName}".Trim(),
            GradingPeriod = parsed.ToString(),
            PeriodGrade = GradeBook.Round(book.PeriodGrade(enrollmentId, parsed)),
            FinalGrade = GradeBook.Round(final),
            Remark = GradeBook.RemarkFor(final),
            AttendanceRate = GradeBook.Round(book.AttendanceRate(enrollmentId, parsed)),
            DaysPresent = present,
            DaysRecorded = recorded,
            Categories = book.Breakdown(enrollmentId, parsed)
        });
    }

    private static decimal? Average(IEnumerable<decimal?> values)
    {
        var present = values.Where(v => v is not null).Select(v => v!.Value).ToList();
        return present.Count == 0 ? null : GradeBook.Round(present.Average());
    }
}