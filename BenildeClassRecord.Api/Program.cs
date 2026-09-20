using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: true);

var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException(
        "ConnectionStrings:Default is missing from appsettings.json.");

var serverVersion = new MariaDbServerVersion(
    new Version(builder.Configuration.GetValue("Database:MariaDbVersion", "10.4.32")!));

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseMySql(connectionString, serverVersion));

var jwtSettings = builder.Configuration.GetSection(JwtSettings.SectionName).Get<JwtSettings>()
    ?? throw new InvalidOperationException("The Jwt section is missing from appsettings.json.");

if (jwtSettings.Key.Length < 32)
{
    throw new InvalidOperationException(
        "Jwt:Key must be at least 32 characters so tokens cannot be forged.");
}

const string PlaceholderJwtKey = "change-this-to-a-long-random-string-of-at-least-32-characters";
var usingPlaceholderKey = jwtSettings.Key == PlaceholderJwtKey;
if (usingPlaceholderKey && !builder.Environment.IsDevelopment())
{
    throw new InvalidOperationException(
        "Jwt:Key is still the placeholder. Put a long random key in appsettings.Local.json.");
}

builder.Services.AddSingleton(jwtSettings);
builder.Services.AddScoped<ITokenService, TokenService>();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings.Issuer,
            ValidAudience = jwtSettings.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings.Key)),
            ClockSkew = TimeSpan.FromMinutes(1)
        };

        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                var idClaim = context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);
                var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var active = int.TryParse(idClaim, out var teacherId)
                    && await db.Teachers.AnyAsync(t => t.Id == teacherId && t.IsActive);
                if (!active) context.Fail("This account is no longer active.");
            }
        };
    });

builder.Services.AddAuthorization();

builder.Services.AddMemoryCache();

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 10,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0
        }));
    options.OnRejected = async (context, cancellationToken) =>
    {
        await context.HttpContext.Response.WriteAsJsonAsync(
            new ApiError("Too many attempts. Wait a minute and try again."), cancellationToken);
    };
});

const string AppCors = "AppCors";
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
{
    options.AddPolicy(AppCors, policy =>
    {
        if (allowedOrigins.Length > 0)
            policy.WithOrigins(allowedOrigins);
        else if (builder.Environment.IsDevelopment())
            policy.AllowAnyOrigin();

        policy.AllowAnyHeader().AllowAnyMethod();
    });
});

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.Configure<ApiBehaviorOptions>(options =>
{
    options.InvalidModelStateResponseFactory = context =>
    {
        var errors = context.ModelState
            .Where(e => e.Value?.Errors.Count > 0)
            .ToDictionary(
                e => e.Key,
                e => e.Value!.Errors.Select(x => x.ErrorMessage).ToArray());

        return new BadRequestObjectResult(new ApiError("Please check the form and try again.")
        {
            Errors = errors
        });
    };
});

var app = builder.Build();

if (usingPlaceholderKey)
{
    app.Logger.LogWarning(
        "Jwt:Key is the placeholder from the source code. Fine for testing on this computer; "
        + "put a random key in appsettings.Local.json before anyone else uses the system.");
}

using (var scope = app.Services.CreateScope())
{
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    try
    {

        if (db.Database.GetMigrations().Any())
        {
            await db.Database.MigrateAsync();
        }
        else
        {
            logger.LogWarning(
                "No EF Core migrations found. Creating the schema from the model. "
                + "Run \"dotnet ef migrations add InitialCreate\" before you add more tables.");
            await db.Database.EnsureCreatedAsync();
        }

        await DbSeeder.SeedAsync(db, logger, app.Environment.IsDevelopment());
    }
    catch (Exception ex)
    {
        logger.LogError(ex,
            "Could not reach the database. Start MySQL in the XAMPP Control Panel and "
            + "check ConnectionStrings:Default in appsettings.json.");
    }
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{

    app.UseHsts();
    app.UseHttpsRedirection();
}

app.Use(async (context, next) =>
{
    var headers = context.Response.Headers;
    headers["X-Content-Type-Options"] = "nosniff";
    headers["X-Frame-Options"] = "DENY";
    headers["Referrer-Policy"] = "no-referrer";
    await next();
});

app.UseCors(AppCors);
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapGet("/api/health", () => Results.Ok(new
{
    status = "ok",
    time = DateTime.UtcNow
}));

app.Run();