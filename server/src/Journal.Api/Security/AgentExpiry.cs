using Journal.Api.Data;
using Journal.Api.Features;

namespace Journal.Api.Security;

// Every five minutes: ends access that expired, removes key wraps no live token needs, and deletes grants whose
// approval was never completed (protocol/agent-access-server.md, Limits, audit and lifecycle).
public sealed class AgentExpiry(IServiceScopeFactory scopes, WriteGate gate, TimeProvider clock, AuditLog audit, AgentAuthorizations authorizations) : BackgroundService
{
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval, clock);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await using var scope = scopes.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
            await AgentGrantEndpoints.RemoveUnfinished(db, authorizations, gate, audit, stoppingToken);
            await AgentGrantEndpoints.PurgeExpired(db, gate, clock, audit, stoppingToken);
        }
    }
}
