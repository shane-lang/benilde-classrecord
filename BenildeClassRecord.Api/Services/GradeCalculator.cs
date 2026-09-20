using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Services;


public class GradeCalculator
{
    public const decimal PassingGrade = 75m;

    
    public static async Task<GradeBook> LoadAsync(AppDbContext db, int classId)
    {
        var categories = await db.GradingCategories
            .AsNoTracking()
            .Where(c => c.ClassId == classId)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Id)
            .ToListAsync();

        var categoryIds = categories.Select(c => c.Id).ToList();

        var assessments = await db.Assessments
            .AsNoTracking()
            .Where(a => categoryIds.Contains(a.CategoryId))
            .ToListAsync();

        var assessmentIds = assessments.Select(a => a.Id).ToList();

        var enrollments = await db.Enrollments
            .AsNoTracking()
            .Include(e => e.Student)
            .Where(e => e.ClassId == classId)
            .ToListAsync();

        var enrollmentIds = enrollments.Select(e => e.Id).ToList();

        var scores = await db.Scores
            .AsNoTracking()
            .Where(s => assessmentIds.Contains(s.AssessmentId))
            .ToListAsync();

        var attendance = await db.AttendanceRecords
            .AsNoTracking()
            .Where(a => enrollmentIds.Contains(a.EnrollmentId))
            .ToListAsync();

        return new GradeBook(categories, assessments, enrollments, scores, attendance);
    }
}


public class GradeBook
{
    private readonly List<GradingCategory> _categories;
    private readonly List<Assessment> _assessments;
    private readonly List<Enrollment> _enrollments;

 
    private readonly Dictionary<(int AssessmentId, int EnrollmentId), decimal> _scoreLookup;
    private readonly Dictionary<int, List<AttendanceRecord>> _attendanceByEnrollment;

    public IReadOnlyList<GradingCategory> Categories => _categories;
    public IReadOnlyList<Enrollment> Enrollments => _enrollments;

    public GradeBook(
        List<GradingCategory> categories,
        List<Assessment> assessments,
        List<Enrollment> enrollments,
        List<Score> scores,
        List<AttendanceRecord> attendance)
    {
        _categories = categories;
        _assessments = assessments;
        _enrollments = enrollments;

     
        _scoreLookup = new Dictionary<(int, int), decimal>();
        foreach (var s in scores)
        {
            _scoreLookup[(s.AssessmentId, s.EnrollmentId)] = s.Value;
        }

        _attendanceByEnrollment = attendance
            .GroupBy(a => a.EnrollmentId)
            .ToDictionary(g => g.Key, g => g.ToList());
    }

    private List<GradingCategory> ChildrenOf(int parentId) =>
        _categories.Where(c => c.ParentId == parentId).ToList();

    public List<GradingCategory> TopLevel() =>
        _categories.Where(c => c.ParentId == null).ToList();

    
    public decimal WeightTotal() => TopLevel().Sum(c => c.Weight);

    public decimal? AttendanceRate(int enrollmentId, GradingPeriod period)
    {
        if (!_attendanceByEnrollment.TryGetValue(enrollmentId, out var records)) return null;

        var inPeriod = records.Where(r => r.GradingPeriod == period).ToList();
        if (inPeriod.Count == 0) return null;

        var attended = inPeriod.Count(r => r.Status != AttendanceStatus.Absent);
        return (decimal)attended / inPeriod.Count * 100m;
    }

    public (int Present, int Recorded) AttendanceCounts(int enrollmentId, GradingPeriod period)
    {
        if (!_attendanceByEnrollment.TryGetValue(enrollmentId, out var records)) return (0, 0);
        var inPeriod = records.Where(r => r.GradingPeriod == period).ToList();
        return (inPeriod.Count(r => r.Status != AttendanceStatus.Absent), inPeriod.Count);
    }

  
    public decimal? CategoryPercent(int enrollmentId, GradingPeriod period, GradingCategory category)
    {
        if (category.IsAttendance) return AttendanceRate(enrollmentId, period);

        var children = ChildrenOf(category.Id);
        if (children.Count > 0)
        {
            decimal weightWithData = 0;
            decimal weightedSum = 0;
            foreach (var child in children)
            {
                var percent = CategoryPercent(enrollmentId, period, child);
                if (percent is null) continue;
                weightWithData += child.Weight;
                weightedSum += child.Weight * percent.Value;
            }
            return weightWithData == 0 ? null : weightedSum / weightWithData;
        }

        // Leaf: earned points over attempted points.
        decimal earned = 0;
        decimal possible = 0;
        var marked = false;

        foreach (var a in _assessments)
        {
            if (a.CategoryId != category.Id || a.GradingPeriod != period) continue;
            if (!_scoreLookup.TryGetValue((a.Id, enrollmentId), out var value)) continue;
            earned += value;
            possible += a.MaxScore;
            marked = true;
        }

        if (!marked || possible == 0) return null;
        return earned / possible * 100m;
    }

  
    public decimal? PeriodGrade(int enrollmentId, GradingPeriod period)
    {
        decimal weightWithData = 0;
        decimal weightedSum = 0;

        foreach (var category in TopLevel())
        {
            var percent = CategoryPercent(enrollmentId, period, category);
            if (percent is null) continue;
            weightWithData += category.Weight;
            weightedSum += category.Weight * percent.Value;
        }

        return weightWithData == 0 ? null : weightedSum / weightWithData;
    }

   
    public decimal? FinalGrade(int enrollmentId)
    {
        var grades = new List<decimal>();
        foreach (GradingPeriod period in Enum.GetValues<GradingPeriod>())
        {
            var g = PeriodGrade(enrollmentId, period);
            if (g is not null) grades.Add(g.Value);
        }
        return grades.Count == 0 ? null : grades.Average();
    }

    public static string RemarkFor(decimal? finalGrade) => finalGrade switch
    {
        null => "No grades",
        >= GradeCalculator.PassingGrade => "Passing",
        _ => "At risk"
    };

    // ---------------------------------------------------------------- reports

   
    public List<CategoryResultDto> Breakdown(int enrollmentId, GradingPeriod period)
    {
        var top = TopLevel();

        decimal weightWithData = 0;
        foreach (var c in top)
        {
            if (CategoryPercent(enrollmentId, period, c) is not null) weightWithData += c.Weight;
        }

        var results = new List<CategoryResultDto>();
        foreach (var c in top)
        {
            var percent = CategoryPercent(enrollmentId, period, c);
            results.Add(new CategoryResultDto
            {
                CategoryId = c.Id,
                Name = c.Name,
                Weight = c.Weight,
                IsAttendance = c.IsAttendance,
                Percent = percent is null ? null : Round(percent.Value),
                EffectiveWeight = percent is null || weightWithData == 0
                    ? null
                    : Round(c.Weight / weightWithData * 100m),
                Children = ChildrenOf(c.Id).Select(child => new CategoryResultDto
                {
                    CategoryId = child.Id,
                    Name = child.Name,
                    Weight = child.Weight,
                    IsAttendance = child.IsAttendance,
                    Percent = CategoryPercent(enrollmentId, period, child) is { } p ? Round(p) : null
                }).ToList()
            });
        }
        return results;
    }

 
    public decimal? ClassCategoryAverage(GradingCategory category, GradingPeriod period)
    {
        decimal total = 0;
        var counted = 0;

        foreach (var enrollment in _enrollments)
        {
            if (!enrollment.IsActive) continue;
            var percent = CategoryPercent(enrollment.Id, period, category);
            if (percent is null) continue;
            total += percent.Value;
            counted++;
        }

        return counted == 0 ? null : Round(total / counted);
    }

    public int ItemCount(int categoryId, GradingPeriod period) =>
        _assessments.Count(a => a.CategoryId == categoryId && a.GradingPeriod == period);

    public StudentGradeDto StudentRow(Enrollment enrollment)
    {
        var final = FinalGrade(enrollment.Id);
        return new StudentGradeDto
        {
            EnrollmentId = enrollment.Id,
            StudentNumber = enrollment.Student?.StudentNumber ?? string.Empty,
            FullName = enrollment.Student is null
                ? string.Empty
                : $"{enrollment.Student.FirstName} {enrollment.Student.LastName}".Trim(),
            Prelim = Round(PeriodGrade(enrollment.Id, GradingPeriod.Prelim)),
            Midterm = Round(PeriodGrade(enrollment.Id, GradingPeriod.Midterm)),
            Finals = Round(PeriodGrade(enrollment.Id, GradingPeriod.Finals)),
            FinalGrade = Round(final),
            Remark = RemarkFor(final)
        };
    }

    public static decimal? Round(decimal? value) =>
        value is null ? null : Math.Round(value.Value, 2, MidpointRounding.AwayFromZero);

    public static decimal Round(decimal value) =>
        Math.Round(value, 2, MidpointRounding.AwayFromZero);
}
