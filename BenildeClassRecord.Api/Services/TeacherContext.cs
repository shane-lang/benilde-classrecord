using System.Security.Claims;
using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Services;

public static class TeacherContext
{
    public static int TeacherId(this ControllerBase controller)
    {
        var raw = controller.User.FindFirstValue(ClaimTypes.NameIdentifier);
        return int.TryParse(raw, out var id) ? id : 0;
    }

    public static Task<Class?> OwnedClassAsync(this ControllerBase controller, AppDbContext db, int classId) =>
        db.Classes.FirstOrDefaultAsync(c => c.Id == classId && c.TeacherId == controller.TeacherId());

    public static Task<Enrollment?> OwnedEnrollmentAsync(this ControllerBase controller, AppDbContext db, int enrollmentId) =>
        db.Enrollments
            .Include(e => e.Student)
            .Include(e => e.Class)
            .FirstOrDefaultAsync(e => e.Id == enrollmentId && e.Class!.TeacherId == controller.TeacherId());

    public static Task<GradingCategory?> OwnedCategoryAsync(this ControllerBase controller, AppDbContext db, int categoryId) =>
        db.GradingCategories
            .Include(c => c.Class)
            .FirstOrDefaultAsync(c => c.Id == categoryId && c.Class!.TeacherId == controller.TeacherId());

    public static Task<Assessment?> OwnedAssessmentAsync(this ControllerBase controller, AppDbContext db, int assessmentId) =>
        db.Assessments
            .Include(a => a.Category)!
            .ThenInclude(c => c!.Class)
            .FirstOrDefaultAsync(a => a.Id == assessmentId && a.Category!.Class!.TeacherId == controller.TeacherId());

    public static bool IsAdmin(this ControllerBase controller) =>
        controller.User.IsInRole("Admin");

    public static bool PeriodLocked(this Class cls, GradingPeriod period) => period switch
    {
        GradingPeriod.Prelim => cls.PrelimLocked,
        GradingPeriod.Midterm => cls.MidtermLocked,
        GradingPeriod.Finals => cls.FinalsLocked,
        _ => false
    };

    public static void SetPeriodLock(this Class cls, GradingPeriod period, bool locked)
    {
        switch (period)
        {
            case GradingPeriod.Prelim: cls.PrelimLocked = locked; break;
            case GradingPeriod.Midterm: cls.MidtermLocked = locked; break;
            case GradingPeriod.Finals: cls.FinalsLocked = locked; break;
        }
    }

    public static string LockedMessage(GradingPeriod period) =>
        $"{period} is finalized. Unlock it first if a correction is really needed; "
        + "the unlock is recorded in the class history.";

    public static bool TryParsePeriod(string? value, out GradingPeriod period) =>
        Enum.TryParse(value, ignoreCase: true, out period);

    public static bool TryParseStatus(string? value, out AttendanceStatus status) =>
        Enum.TryParse(value, ignoreCase: true, out status);
}