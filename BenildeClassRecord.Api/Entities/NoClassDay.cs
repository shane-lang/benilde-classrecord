using System.ComponentModel.DataAnnotations;

namespace BenildeClassRecord.Api.Entities;

public class NoClassDay
{
    public int Id { get; set; }

    public int ClassId { get; set; }
    public Class? Class { get; set; }

    public DateOnly Date { get; set; }

    [MaxLength(120)]
    public string? Reason { get; set; }
}