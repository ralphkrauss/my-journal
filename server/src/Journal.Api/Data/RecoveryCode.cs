using Journal.Api.Security;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Data;

public static class RecoveryCode
{
    // Requires access to the server database; no remotely callable code-generation route.
    public static async Task<string> Create(string root)
    {
        var database = Path.Combine(Path.GetFullPath(root), "journal.db");
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = database, Mode = SqliteOpenMode.ReadWrite }.ToString());
        await connection.OpenAsync();
        using var transaction = connection.BeginTransaction();
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE Vaults SET RecoveryHash = $hash WHERE Id = 1 AND FormatVersion = 4";
        var code = Convert.ToHexStringLower(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        command.Parameters.AddWithValue("$hash", Secrets.Hash(code));
        if (await command.ExecuteNonQueryAsync() != 1)
        {
            throw new InvalidOperationException("One-time recovery codes are only available for journals created without encryption or a password.");
        }
        await transaction.CommitAsync();
        return code;
    }
}
