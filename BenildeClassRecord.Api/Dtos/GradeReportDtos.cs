namespace BenildeClassRecord.Api.Dtos;

public class StudentGradeDto
{
    public int EnrollmentId { get; set; }
    public string StudentNumber { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;

    public decimal? Prelim { get; set; }
    public decimal? Midterm { get; set; }
    public decimal? Finals { get; set; }

    public decimal? FinalGrade { get; set; }

    public string Remark { get; set; } = string.Empty;
}

public class CategoryResultDto
{
    public int CategoryId { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Weight { get; set; }
    public bool IsAttendance { get; set; }

    public decimal? Percent { get; set; }

    public decimal? EffectiveWeight { get; set; }

    public List<CategoryResultDto> Children { get; set; } = new();
}

public class CategoryAverageDto
{
    public int CategoryId { get; set; }
    public int? ParentId { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Weight { get; set; }
    public bool IsAttendance { get; set; }

    public decimal? Average { get; set; }

    public int ItemCount { get; set; }
}

public class ClassStandingDto
{
    public int ClassId { get; set; }
    public string SubjectName { get; set; } = string.Empty;
    public decimal PassingGrade { get; set; }

    public decimal? PrelimAverage { get; set; }
    public decimal? MidtermAverage { get; set; }
    public decimal? FinalsAverage { get; set; }
    public decimal? ClassAverage { get; set; }

    public int PassingCount { get; set; }
    public int AtRiskCount { get; set; }

    public bool WeightsUnbalanced { get; set; }
    public decimal WeightTotal { get; set; }

    public string GradingPeriod { get; set; } = string.Empty;

    public List<CategoryAverageDto> CategoryAverages { get; set; } = new();

    public List<StudentGradeDto> Students { get; set; } = new();
}

public class StudentReportDto
{
    public int EnrollmentId { get; set; }
    public string StudentNumber { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string GradingPeriod { get; set; } = string.Empty;

    public decimal? PeriodGrade { get; set; }
    public decimal? FinalGrade { get; set; }
    public string Remark { get; set; } = string.Empty;

    public decimal? AttendanceRate { get; set; }
    public int DaysPresent { get; set; }
    public int DaysRecorded { get; set; }

    public List<CategoryResultDto> Categories { get; set; } = new();
}