using BenildeClassRecord.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Teacher> Teachers => Set<Teacher>();
    public DbSet<Class> Classes => Set<Class>();
    public DbSet<Student> Students => Set<Student>();
    public DbSet<Enrollment> Enrollments => Set<Enrollment>();
    public DbSet<GradingCategory> GradingCategories => Set<GradingCategory>();
    public DbSet<Assessment> Assessments => Set<Assessment>();
    public DbSet<Score> Scores => Set<Score>();
    public DbSet<AttendanceRecord> AttendanceRecords => Set<AttendanceRecord>();
    public DbSet<ClassSchedule> ClassSchedules => Set<ClassSchedule>();
    public DbSet<ScheduleMeetingDay> ScheduleMeetingDays => Set<ScheduleMeetingDay>();
    public DbSet<GradingPeriodRange> GradingPeriodRanges => Set<GradingPeriodRange>();
    public DbSet<NoClassDay> NoClassDays => Set<NoClassDay>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<TeacherInvite> TeacherInvites => Set<TeacherInvite>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        base.OnModelCreating(b);

        b.Entity<Assessment>().Property(x => x.GradingPeriod).HasConversion<string>().HasMaxLength(10);
        b.Entity<AttendanceRecord>().Property(x => x.GradingPeriod).HasConversion<string>().HasMaxLength(10);
        b.Entity<AttendanceRecord>().Property(x => x.Status).HasConversion<string>().HasMaxLength(10);
        b.Entity<GradingPeriodRange>().Property(x => x.GradingPeriod).HasConversion<string>().HasMaxLength(10);

        b.Entity<Teacher>(e =>
        {
            e.ToTable("teachers");
            e.HasIndex(t => t.Email).IsUnique();
        });

        b.Entity<TeacherInvite>(e =>
        {
            e.ToTable("teacher_invites");

            e.HasIndex(x => x.Email);
            e.HasIndex(x => x.ExpiresAt);

            e.HasOne(x => x.InvitedBy)
                .WithMany()
                .HasForeignKey(x => x.InvitedByTeacherId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Class>(e =>
        {
            e.ToTable("classes");
            e.Property(c => c.PrelimWeight).HasPrecision(5, 4);
            e.Property(c => c.MidtermWeight).HasPrecision(5, 4);
            e.Property(c => c.FinalsWeight).HasPrecision(5, 4);
            e.HasOne(c => c.Teacher)
                .WithMany(t => t.Classes)
                .HasForeignKey(c => c.TeacherId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(c => c.TeacherId);
        });

        b.Entity<Student>(e =>
        {
            e.ToTable("students");
            e.HasIndex(s => s.StudentNumber).IsUnique();
            e.Ignore(s => s.FullName);
        });

        b.Entity<Enrollment>(e =>
        {
            e.ToTable("enrollments");
            e.HasOne(x => x.Class)
                .WithMany(c => c.Enrollments)
                .HasForeignKey(x => x.ClassId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Student)
                .WithMany(s => s.Enrollments)
                .HasForeignKey(x => x.StudentId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.ClassId, x.StudentId }).IsUnique();
        });

        b.Entity<GradingCategory>(e =>
        {
            e.ToTable("grading_categories");
            e.Property(x => x.Weight).HasPrecision(5, 4);

            e.HasOne(x => x.Class)
                .WithMany(c => c.GradingCategories)
                .HasForeignKey(x => x.ClassId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(x => x.Parent)
                .WithMany(x => x.Children)
                .HasForeignKey(x => x.ParentId)
                .OnDelete(DeleteBehavior.Restrict);

            e.HasIndex(x => x.ClassId);
        });

        b.Entity<Assessment>(e =>
        {
            e.ToTable("assessments");
            e.Property(x => x.MaxScore).HasPrecision(6, 2);
            e.HasOne(x => x.Category)
                .WithMany(c => c.Assessments)
                .HasForeignKey(x => x.CategoryId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.CategoryId, x.GradingPeriod });
        });

        b.Entity<Score>(e =>
        {
            e.ToTable("scores");
            e.Property(x => x.Value).HasPrecision(6, 2).HasColumnName("Score");

            e.HasOne(x => x.Assessment)
                .WithMany(a => a.Scores)
                .HasForeignKey(x => x.AssessmentId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Enrollment)
                .WithMany(en => en.Scores)
                .HasForeignKey(x => x.EnrollmentId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.AssessmentId, x.EnrollmentId }).IsUnique();
        });

        b.Entity<AttendanceRecord>(e =>
        {
            e.ToTable("attendance_records");
            e.HasOne(x => x.Enrollment)
                .WithMany(en => en.AttendanceRecords)
                .HasForeignKey(x => x.EnrollmentId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => new { x.EnrollmentId, x.Date }).IsUnique();
        });

        b.Entity<ClassSchedule>(e =>
        {
            e.ToTable("class_schedules");
            e.HasOne(x => x.Class)
                .WithOne(c => c.Schedule)
                .HasForeignKey<ClassSchedule>(x => x.ClassId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasIndex(x => x.ClassId).IsUnique();
        });

        b.Entity<ScheduleMeetingDay>(e =>
        {
            e.ToTable("schedule_meeting_days");
            e.HasOne(x => x.Schedule)
                .WithMany(s => s.MeetingDays)
                .HasForeignKey(x => x.ScheduleId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.ScheduleId, x.Weekday }).IsUnique();
        });

        b.Entity<GradingPeriodRange>(e =>
        {
            e.ToTable("grading_period_ranges");
            e.HasOne(x => x.Class)
                .WithMany(c => c.PeriodRanges)
                .HasForeignKey(x => x.ClassId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.ClassId, x.GradingPeriod }).IsUnique();
        });

        b.Entity<AuditLog>(e =>
        {
            e.ToTable("audit_logs");
            e.HasOne(x => x.Teacher)
                .WithMany()
                .HasForeignKey(x => x.TeacherId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.ClassId, x.At });
            e.HasIndex(x => x.At);
        });

        b.Entity<NoClassDay>(e =>
        {
            e.ToTable("no_class_days");
            e.HasOne(x => x.Class)
                .WithMany(c => c.NoClassDays)
                .HasForeignKey(x => x.ClassId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.ClassId, x.Date }).IsUnique();
        });
    }
}