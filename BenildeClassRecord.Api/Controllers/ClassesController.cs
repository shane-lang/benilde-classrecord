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
[Route("api/classes")]
public class ClassesController : ControllerBase
{
    private readonly AppDbContext _db;

    public ClassesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<ClassDto>>> GetAll([FromQuery] bool includeArchived = false)
    {
        var teacherId = this.TeacherId();

        var classes = await _db.Classes
            .AsNoTracking()
            .Where(c => c.TeacherId == teacherId && (includeArchived || !c.IsArchived))
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new ClassDto
            {
                Id = c.Id,
                SubjectCode = c.SubjectCode,
                SubjectName = c.SubjectName,
                Course = c.Course,
                YearSection = c.YearSection,
                SchoolYear = c.SchoolYear,
                StudentCount = c.Enrollments.Count(e => e.IsActive),
                HasSchedule = c.Schedule != null,
                PrelimWeight = c.PrelimWeight,
                MidtermWeight = c.MidtermWeight,
                FinalsWeight = c.FinalsWeight,
                IsArchived = c.IsArchived,
                PrelimLocked = c.PrelimLocked,
                MidtermLocked = c.MidtermLocked,
                FinalsLocked = c.FinalsLocked,
                CreatedAt = c.CreatedAt
            })
            .ToListAsync();

        return Ok(classes);
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<ClassDetailDto>> Get(int id)
    {
        var cls = await _db.Classes
            .AsNoTracking()
            .Include(c => c.Schedule)!.ThenInclude(s => s!.MeetingDays)
            .Include(c => c.PeriodRanges)
            .Include(c => c.NoClassDays)
            .Include(c => c.GradingCategories)
            .FirstOrDefaultAsync(c => c.Id == id && c.TeacherId == this.TeacherId());

        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        var categoryIds = cls.GradingCategories.Select(g => g.Id).ToList();

        var counts = await _db.Assessments
            .Where(a => categoryIds.Contains(a.CategoryId))
            .GroupBy(a => a.CategoryId)
            .Select(g => new { CategoryId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.CategoryId, x => x.Count);

        var dto = new ClassDetailDto
        {
            Id = cls.Id,
            SubjectCode = cls.SubjectCode,
            SubjectName = cls.SubjectName,
            Course = cls.Course,
            YearSection = cls.YearSection,
            SchoolYear = cls.SchoolYear,
            StudentCount = await _db.Enrollments.CountAsync(e => e.ClassId == id && e.IsActive),
            HasSchedule = cls.Schedule != null,
            PrelimWeight = cls.PrelimWeight,
            MidtermWeight = cls.MidtermWeight,
            FinalsWeight = cls.FinalsWeight,
            IsArchived = cls.IsArchived,
            PrelimLocked = cls.PrelimLocked,
            MidtermLocked = cls.MidtermLocked,
            FinalsLocked = cls.FinalsLocked,
            CreatedAt = cls.CreatedAt,
            Schedule = ScheduleMapper.ToDto(cls),
            Categories = CategoryMapper.ToTree(cls.GradingCategories, counts)
        };

        return Ok(dto);
    }

    [HttpPost]
    public async Task<ActionResult<ClassDto>> Create([FromBody] SaveClassRequest request)
    {
        if (!PeriodWeightsValid(request, out var weightError))
            return BadRequest(new ApiError(weightError));

        var cls = new Class
        {
            TeacherId = this.TeacherId(),
            SubjectName = request.SubjectName.Trim(),
            SubjectCode = request.SubjectCode.Trim(),
            Course = request.Course.Trim(),
            YearSection = request.YearSection.Trim(),
            SchoolYear = request.SchoolYear.Trim(),
            PrelimWeight = request.PrelimWeight,
            MidtermWeight = request.MidtermWeight,
            FinalsWeight = request.FinalsWeight,
            CreatedAt = DateTime.UtcNow
        };

        cls.GradingCategories = new List<GradingCategory>
        {
            new() { Name = "Attendance",   Weight = 0.05m, IsAttendance = true, SortOrder = 0 },
            new() { Name = "Quizzes",      Weight = 0.20m, SortOrder = 1 },
            new() { Name = "Activities",   Weight = 0.15m, SortOrder = 2 },
            new() { Name = "Performance Task", Weight = 0.15m, SortOrder = 3 },
            new() { Name = "Project",      Weight = 0.10m, SortOrder = 4 },
            new() { Name = "Major Exam",   Weight = 0.35m, SortOrder = 5 }
        };

        _db.Classes.Add(cls);
        await _db.SaveChangesAsync();

        this.Audit(_db, "Class created", cls.Id, $"{cls.SubjectCode} {cls.SubjectName}".Trim(),
            oldValue: null, newValue: $"{cls.Course} {cls.YearSection}".Trim());
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(Get), new { id = cls.Id }, new ClassDto
        {
            Id = cls.Id,
            SubjectCode = cls.SubjectCode,
            SubjectName = cls.SubjectName,
            Course = cls.Course,
            YearSection = cls.YearSection,
            SchoolYear = cls.SchoolYear,
            StudentCount = 0,
            HasSchedule = false,
            PrelimWeight = cls.PrelimWeight,
            MidtermWeight = cls.MidtermWeight,
            FinalsWeight = cls.FinalsWeight,
            CreatedAt = cls.CreatedAt
        });
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] SaveClassRequest request)
    {
        if (!PeriodWeightsValid(request, out var weightError))
            return BadRequest(new ApiError(weightError));

        var cls = await this.OwnedClassAsync(_db, id);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        cls.SubjectName = request.SubjectName.Trim();
        cls.SubjectCode = request.SubjectCode.Trim();
        cls.Course = request.Course.Trim();
        cls.YearSection = request.YearSection.Trim();
        var before = $"{cls.SubjectCode} {cls.SubjectName}, {cls.Course} {cls.YearSection}".Trim();

        cls.SchoolYear = request.SchoolYear.Trim();
        cls.PrelimWeight = request.PrelimWeight;
        cls.MidtermWeight = request.MidtermWeight;
        cls.FinalsWeight = request.FinalsWeight;

        this.Audit(_db, "Class details changed", cls.Id, cls.SubjectName, oldValue: before,
            newValue: $"{cls.SubjectCode} {cls.SubjectName}, {cls.Course} {cls.YearSection}".Trim());

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPut("{id:int}/archive")]
    public async Task<IActionResult> SetArchived(int id, [FromBody] SetArchivedRequest request)
    {
        var cls = await this.OwnedClassAsync(_db, id);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        cls.IsArchived = request.Archived;
        this.Audit(_db, request.Archived ? "Class archived" : "Class restored", cls.Id,
            $"{cls.SubjectCode} {cls.SubjectName}".Trim());

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPut("{id:int}/periods/{period}/lock")]
    public async Task<IActionResult> SetPeriodLock(
        int id, string period, [FromBody] SetPeriodLockRequest request)
    {
        if (!TeacherContext.TryParsePeriod(period, out var parsed))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        var cls = await this.OwnedClassAsync(_db, id);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        if (cls.PeriodLocked(parsed) == request.Locked) return NoContent();

        cls.SetPeriodLock(parsed, request.Locked);
        this.Audit(_db, request.Locked ? "Period finalized" : "Period reopened", cls.Id,
            $"{parsed} — {cls.SubjectCode} {cls.SubjectName}".Trim(),
            oldValue: request.Locked ? "open" : "finalized",
            newValue: request.Locked ? "finalized" : "open");

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("{id:int}/history")]
    public async Task<ActionResult<List<AuditLogDto>>> History(int id, [FromQuery] int limit = 100)
    {
        if (await this.OwnedClassAsync(_db, id) is null)
            return NotFound(new ApiError("That class wasn't found."));

        limit = Math.Clamp(limit, 1, 500);

        var rows = await _db.AuditLogs
            .AsNoTracking()
            .Include(a => a.Teacher)
            .Where(a => a.ClassId == id)
            .OrderByDescending(a => a.At).ThenByDescending(a => a.Id)
            .Take(limit)
            .Select(a => new AuditLogDto
            {
                Id = a.Id,
                Action = a.Action,
                Target = a.Target,
                OldValue = a.OldValue,
                NewValue = a.NewValue,
                By = a.Teacher!.FullName,
                At = a.At
            })
            .ToListAsync();

        return Ok(rows);
    }

    private static bool PeriodWeightsValid(SaveClassRequest request, out string error)
    {
        var total = request.PrelimWeight + request.MidtermWeight + request.FinalsWeight;
        if (total == 0)
        {
            error = string.Empty;
            return true;
        }

        if (Math.Abs(total - 1m) > 0.0001m)
        {
            error = "The Prelim, Midterm and Finals weights must add up to 100%, "
                + "or all be 0 to weigh the periods equally.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var cls = await this.OwnedClassAsync(_db, id);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        var children = await _db.GradingCategories
            .Where(c => c.ClassId == id && c.ParentId != null)
            .ToListAsync();
        _db.GradingCategories.RemoveRange(children);
        await _db.SaveChangesAsync();

        this.Audit(_db, "Class deleted", null, $"{cls.SubjectCode} {cls.SubjectName}".Trim(),
            oldValue: $"{cls.Course} {cls.YearSection}".Trim(), newValue: null);
        await _db.SaveChangesAsync();

        _db.Classes.Remove(cls);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}