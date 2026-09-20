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
[Route("api/classes/{classId:int}/attendance")]
public class AttendanceController : ControllerBase
{
    private readonly AppDbContext _db;

    public AttendanceController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<AttendanceRecordDto>>> Get(
        int classId, [FromQuery] string? period)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var query = _db.AttendanceRecords
            .AsNoTracking()
            .Include(a => a.Enrollment)
            .Where(a => a.Enrollment!.ClassId == classId);

        if (period is not null)
        {
            if (!TeacherContext.TryParsePeriod(period, out var parsed))
                return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));
            query = query.Where(a => a.GradingPeriod == parsed);
        }

        var records = await query
            .OrderBy(a => a.Date)
            .Select(a => new AttendanceRecordDto
            {
                Id = a.Id,
                EnrollmentId = a.EnrollmentId,
                Date = a.Date,
                Status = a.Status.ToString(),
                GradingPeriod = a.GradingPeriod.ToString(),
                Remarks = a.Remarks
            })
            .ToListAsync();

        return Ok(records);
    }

    [HttpGet("days")]
    public async Task<ActionResult<List<ClassDayDto>>> GetClassDays(
        int classId, [FromQuery] string period = "Prelim")
    {
        if (!TeacherContext.TryParsePeriod(period, out var parsed))
            return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

        var cls = await _db.Classes
            .AsNoTracking()
            .Include(c => c.Schedule)!.ThenInclude(s => s!.MeetingDays)
            .Include(c => c.PeriodRanges)
            .Include(c => c.NoClassDays)
            .FirstOrDefaultAsync(c => c.Id == classId && c.TeacherId == this.TeacherId());

        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        var dates = ScheduleMapper.ClassDates(cls, parsed).ToHashSet();

        var recorded = await _db.AttendanceRecords
            .AsNoTracking()
            .Include(a => a.Enrollment)
            .Where(a => a.Enrollment!.ClassId == classId && a.GradingPeriod == parsed)
            .GroupBy(a => a.Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        foreach (var r in recorded) dates.Add(r.Date);

        var studentCount = await _db.Enrollments.CountAsync(e => e.ClassId == classId && e.IsActive);
        var countByDate = recorded.ToDictionary(r => r.Date, r => r.Count);

        var days = dates
            .OrderBy(d => d)
            .Select(d => new ClassDayDto
            {
                Date = d,
                GradingPeriod = parsed.ToString(),
                MarkedCount = countByDate.TryGetValue(d, out var n) ? n : 0,
                StudentCount = studentCount
            })
            .ToList();

        return Ok(days);
    }

    [HttpPut]
    public async Task<ActionResult<object>> Save(
        int classId, [FromBody] SaveAttendanceBatchRequest request)
    {
        var cls = await this.OwnedClassAsync(_db, classId);
        if (cls is null)
            return NotFound(new ApiError("That class wasn't found."));

        foreach (var r in request.Records)
        {
            if (TeacherContext.TryParsePeriod(r.GradingPeriod, out var p) && cls.PeriodLocked(p))
                return StatusCode(StatusCodes.Status403Forbidden,
                    new ApiError(TeacherContext.LockedMessage(p)));
        }

        var enrollmentIds = request.Records.Select(r => r.EnrollmentId).Distinct().ToList();

        var validEnrollments = await _db.Enrollments
            .Where(e => enrollmentIds.Contains(e.Id) && e.ClassId == classId)
            .Select(e => e.Id)
            .ToListAsync();

        if (validEnrollments.Count != enrollmentIds.Count)
            return BadRequest(new ApiError("One of those students isn't enrolled in this class."));

        var dates = request.Records.Select(r => r.Date).Distinct().ToList();

        var existing = await _db.AttendanceRecords
            .Where(a => enrollmentIds.Contains(a.EnrollmentId) && dates.Contains(a.Date))
            .ToListAsync();

        var saved = 0;
        var cleared = 0;

        foreach (var input in request.Records)
        {
            var row = existing.FirstOrDefault(a =>
                a.EnrollmentId == input.EnrollmentId && a.Date == input.Date);

            if (string.IsNullOrWhiteSpace(input.Status))
            {
                if (row is not null)
                {
                    _db.AttendanceRecords.Remove(row);
                    cleared++;
                }
                continue;
            }

            if (!TeacherContext.TryParseStatus(input.Status, out var status))
                return BadRequest(new ApiError(
                    "Status must be Present, Absent, Late or Excused."));

            if (!TeacherContext.TryParsePeriod(input.GradingPeriod, out var period))
                return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

            if (row is null)
            {
                this.Audit(_db, "Attendance recorded", classId,
                    $"{input.Date:yyyy-MM-dd} — enrolment {input.EnrollmentId}",
                    oldValue: null, newValue: status.ToString());
                _db.AttendanceRecords.Add(new AttendanceRecord
                {
                    EnrollmentId = input.EnrollmentId,
                    Date = input.Date,
                    Status = status,
                    GradingPeriod = period,
                    Remarks = string.IsNullOrWhiteSpace(input.Remarks) ? null : input.Remarks.Trim(),
                    RecordedAt = DateTime.UtcNow
                });
            }
            else
            {
                if (row.Status != status)
                {
                    this.Audit(_db, "Attendance changed", classId,
                        $"{input.Date:yyyy-MM-dd} — enrolment {input.EnrollmentId}",
                        oldValue: row.Status.ToString(), newValue: status.ToString());
                }
                row.Status = status;
                row.GradingPeriod = period;
                row.Remarks = string.IsNullOrWhiteSpace(input.Remarks) ? null : input.Remarks.Trim();
                row.RecordedAt = DateTime.UtcNow;
            }
            saved++;
        }

        await _db.SaveChangesAsync();
        return Ok(new { saved, cleared });
    }

    [HttpDelete("{date}")]
    public async Task<ActionResult<object>> DeleteDay(int classId, DateOnly date)
    {
        var cls = await this.OwnedClassAsync(_db, classId);
        if (cls is null)
            return NotFound(new ApiError("That class wasn't found."));

        var rows = await _db.AttendanceRecords
            .Include(a => a.Enrollment)
            .Where(a => a.Enrollment!.ClassId == classId && a.Date == date)
            .ToListAsync();

        foreach (var period in rows.Select(r => r.GradingPeriod).Distinct())
        {
            if (cls.PeriodLocked(period))
                return StatusCode(StatusCodes.Status403Forbidden,
                    new ApiError(TeacherContext.LockedMessage(period)));
        }

        this.Audit(_db, "Class day deleted", classId, date.ToString("yyyy-MM-dd"),
            oldValue: $"{rows.Count} record(s)", newValue: null);

        _db.AttendanceRecords.RemoveRange(rows);
        await _db.SaveChangesAsync();
        return Ok(new { deleted = rows.Count });
    }
}