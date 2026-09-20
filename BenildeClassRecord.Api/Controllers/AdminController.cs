using System.Security.Cryptography;
using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin")]
[Route("api/admin")]
public class AdminController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly ILogger<AdminController> _logger;

    public AdminController(AppDbContext db, ILogger<AdminController> logger)
    {
        _db = db;
        _logger = logger;
    }

    private static string TemporaryPassword()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
        var chars = new char[12];
        for (var i = 0; i < chars.Length; i++)
        {
            chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        }
        return new string(chars);
    }

    [HttpGet("teachers")]
    public async Task<ActionResult<List<TeacherListItemDto>>> GetTeachers()
    {
        var teachers = await _db.Teachers
            .AsNoTracking()
            .OrderBy(t => t.FullName)
            .Select(t => new TeacherListItemDto
            {
                Id = t.Id,
                Email = t.Email,
                FullName = t.FullName,
                Department = t.Department,
                IsActive = t.IsActive,
                IsAdmin = t.IsAdmin,
                MustChangePassword = t.MustChangePassword,
                ClassCount = t.Classes.Count,
                CreatedAt = t.CreatedAt,
                LastLoginAt = t.LastLoginAt
            })
            .ToListAsync();

        return Ok(teachers);
    }

    [HttpPost("teachers")]
    [EnableRateLimiting("auth")]
    public async Task<ActionResult<TemporaryPasswordResponse>> CreateTeacher(
        [FromBody] CreateTeacherRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        if (await _db.Teachers.AnyAsync(t => t.Email == email))
            return Conflict(new ApiError("That e-mail already has an account."));

        var password = string.IsNullOrWhiteSpace(request.Password)
            ? TemporaryPassword()
            : request.Password;

        var teacher = new Teacher
        {
            Email = email,
            FullName = request.FullName.Trim(),
            Department = string.IsNullOrWhiteSpace(request.Department) ? null : request.Department!.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
            IsActive = true,
            IsAdmin = request.IsAdmin,

            MustChangePassword = true,
            CreatedAt = DateTime.UtcNow
        };

        _db.Teachers.Add(teacher);
        await _db.SaveChangesAsync();

        this.Audit(_db, "Account created", null, teacher.Email,
            newValue: request.IsAdmin ? "administrator" : "teacher");
        await _db.SaveChangesAsync();

        _logger.LogInformation("Account {Email} created by teacher {AdminId}", teacher.Email, this.TeacherId());

        return Ok(new TemporaryPasswordResponse
        {
            TeacherId = teacher.Id,
            Email = teacher.Email,
            TemporaryPassword = password
        });
    }

    [HttpPut("teachers/{id:int}/active")]
    public async Task<IActionResult> SetActive(int id, [FromBody] SetActiveRequest request)
    {

        if (id == this.TeacherId() && !request.Active)
            return BadRequest(new ApiError("You cannot deactivate your own account."));

        var teacher = await _db.Teachers.FindAsync(id);
        if (teacher is null) return NotFound(new ApiError("That account wasn't found."));

        if (teacher.IsActive == request.Active) return NoContent();

        if (!request.Active && teacher.IsAdmin)
        {
            var otherAdmins = await _db.Teachers
                .CountAsync(t => t.IsAdmin && t.IsActive && t.Id != id);
            if (otherAdmins == 0)
            {
                return BadRequest(new ApiError(
                    "This is the only active administrator account. Create a second " +
                    "one before deactivating this one, or nobody will be able to " +
                    "manage accounts."));
            }
        }

        teacher.IsActive = request.Active;
        this.Audit(_db, request.Active ? "Account restored" : "Account deactivated", null, teacher.Email,
            oldValue: request.Active ? "deactivated" : "active",
            newValue: request.Active ? "active" : "deactivated");

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPut("teachers/{id:int}/role")]
    public async Task<IActionResult> SetRole(int id, [FromBody] SetAdminRequest request)
    {
        if (id == this.TeacherId() && !request.IsAdmin)
            return BadRequest(new ApiError("You cannot remove your own administrator role."));

        var teacher = await _db.Teachers.FindAsync(id);
        if (teacher is null) return NotFound(new ApiError("That account wasn't found."));

        if (teacher.IsAdmin == request.IsAdmin) return NoContent();

        if (request.IsAdmin)
        {
            var classCount = await _db.Classes.CountAsync(c => c.TeacherId == id);
            if (classCount > 0)
            {
                return BadRequest(new ApiError(
                    $"{teacher.FullName} holds {classCount} " +
                    (classCount == 1 ? "class" : "classes") +
                    ". An administrator account holds no classes, so this account " +
                    "cannot become one. Create a separate administrator account instead."));
            }
        }

        if (!request.IsAdmin)
        {
            var otherAdmins = await _db.Teachers
                .CountAsync(t => t.IsAdmin && t.IsActive && t.Id != id);
            if (otherAdmins == 0)
            {
                return BadRequest(new ApiError(
                    "This is the only administrator account. Create another one " +
                    "before removing this role, or no one will be able to manage accounts."));
            }
        }

        teacher.IsAdmin = request.IsAdmin;
        this.Audit(_db, request.IsAdmin ? "Administrator role granted" : "Administrator role removed",
            null, teacher.Email,
            oldValue: request.IsAdmin ? "teacher" : "administrator",
            newValue: request.IsAdmin ? "administrator" : "teacher");

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("teachers/{id:int}/reset-password")]
    [EnableRateLimiting("auth")]
    public async Task<ActionResult<TemporaryPasswordResponse>> ResetPassword(int id)
    {
        var teacher = await _db.Teachers.FindAsync(id);
        if (teacher is null) return NotFound(new ApiError("That account wasn't found."));

        var password = TemporaryPassword();
        teacher.PasswordHash = BCrypt.Net.BCrypt.HashPassword(password);
        teacher.MustChangePassword = true;

        this.Audit(_db, "Password reset", null, teacher.Email);
        await _db.SaveChangesAsync();

        _logger.LogWarning("Password of {Email} reset by teacher {AdminId}", teacher.Email, this.TeacherId());

        return Ok(new TemporaryPasswordResponse
        {
            TeacherId = teacher.Id,
            Email = teacher.Email,
            TemporaryPassword = password
        });
    }

    [HttpGet("classes")]
    public async Task<ActionResult<List<AdminClassDto>>> GetClasses(
        [FromQuery] bool includeArchived = true)
    {
        var classes = await _db.Classes
            .AsNoTracking()
            .Include(c => c.Teacher)
            .Where(c => includeArchived || !c.IsArchived)
            .OrderBy(c => c.Teacher!.FullName)
            .ThenBy(c => c.SubjectCode)
            .Select(c => new AdminClassDto
            {
                Id = c.Id,
                SubjectCode = c.SubjectCode,
                SubjectName = c.SubjectName,
                Course = c.Course,
                YearSection = c.YearSection,
                SchoolYear = c.SchoolYear,
                IsArchived = c.IsArchived,
                StudentCount = c.Enrollments.Count(e => e.IsActive),
                CreatedAt = c.CreatedAt,
                TeacherId = c.TeacherId,
                TeacherName = c.Teacher!.FullName,
                TeacherEmail = c.Teacher!.Email,
                OwnerIsInactive = !c.Teacher!.IsActive
            })
            .ToListAsync();

        return Ok(classes);
    }

    [HttpPut("classes/{id:int}/teacher")]
    public async Task<IActionResult> TransferClass(int id, [FromBody] TransferClassRequest request)
    {
        var cls = await _db.Classes
            .Include(c => c.Teacher)
            .FirstOrDefaultAsync(c => c.Id == id);
        if (cls is null) return NotFound(new ApiError("That class wasn't found."));

        var target = await _db.Teachers.FindAsync(request.TeacherId);
        if (target is null) return NotFound(new ApiError("That account wasn't found."));

        if (target.IsAdmin)
        {
            return BadRequest(new ApiError(
                $"{target.FullName} is an administrator account, and an administrator " +
                "holds no classes. Choose a teacher account instead."));
        }

        if (!target.IsActive)
        {
            return BadRequest(new ApiError(
                $"{target.FullName}'s account is deactivated, so they could not open " +
                "the class. Restore the account first, or choose someone else."));
        }

        if (cls.TeacherId == target.Id)
        {
            return BadRequest(new ApiError(
                $"{target.FullName} already holds this class."));
        }

        var fromName = cls.Teacher?.FullName ?? "a former account";
        cls.TeacherId = target.Id;

        var what = $"{cls.SubjectCode} {cls.YearSection}".Trim();
        this.Audit(_db, "Class transferred", cls.Id,
            string.IsNullOrWhiteSpace(what) ? cls.SubjectName : what,
            oldValue: fromName,
            newValue: string.IsNullOrWhiteSpace(request.Reason)
                ? target.FullName
                : $"{target.FullName} ({request.Reason!.Trim()})");

        await _db.SaveChangesAsync();

        _logger.LogInformation(
            "Class {ClassId} transferred from teacher {From} to teacher {To} by admin {AdminId}",
            cls.Id, fromName, target.FullName, this.TeacherId());

        return NoContent();
    }

    private static string InviteCode()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var block = new char[9];
        for (var i = 0; i < block.Length; i++)
        {
            block[i] = i == 4
                ? '-'
                : alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        }
        return $"BCR-{new string(block)}";
    }

    private static string StatusOf(TeacherInvite invite, DateTime now) =>
        invite.AcceptedAt is not null ? "Accepted" : (invite.ExpiresAt <= now ? "Expired" : "Pending");

    private static InviteDto ToDto(TeacherInvite invite, DateTime now) => new()
    {
        Id = invite.Id,
        Email = invite.Email,
        FullName = invite.FullName,
        Department = invite.Department,
        IsAdmin = invite.IsAdmin,
        InvitedBy = invite.InvitedBy?.FullName ?? string.Empty,
        CreatedAt = invite.CreatedAt,
        ExpiresAt = invite.ExpiresAt,
        AcceptedAt = invite.AcceptedAt,
        Status = StatusOf(invite, now)
    };

    [HttpGet("invites")]
    public async Task<ActionResult<List<InviteDto>>> GetInvites()
    {
        var now = DateTime.UtcNow;
        var invites = await _db.TeacherInvites
            .AsNoTracking()
            .Include(i => i.InvitedBy)
            .OrderByDescending(i => i.CreatedAt)
            .ToListAsync();

        return Ok(invites.Select(i => ToDto(i, now)).ToList());
    }

    [HttpPost("invites")]
    [EnableRateLimiting("auth")]
    public async Task<ActionResult<InviteCodeResponse>> CreateInvite(
        [FromBody] CreateInviteRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        if (await _db.Teachers.AnyAsync(t => t.Email == email))
            return Conflict(new ApiError("That e-mail already has an account."));

        var now = DateTime.UtcNow;

        var existing = await _db.TeacherInvites
            .Where(i => i.Email == email && i.AcceptedAt == null)
            .ToListAsync();
        if (existing.Count > 0) _db.TeacherInvites.RemoveRange(existing);

        var code = InviteCode();
        var invite = new TeacherInvite
        {
            Email = email,
            FullName = request.FullName.Trim(),
            Department = string.IsNullOrWhiteSpace(request.Department) ? null : request.Department!.Trim(),
            IsAdmin = request.IsAdmin,
            CodeHash = BCrypt.Net.BCrypt.HashPassword(code),
            InvitedByTeacherId = this.TeacherId(),
            CreatedAt = now,
            ExpiresAt = now.AddDays(request.DaysValid)
        };

        _db.TeacherInvites.Add(invite);
        this.Audit(_db, "Teacher invited", null, invite.Email,
            newValue: $"{(request.IsAdmin ? "administrator" : "teacher")}, expires {invite.ExpiresAt:yyyy-MM-dd}");
        await _db.SaveChangesAsync();

        _logger.LogInformation("Invitation for {Email} issued by teacher {AdminId}", invite.Email, this.TeacherId());

        await _db.Entry(invite).Reference(i => i.InvitedBy).LoadAsync();

        return Ok(new InviteCodeResponse
        {
            Invite = ToDto(invite, now),
            Code = code
        });
    }

    [HttpDelete("invites/{id:int}")]
    public async Task<IActionResult> RevokeInvite(int id)
    {
        var invite = await _db.TeacherInvites.FindAsync(id);
        if (invite is null) return NotFound(new ApiError("That invitation wasn't found."));

        if (invite.AcceptedAt is not null)
            return BadRequest(new ApiError(
                "That invitation has already been used. Deactivate the account instead."));

        this.Audit(_db, "Invitation revoked", null, invite.Email);
        _db.TeacherInvites.Remove(invite);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("audit")]
    public async Task<ActionResult<List<AuditLogDto>>> GetAudit([FromQuery] int limit = 200)
    {
        limit = Math.Clamp(limit, 1, 1000);

        var rows = await _db.AuditLogs
            .AsNoTracking()
            .Include(a => a.Teacher)
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
}