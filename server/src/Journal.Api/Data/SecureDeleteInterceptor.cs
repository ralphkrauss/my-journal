using System.Data.Common;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Journal.Api.Data;

// Overwrites deleted content in the database file, so key material removed from it (agent token wraps) doesn't stay
// in free pages (protocol/agent-access-server.md, Limits, audit and lifecycle).
public sealed class SecureDeleteInterceptor : DbConnectionInterceptor
{
    private const string Pragma = "PRAGMA secure_delete=ON;";

    public override void ConnectionOpened(DbConnection connection, ConnectionEndEventData eventData)
    {
        ArgumentNullException.ThrowIfNull(connection);
        using var command = connection.CreateCommand();
        command.CommandText = Pragma;
        command.ExecuteNonQuery();
    }

    public override async Task ConnectionOpenedAsync(DbConnection connection, ConnectionEndEventData eventData, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        await using var command = connection.CreateCommand();
        command.CommandText = Pragma;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
