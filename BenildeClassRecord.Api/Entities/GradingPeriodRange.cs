namespace BenildeClassRecord.Api.Entities;

public class GradingPeriodRange
{
    public int Id { get; set; }

    public int ClassId { get; set; }
    public Class? Class { get; set; }

    public GradingPeriod GradingPeriod { get; set; }

    public DateOnly StartDate { get; set; }

    public DateOnly EndDate { get; set; }
}