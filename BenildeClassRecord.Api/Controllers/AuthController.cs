using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace BenildeClassRecord.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly ITokenService _tokens;
    private readonly ILogger<AuthController> _logger;
    private readonly IMemoryCache _cache;
    private readonly IConfiguration _config;

    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan LockoutTime = TimeSpan.FromMinutes(15);

    private const string DummyHash =
        "$2a$11$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";

    public AuthController(
        AppDbContext db,
        ITokenService tokens,
        ILogger<AuthController> logger,
        IMemoryCache cache,
        IConfiguration config)
    {
        _db = db;
        _tokens = tokens;
        _logger = logger;
        _cache = cache;
        _config = config;
    }

    private static string FailKey(string email) => $"login-fails:{email}";

    [HttpPost("login")]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status429TooManyRequests)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        if (_cache.TryGetValue(FailKey(email), out int fails) && fails >= MaxFailedAttempts)
        {
            return StatusCode(StatusCodes.Status429TooManyRequests, new ApiError(
                $"Too many failed attempts. Try again in {LockoutTime.TotalMinutes:0} minutes."));
        }

        var teacher = await _db.Teachers.FirstOrDefaultAsync(t => t.Email == email);

        bool passwordOk;
        if (teacher is null)
        {

            BCrypt.Net.BCrypt.Verify(request.Password, DummyHash);
            passwordOk = false;
        }
        else
        {
            passwordOk = BCrypt.Net.BCrypt.Verify(request.Password, teacher.PasswordHash);
        }

        if (teacher is null || !passwordOk)
        {

            _cache.Set(FailKey(email), fails + 1, LockoutTime);
            _logger.LogWarning("Failed sign-in for {Email} ({Count} in a row)", email, fails + 1);

            return Unauthorized(new ApiError("Incorrect e-mail or password."));
        }

        if (!teacher.IsActive)
        {
            return Unauthorized(new ApiError(
                "This account is deactivated. Ask your administrator to restore it."));
        }

        _cache.Remove(FailKey(email));
        teacher.LastLoginAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var (token, expiresAt) = _tokens.CreateToken(teacher);

        return Ok(new LoginResponse
        {
            Token = token,
            ExpiresAt = expiresAt,
            Teacher = ToDto(teacher)
        });
    }

    [HttpPost("register")]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Register(
        [FromBody] RegisterRequest request,
        [FromHeader(Name = "X-Setup-Key")] string? setupKey)
    {
        var expectedKey = _config["Security:RegistrationKey"];
        if (string.IsNullOrWhiteSpace(expectedKey))
        {
            return StatusCode(StatusCodes.Status403Forbidden, new ApiError(
                "Creating accounts is switched off. Set Security:RegistrationKey in appsettings.Local.json."));
        }

        if (!KeysMatch(setupKey, expectedKey))
        {
            _logger.LogWarning("Registration refused: wrong or missing setup key");
            return StatusCode(StatusCodes.Status403Forbidden, new ApiError(
                "Only the system administrator can create accounts."));
        }

        var email = request.Email.Trim().ToLowerInvariant();

        if (await _db.Teachers.AnyAsync(t => t.Email == email))
        {
            return Conflict(new ApiError("That e-mail already has an account."));
        }

        var firstAccount = !await _db.Teachers.AnyAsync();

        var teacher = new Teacher
        {
            Email = email,
            IsAdmin = firstAccount,
            FullName = request.FullName.Trim(),
            Department = string.IsNullOrWhiteSpace(request.Department)
                ? null
                : request.Department!.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        _db.Teachers.Add(teacher);
        await _db.SaveChangesAsync();

        var (token, expiresAt) = _tokens.CreateToken(teacher);

        return CreatedAtAction(nameof(Me), null, new LoginResponse
        {
            Token = token,
            ExpiresAt = expiresAt,
            Teacher = ToDto(teacher)
        });
    }

    [HttpGet("me")]
    [Authorize]
    [ProducesResponseType(typeof(TeacherDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Me()
    {
        var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!int.TryParse(idClaim, out var id))
        {
            return Unauthorized(new ApiError("This session is no longer valid."));
        }

        var teacher = await _db.Teachers.FindAsync(id);
        if (teacher is null || !teacher.IsActive)
        {
            return Unauthorized(new ApiError("This account is no longer available."));
        }

        return Ok(ToDto(teacher));
    }

    [HttpPost("change-password")]
    [Authorize]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id))
            return Unauthorized(new ApiError("This session is no longer valid."));

        var teacher = await _db.Teachers.FindAsync(id);
        if (teacher is null || !teacher.IsActive)
            return Unauthorized(new ApiError("This account is no longer available."));

        if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword, teacher.PasswordHash))
            return BadRequest(new ApiError("Your current password is incorrect."));

        if (request.NewPassword == request.CurrentPassword)
            return BadRequest(new ApiError("The new password must be different from the current one."));

        teacher.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
        teacher.MustChangePassword = false;
        this.Audit(_db, "Password changed", null, teacher.Email);
        await _db.SaveChangesAsync();

        _logger.LogInformation("Teacher {Id} changed their password", teacher.Id);
        return Ok(new { message = "Password changed." });
    }

    [HttpPost("accept-invite")]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ApiError), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> AcceptInvite([FromBody] AcceptInviteRequest request)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var now = DateTime.UtcNow;

        const string refusal = "That code is not valid for this e-mail address, or it has expired.";

        if (await _db.Teachers.AnyAsync(t => t.Email == email))
            return Conflict(new ApiError("That e-mail already has an account. Log in instead."));

        var invite = await _db.TeacherInvites
            .Where(i => i.Email == email && i.AcceptedAt == null)
            .OrderByDescending(i => i.CreatedAt)
            .FirstOrDefaultAsync();

        if (invite is null || invite.ExpiresAt <= now)
        {
            _logger.LogWarning("Invitation refused for {Email}: none pending", email);
            return StatusCode(StatusCodes.Status403Forbidden, new ApiError(refusal));
        }

        if (!BCrypt.Net.BCrypt.Verify(request.Code.Trim(), invite.CodeHash))
        {
            _logger.LogWarning("Invitation refused for {Email}: wrong code", email);
            return StatusCode(StatusCodes.Status403Forbidden, new ApiError(refusal));
        }

        var teacher = new Teacher
        {
            Email = invite.Email,
            FullName = invite.FullName,
            Department = invite.Department,
            IsAdmin = invite.IsAdmin,

            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            MustChangePassword = false,
            IsActive = true,
            CreatedAt = now
        };

        _db.Teachers.Add(teacher);
        invite.AcceptedAt = now;
        await _db.SaveChangesAsync();

        _logger.LogInformation("Invitation for {Email} accepted", teacher.Email);

        var (token, expiresAt) = _tokens.CreateToken(teacher);

        return CreatedAtAction(nameof(Me), null, new LoginResponse
        {
            Token = token,
            ExpiresAt = expiresAt,
            Teacher = ToDto(teacher)
        });
    }

    private static bool KeysMatch(string? given, string expected)
    {
        if (given is null) return false;
        return CryptographicOperations.FixedTimeEquals(
            SHA256.HashData(Encoding.UTF8.GetBytes(given)),
            SHA256.HashData(Encoding.UTF8.GetBytes(expected)));
    }

    private static TeacherDto ToDto(Teacher t) => new()
    {
        Id = t.Id,
        Email = t.Email,
        FullName = t.FullName,
        Department = t.Department,
        IsAdmin = t.IsAdmin,
        MustChangePassword = t.MustChangePassword
    };
}