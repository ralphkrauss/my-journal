using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;

namespace Journal.Api.Hosting;

// The app that started this server, from Journal:ParentProcessId. The server stops when that process exits,
// so an app that crashed or was force quit does not leave the server holding its address and data directory.
// Without the setting (containers, the standalone package) the server runs until it is stopped.
public sealed class ParentProcess
{
    public const string ProcessIdKey = "Journal:ParentProcessId";
    // Start times of one process read at different moments can differ slightly on some platforms. A process
    // that reuses the ID started later, after the watched process had already been running.
    private static readonly TimeSpan StartTimeTolerance = TimeSpan.FromSeconds(1);
    private readonly DateTime? startTime;

    private ParentProcess(int id, DateTime? startTime)
    {
        Id = id;
        this.startTime = startTime;
    }

    public int Id
    {
        get;
    }

    // Null when the setting is absent. A value that is not a process ID throws FormatException.
    public static int? ConfiguredId(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var value = configuration[ProcessIdKey];
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }
        if (!int.TryParse(value.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var id) || id <= 0)
        {
            throw new FormatException($"{ProcessIdKey} must be the ID of the process that started the server.");
        }
        return id;
    }

    // The running process with this ID, or null if there is none. Its start time, where the platform reports
    // it, keeps a later process that reuses the ID from being mistaken for it.
    public static ParentProcess? Find(int id)
    {
        using var process = Open(id);
        return process is null ? null : new ParentProcess(id, StartTime(process));
    }

    public bool IsRunning()
    {
        using var process = Open(Id);
        if (process is null)
        {
            return false;
        }
        if (startTime is not { } expected || StartTime(process) is not { } current)
        {
            return true;
        }
        return (current - expected).Duration() <= StartTimeTolerance;
    }

    private static Process? Open(int id)
    {
        try
        {
            return Process.GetProcessById(id);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static DateTime? StartTime(Process process)
    {
        try
        {
            return process.StartTime.ToUniversalTime();
        }
        catch (Exception error) when (error is InvalidOperationException or Win32Exception or NotSupportedException)
        {
            return null;
        }
    }
}

// Polls the parent process and stops the server gracefully once it has exited.
public sealed partial class ParentProcessWatchdog(ParentProcess parent, IHostApplicationLifetime lifetime, ILogger<ParentProcessWatchdog> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(2);
    private readonly ILogger logger = logger;

    // Registers the watchdog when Journal:ParentProcessId is set. Returns false if that process is no longer
    // running, so the server should not start. A value that is not a process ID throws FormatException.
    public static bool Configure(WebApplicationBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);
        if (ParentProcess.ConfiguredId(builder.Configuration) is not { } id)
        {
            return true;
        }
        if (ParentProcess.Find(id) is not { } parent)
        {
            return false;
        }
        builder.Services.AddSingleton(parent);
        builder.Services.AddHostedService<ParentProcessWatchdog>();
        return true;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            if (!parent.IsRunning())
            {
                ParentExited(parent.Id);
                lifetime.StopApplication();
                return;
            }
        }
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "The process that started the server ({ProcessId}) has exited. Stopping the server.")]
    private partial void ParentExited(int processId);
}
