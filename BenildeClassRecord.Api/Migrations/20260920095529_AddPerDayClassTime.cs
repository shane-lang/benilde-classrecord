using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BenildeClassRecord.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddPerDayClassTime : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "DurationMinutes",
                table: "schedule_meeting_days",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<TimeOnly>(
                name: "StartTime",
                table: "schedule_meeting_days",
                type: "time(6)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DurationMinutes",
                table: "schedule_meeting_days");

            migrationBuilder.DropColumn(
                name: "StartTime",
                table: "schedule_meeting_days");
        }
    }
}
