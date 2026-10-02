using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Journal.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AgentSettingsRevision : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Existing grants start at the first revision their devices will read.
            migrationBuilder.AddColumn<long>(
                name: "Revision",
                table: "AgentGrants",
                type: "INTEGER",
                nullable: false,
                defaultValue: 1L);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Revision",
                table: "AgentGrants");
        }
    }
}
