using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Journal.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class OperationReceiptCursor : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "ChangeCursor",
                table: "Operations",
                type: "INTEGER",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ChangeCursor",
                table: "Operations");
        }
    }
}
