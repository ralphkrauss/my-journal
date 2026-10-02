using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Journal.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class SyncIdentityAndPairingCheck : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SyncId",
                table: "Vaults",
                type: "TEXT",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<long>(
                name: "SyncIdCursor",
                table: "Vaults",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0L);

            migrationBuilder.AddColumn<string>(
                name: "ApproverKey",
                table: "PairRequests",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "Declined",
                table: "PairRequests",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "KeyCommitment",
                table: "PairRequests",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SyncId",
                table: "Vaults");

            migrationBuilder.DropColumn(
                name: "SyncIdCursor",
                table: "Vaults");

            migrationBuilder.DropColumn(
                name: "ApproverKey",
                table: "PairRequests");

            migrationBuilder.DropColumn(
                name: "Declined",
                table: "PairRequests");

            migrationBuilder.DropColumn(
                name: "KeyCommitment",
                table: "PairRequests");
        }
    }
}
