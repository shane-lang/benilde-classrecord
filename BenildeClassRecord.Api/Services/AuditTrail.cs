using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Entities;
using Microsoft.AspNetCore.Mvc;

namespace BenildeClassRecord.Api.Services;

public static class AuditTrail
{
    private static string? Fit(string? value, int max) =>
        value is null ? null : (value.Length <= max ? value : value[..max]);

    public static void Audit(
        this ControllerBase controller,
        AppDbContext db,
        string action,
        int? classId = null,
        string? target = null,
        string? oldValue = null,
        string? newValue = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            TeacherId = controller.TeacherId(),
            ClassId = classId,
            Action = Fit(action, 60)!,
            Target = Fit(target, 200),
            OldValue = Fit(oldValue, 120),
            NewValue = Fit(newValue, 120),
            At = DateTime.UtcNow
        });
    }
}