namespace Journal.Api.Features;

// Wakes devices waiting for changes (GET /v1/sync/wait) and keeps one wait per device: a newer wait from a device
// replaces its older one. A woken wait reads the database again, so an extra notification costs one check and a
// missing one at most a wait cycle; nothing is lost either way (docs/design/sync-protocol-efficiency.md §4.3).
public sealed class SyncSignal(int capacity = SyncSignal.DefaultCapacity)
{
    // Waits held at once across all devices, as defence in depth: each needs a device credential, and one device
    // holds at most one, so a single-person server stays far below it.
    public const int DefaultCapacity = 64;
    private readonly Lock gate = new();
    private readonly Dictionary<Guid, Registration> waiters = [];
    private TaskCompletionSource current = NewSource();

    private static TaskCompletionSource NewSource() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    // Completes at the next Notify. A wait takes it before reading the database, so a change committed after that
    // read still wakes it.
    public Task Current
    {
        get
        {
            lock (gate)
            {
                return current.Task;
            }
        }
    }

    // Waits for `notified` (a Current task), the wait being replaced, or `token`. Nothing stays attached to the
    // shared `notified` task afterwards, however the wait ends: a wait that times out with no write since must not
    // leave a continuation behind for every cycle (red team RT-S3).
    public static async Task WaitForSignal(Task notified, Task superseded, CancellationToken token)
    {
        ArgumentNullException.ThrowIfNull(notified);
        using var stop = CancellationTokenSource.CreateLinkedTokenSource(token);
        // WaitAsync removes its continuation from `notified` when `stop` is cancelled.
        var signalled = notified.WaitAsync(stop.Token);
        try
        {
            await Task.WhenAny(signalled, superseded).ConfigureAwait(false);
        }
        finally
        {
            await stop.CancelAsync().ConfigureAwait(false);
        }
    }

    // Called once a commit that waits must see (a change, a revocation, a new identity) has been attempted.
    public void Notify()
    {
        TaskCompletionSource previous;
        lock (gate)
        {
            previous = current;
            current = NewSource();
        }
        previous.TrySetResult();
    }

    // Registers a device's wait, replacing (and ending) the wait it had before. Null when the server already holds
    // `capacity` waits of other devices; replacing a device's own wait is never refused.
    public Registration? Register(Guid device)
    {
        var registration = new Registration(device);
        Registration? replaced;
        lock (gate)
        {
            if (!waiters.TryGetValue(device, out replaced) && waiters.Count >= capacity)
            {
                return null;
            }
            waiters[device] = registration;
        }
        replaced?.Supersede();
        return registration;
    }

    // Removes a wait only while it is still its device's current one, so a replaced wait ending later can't remove
    // the wait that replaced it.
    public void Release(Registration registration)
    {
        ArgumentNullException.ThrowIfNull(registration);
        lock (gate)
        {
            if (waiters.TryGetValue(registration.Device, out var entry) && ReferenceEquals(entry, registration))
            {
                waiters.Remove(registration.Device);
            }
        }
    }

    public int WaiterCount
    {
        get
        {
            lock (gate)
            {
                return waiters.Count;
            }
        }
    }

    public sealed class Registration
    {
        private readonly TaskCompletionSource superseded = new(TaskCreationOptions.RunContinuationsAsynchronously);

        internal Registration(Guid device) => Device = device;

        public Guid Device
        {
            get;
        }

        // Completes when a newer wait from the same device replaces this one.
        public Task Superseded => superseded.Task;

        internal void Supersede() => superseded.TrySetResult();
    }
}
