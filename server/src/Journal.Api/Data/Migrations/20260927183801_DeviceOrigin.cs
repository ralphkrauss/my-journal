using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Journal.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class DeviceOrigin : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "ApprovedByDeviceId",
                table: "Devices",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CreatedVia",
                table: "Devices",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ApprovedByDeviceId",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "CreatedVia",
                table: "Devices");
        }
    }
}
