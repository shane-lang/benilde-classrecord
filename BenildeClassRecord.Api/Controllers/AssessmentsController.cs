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
[Route("api")]
public class AssessmentsController : ControllerBase
{
    private readonly AppDbContext _db;

    public AssessmentsController(AppDbContext db) => _db = db;

    [HttpGet("classes/{classId:int}/assessments")]
    public async Task<ActionResult<List<AssessmentDto>>> GetForClass(
        int classId, [FromQuery] string? period, [FromQuery] int? categoryId)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var query = _db.Assessments
            .AsNoTracking()
            .Include(a => a.Category)
            .Where(a => a.Category!.ClassId == classId);

        if (period is not null)
        {
            if (!TeacherContext.TryParsePeriod(period, out var parsed))
                return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));
            query = query.Where(a => a.GradingPeriod == parsed);
        }

        if (categoryId is int cid) query = query.Where(a => a.CategoryId == cid);

        var items = await query
            .OrderBy(a => a.CategoryId).ThenBy(a => a.Id)
            .Select(a => new AssessmentDto
            {
                Id = a.Id,
                CategoryId = a.CategoryId,
                CategoryName = a.Category!.Name,
                GradingPeriod = a.GradingPeriod.ToString(),
                Name = a.Name,
                MaxScore = a.MaxScore,
                ScoredCount = a.Scores.Count
            })
            .ToListAsync();

        return Ok(items);
    }

    [HttpPost("categories/{categoryId:int}/assessments")]
    public async Task<ActionResult<AssessmentDto>> Create(
        int categoryId, [FromBody] SaveAssessmentRequest request)
    {
        var category = await this.OwnedCategoryAsync(_db, categoryId);
        if (category is null) return NotFound(new ApiError("That category wasn't found."));

        if (category.IsAttendance)
            return BadRequest(new ApiError(
                "Attendance is taken on the attendance sheet, so it holds no items."));

        if (!TeacherContext.TryParsePeriod(request.GradingPeriod, out var period))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        if (category.Class!.PeriodLocked(period))
            return StatusCode(StatusCodes.Status403Forbidden,
                new ApiError(TeacherContext.LockedMessage(period)));

        var assessment = new Assessment
        {
            CategoryId = categoryId,
            Name = request.Name.Trim(),
            MaxScore = request.MaxScore,
            GradingPeriod = period,
            CreatedAt = DateTime.UtcNow
        };

        _db.Assessments.Add(assessment);
        this.Audit(_db, "Item added", category.ClassId, $"{category.Name} — {assessment.Name} ({period})",
            oldValue: null, newValue: $"perfect score {assessment.MaxScore:0.##}");
        await _db.SaveChangesAsync();

        return Ok(ToDto(assessment, category.Name, 0));
    }

    [HttpPost("categories/{categoryId:int}/assessments/series")]
    public async Task<ActionResult<List<AssessmentDto>>> CreateSeries(
        int categoryId, [FromBody] CreateAssessmentSeriesRequest request)
    {
        var category = await this.OwnedCategoryAsync(_db, categoryId);
        if (category is null) return NotFound(new ApiError("That category wasn't found."));

        if (category.IsAttendance)
            return BadRequest(new ApiError("Attendance holds no items."));

        if (!TeacherContext.TryParsePeriod(request.GradingPeriod, out var period))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        if (category.Class!.PeriodLocked(period))
            return StatusCode(StatusCodes.Status403Forbidden,
                new ApiError(TeacherContext.LockedMessage(period)));

        var existing = await _db.Assessments
            .CountAsync(a => a.CategoryId == categoryId && a.GradingPeriod == period);

        var prefix = request.NamePrefix.Trim();
        var created = new List<Assessment>();

        for (var i = 0; i < request.Count; i++)
        {
            var assessment = new Assessment
            {
                CategoryId = categoryId,
                Name = $"{prefix} {existing + i + 1}",
                MaxScore = request.MaxScore,
                GradingPeriod = period,
                CreatedAt = DateTime.UtcNow
            };
            _db.Assessments.Add(assessment);
            created.Add(assessment);
        }

        this.Audit(_db, "Items added", category.ClassId, $"{category.Name} ({period})",
            oldValue: null, newValue: $"{created.Count} item(s), perfect score {request.MaxScore:0.##}");
        await _db.SaveChangesAsync();
        return Ok(created.Select(a => ToDto(a, category.Name, 0)).ToList());
    }

    [HttpPut("assessments/{assessmentId:int}")]
    public async Task<IActionResult> Update(
        int assessmentId, [FromBody] SaveAssessmentRequest request)
    {
        var assessment = await this.OwnedAssessmentAsync(_db, assessmentId);
        if (assessment is null) return NotFound(new ApiError("That item wasn't found."));

        if (!TeacherContext.TryParsePeriod(request.GradingPeriod, out var period))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        var cls = assessment.Category!.Class!;

        foreach (var p in new[] { assessment.GradingPeriod, period })
        {
            if (cls.PeriodLocked(p))
                return StatusCode(StatusCodes.Status403Forbidden,
                    new ApiError(TeacherContext.LockedMessage(p)));
        }

        var before = $"{assessment.Name}, {assessment.MaxScore:0.##}, {assessment.GradingPeriod}";

        assessment.Name = request.Name.Trim();
        assessment.MaxScore = request.MaxScore;
        assessment.GradingPeriod = period;

        this.Audit(_db, "Item changed", assessment.Category!.ClassId, assessment.Name,
            oldValue: before, newValue: $"{assessment.Name}, {assessment.MaxScore:0.##}, {period}");

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("assessments/{assessmentId:int}")]
    public async Task<IActionResult> Delete(int assessmentId)
    {
        var assessment = await this.OwnedAssessmentAsync(_db, assessmentId);
        if (assessment is null) return NotFound(new ApiError("That item wasn't found."));

        if (assessment.Category!.Class!.PeriodLocked(assessment.GradingPeriod))
            return StatusCode(StatusCodes.Status403Forbidden,
                new ApiError(TeacherContext.LockedMessage(assessment.GradingPeriod)));

        var scored = await _db.Scores.CountAsync(s => s.AssessmentId == assessmentId);
        this.Audit(_db, "Item deleted", assessment.Category!.ClassId,
            $"{assessment.Name} ({assessment.GradingPeriod})",
            oldValue: $"{scored} score(s)", newValue: null);

        _db.Assessments.Remove(assessment);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static AssessmentDto ToDto(Assessment a, string categoryName, int scored) => new()
    {
        Id = a.Id,
        CategoryId = a.CategoryId,
        CategoryName = categoryName,
        GradingPeriod = a.GradingPeriod.ToString(),
        Name = a.Name,
        MaxScore = a.MaxScore,
        ScoredCount = scored
    };
}