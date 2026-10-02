namespace Journal.Api.Security;

// Wrong secrets from every client address together. Per-address limits don't stop guessing spread over many
// addresses, so after `budget` failures within Window each further attempt waits, twice as long as the previous
// wait, up to MaximumWait.
public abstract class AttemptBudget(TimeProvider clock, int budget)
{
    public static readonly TimeSpan Window = TimeSpan.FromHours(1);
    public static readonly TimeSpan FirstWait = TimeSpan.FromSeconds(30);
    public static readonly TimeSpan MaximumWait = TimeSpan.FromMinutes(15);

    private readonly Lock gate = new();
    // Attempts that failed or are still being checked, oldest first.
    private readonly List<DateTimeOffset> failures = [];
    private DateTimeOffset allowedAt = DateTimeOffset.MinValue;

    // Reserves an attempt, counted as a failure until Succeeded is called, so concurrent guesses can't
    // exceed the budget. Returns how long to wait instead when no attempt is allowed now.
    public TimeSpan? Reserve()
    {
        var now = clock.GetUtcNow();
        lock (gate)
        {
            failures.RemoveAll(time => time <= now - Window);
            if (now < allowedAt)
            {
                return allowedAt - now;
            }
            failures.Add(now);
            if (failures.Count >= budget)
            {
                var doublings = Math.Min(failures.Count - budget, 16);
                var wait = TimeSpan.FromTicks(Math.Min(FirstWait.Ticks << doublings, MaximumWait.Ticks));
                allowedAt = now + wait;
                Paused(failures.Count, (int)Math.Ceiling(wait.TotalSeconds));
            }
            return null;
        }
    }

    // The reserved attempt used the right secret, so it isn't a failure. A wait it started still applies.
    public void Succeeded()
    {
        lock (gate)
        {
            if (failures.Count > 0)
            {
                failures.RemoveAt(failures.Count - 1);
            }
        }
    }

    protected abstract void Paused(int failures, int seconds);
}

// Anonymous POST /v1/recovery: connected devices never need it, and pairing and every device-authenticated
// request are unaffected.
public sealed class RecoveryAttempts(TimeProvider clock, AuditLog audit) : AttemptBudget(clock, Budget)
{
    public const int Budget = 20;

    protected override void Paused(int failures, int seconds) => audit.RecoveryPaused(failures, seconds);
}

// Anonymous POST /v1/setup and /v1/setup/check. The code has about 30 bits, so this caps guessing at about a hundred
// tries a day.
public sealed class SetupAttempts(TimeProvider clock, AuditLog audit) : AttemptBudget(clock, Budget)
{
    public const int Budget = 10;

    protected override void Paused(int failures, int seconds) => audit.SetupPaused(failures, seconds);
}
