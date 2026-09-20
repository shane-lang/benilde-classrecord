using BenildeClassRecord.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Data;

public static class DbSeeder
{
    public const string DevAdminEmail = "admin@benilde.edu.ph";

    public const string DevAdminPassword = "Admin@Benilde2026";

    public static async Task SeedAsync(AppDbContext db, ILogger logger, bool isDevelopment)
    {
        if (await db.Teachers.AnyAsync()) return;

        if (!isDevelopment)
        {
            logger.LogWarning(
                "The database has no accounts and none was created, because seeding "
                + "an account with a known password is not safe outside development. "
                + "Create the first administrator by running sql/003_admin_account.sql, "
                + "or by setting Security:RegistrationKey in appsettings.Local.json and "
                + "calling POST /api/auth/register with that key in the X-Setup-Key header.");
            return;
        }

        db.Teachers.Add(new Teacher
        {
            Email = DevAdminEmail,
            FullName = "System Administrator",
            Department = "Administration",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(DevAdminPassword),
            IsActive = true,

            IsAdmin = true,

            MustChangePassword = true,
            CreatedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();

        logger.LogInformation(
            "Development: seeded the administrator account {Email}. Its password is "
            + "DbSeeder.DevAdminPassword, and the system will require a new one at "
            + "the first sign-in.",
            DevAdminEmail);
    }
}