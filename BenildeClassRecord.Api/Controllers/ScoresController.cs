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
[Route("api/classes/{classId:int}/scores")]
public class ScoresController : ControllerBase
{
    private readonly AppDbContext _db;

    public ScoresController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<ScoreDto>>> Get(int classId, [FromQuery] string? period)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var query = _db.Scores
            .AsNoTracking()
            .Include(s => s.Assessment)!.ThenInclude(a => a!.Category)
            .Where(s => s.Assessment!.Category!.ClassId == classId);

        if (period is not null)
        {
            if (!TeacherContext.TryParsePeriod(period, out var parsed))
                return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));
            query = query.Where(s => s.Assessment!.GradingPeriod == parsed);
        }

        var scores = await query
            .Select(s => new ScoreDto
            {
                AssessmentId = s.AssessmentId,
                EnrollmentId = s.EnrollmentId,
                Score = s.Value
            })
            .ToListAsync();

        return Ok(scores);
    }

    [HttpPut]
    public async Task<ActionResult<object>> Save(int classId, [FromBody] SaveScoresRequest request)
    {
        var cls = await this.OwnedClassAsync(_db, classId);
        if (cls is null)
            return NotFound(new ApiError("That class wasn't found."));

        var assessmentIds = request.Scores.Select(s => s.AssessmentId).Distinct().ToList();
        var enrollmentIds = request.Scores.Select(s => s.EnrollmentId).Distinct().ToList();

        var assessments = await _db.Assessments
            .Include(a => a.Category)
            .Where(a => assessmentIds.Contains(a.Id) && a.Category!.ClassId == classId)
            .ToDictionaryAsync(a => a.Id);

        if (assessments.Count != assessmentIds.Count)
            return BadRequest(new ApiError("One of those items doesn't belong to this class."));

        var validEnrollments = await _db.Enrollments
            .Where(e => enrollmentIds.Contains(e.Id) && e.ClassId == classId)
            .Select(e => e.Id)
            .ToListAsync();

        if (validEnrollments.Count != enrollmentIds.Count)
            return BadRequest(new ApiError("One of those students isn't enrolled in this class."));

        foreach (var a in assessments.Values)
        {
            if (cls.PeriodLocked(a.GradingPeriod))
                return StatusCode(StatusCodes.Status403Forbidden,
                    new ApiError(TeacherContext.LockedMessage(a.GradingPeriod)));
        }

        var students = await _db.Enrollments
            .AsNoTracking()
            .Include(e => e.Student)
            .Where(e => enrollmentIds.Contains(e.Id))
            .ToDictionaryAsync(e => e.Id, e => e.Student!.FullName);

        var existing = await _db.Scores
            .Where(s => assessmentIds.Contains(s.AssessmentId) && enrollmentIds.Contains(s.EnrollmentId))
            .ToListAsync();

        var saved = 0;
        var cleared = 0;

        foreach (var input in request.Scores)
        {
            var row = existing.FirstOrDefault(s =>
                s.AssessmentId == input.AssessmentId && s.EnrollmentId == input.EnrollmentId);

            var who = students.TryGetValue(input.EnrollmentId, out var name) ? name : "student";
            var item = assessments[input.AssessmentId].Name;

            if (input.Score is null)
            {
                if (row is not null)
                {
                    this.Audit(_db, "Score cleared", classId, $"{item} — {who}",
                        oldValue: row.Value.ToString("0.##"), newValue: null);
                    _db.Scores.Remove(row);
                    cleared++;
                }
                continue;
            }

            var value = input.Score.Value;
            if (value < 0)
                return BadRequest(new ApiError("A score can't be negative."));

            var max = assessments[input.AssessmentId].MaxScore;
            if (value > max)
                return BadRequest(new ApiError(
                    $"{value} is higher than the perfect score of {max} for {assessments[input.AssessmentId].Name}."));

            if (row is null)
            {
                _db.Scores.Add(new Score
                {
                    AssessmentId = input.AssessmentId,
                    EnrollmentId = input.EnrollmentId,
                    Value = value,
                    RecordedAt = DateTime.UtcNow
                });
                this.Audit(_db, "Score recorded", classId, $"{item} — {who}",
                    oldValue: null, newValue: value.ToString("0.##"));
            }
            else
            {

                if (row.Value != value)
                {
                    this.Audit(_db, "Score changed", classId, $"{item} — {who}",
                        oldValue: row.Value.ToString("0.##"), newValue: value.ToString("0.##"));
                }
                row.Value = value;
                row.RecordedAt = DateTime.UtcNow;
            }
            saved++;
        }

        await _db.SaveChangesAsync();
        return Ok(new { saved, cleared });
    }
}