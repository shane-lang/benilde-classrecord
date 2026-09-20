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
[Route("api/classes/{classId:int}/schedule")]
public class ScheduleController : ControllerBase
{
    private readonly AppDbContext _db;

    public ScheduleController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<ScheduleDto>> Get(int classId)
    {
        var cls = await LoadAsync(classId);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        var dto = ScheduleMapper.ToDto(cls);
        if (dto is null) return NotFound(new ApiError("This class has no schedule set yet."));

        return Ok(dto);
    }

    [HttpPut]
    public async Task<ActionResult<ScheduleDto>> Save(
        int classId, [FromBody] SaveScheduleRequest request)
    {
        var cls = await LoadAsync(classId);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        foreach (var day in request.MeetingDays)
        {
            if (day.Weekday is < 1 or > 7)
                return BadRequest(new ApiError("Meeting days run from 1 (Monday) to 7 (Sunday)."));

            if (day.DurationMinutes is int minutes && minutes is < 15 or > 480)
                return BadRequest(new ApiError(
                    "A session must run between 15 minutes and 8 hours."));
        }

        if (request.MeetingDays.Select(d => d.Weekday).Distinct().Count() != request.MeetingDays.Count)
            return BadRequest(new ApiError("A meeting day is listed twice."));

        var ranges = new List<GradingPeriodRange>();
        foreach (var input in request.PeriodRanges)
        {
            if (!TeacherContext.TryParsePeriod(input.GradingPeriod, out var period))
                return BadRequest(new ApiError("Period must be Prelim, Midterm or Finals."));

            if (input.EndDate < input.StartDate)
                return BadRequest(new ApiError(
                    $"{period} ends before it starts."));

            ranges.Add(new GradingPeriodRange
            {
                ClassId = classId,
                GradingPeriod = period,
                StartDate = input.StartDate,
                EndDate = input.EndDate
            });
        }

        if (ranges.Select(r => r.GradingPeriod).Distinct().Count() != ranges.Count)
            return BadRequest(new ApiError("A grading period is listed twice."));

        var ordered = ranges.OrderBy(r => r.GradingPeriod).ToList();
        for (var i = 1; i < ordered.Count; i++)
        {
            if (ordered[i].StartDate <= ordered[i - 1].EndDate)
                return BadRequest(new ApiError(
                    $"{ordered[i].GradingPeriod} starts before {ordered[i - 1].GradingPeriod} ends."));
        }

        var schedule = cls.Schedule;
        if (schedule is null)
        {
            schedule = new ClassSchedule { ClassId = classId };
            _db.ClassSchedules.Add(schedule);
        }

        schedule.StartTime = request.StartTime;
        schedule.DurationMinutes = request.DurationMinutes;

        _db.ScheduleMeetingDays.RemoveRange(schedule.MeetingDays);
        _db.GradingPeriodRanges.RemoveRange(cls.PeriodRanges);
        await _db.SaveChangesAsync();

        foreach (var day in request.MeetingDays)
        {
            _db.ScheduleMeetingDays.Add(new ScheduleMeetingDay
            {
                ScheduleId = schedule.Id,
                Weekday = day.Weekday,

                StartTime = day.StartTime == request.StartTime ? null : day.StartTime,
                DurationMinutes = day.DurationMinutes == request.DurationMinutes
                    ? null
                    : day.DurationMinutes
            });
        }
        _db.GradingPeriodRanges.AddRange(ranges);
        await _db.SaveChangesAsync();

        var saved = await LoadAsync(classId);
        return Ok(ScheduleMapper.ToDto(saved!));
    }

    [HttpPost("no-class-days")]
    public async Task<ActionResult<NoClassDayDto>> AddNoClassDay(
        int classId, [FromBody] SaveNoClassDayRequest request)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var exists = await _db.NoClassDays
            .AnyAsync(d => d.ClassId == classId && d.Date == request.Date);

        if (exists)
            return Conflict(new ApiError("That date is already marked as a no-class day."));

        var day = new NoClassDay
        {
            ClassId = classId,
            Date = request.Date,
            Reason = string.IsNullOrWhiteSpace(request.Reason) ? null : request.Reason.Trim()
        };

        _db.NoClassDays.Add(day);
        await _db.SaveChangesAsync();

        return Ok(new NoClassDayDto { Date = day.Date, Reason = day.Reason });
    }

    [HttpDelete("no-class-days/{date}")]
    public async Task<IActionResult> RemoveNoClassDay(int classId, DateOnly date)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var day = await _db.NoClassDays
            .FirstOrDefaultAsync(d => d.ClassId == classId && d.Date == date);

        if (day is null) return NotFound(new ApiError("That date isn't marked as a no-class day."));

        _db.NoClassDays.Remove(day);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Task<Class?> LoadAsync(int classId) =>
        _db.Classes
            .Include(c => c.Schedule)!.ThenInclude(s => s!.MeetingDays)
            .Include(c => c.PeriodRanges)
            .Include(c => c.NoClassDays)
            .FirstOrDefaultAsync(c => c.Id == classId && c.TeacherId == this.TeacherId());
}