using Journal.Api.Security;
using Microsoft.Data.Sqlite;

namespace Journal.Api.Data;

// A maintenance command and the remaining arguments, which configure the server exactly as a normal start does.
public sealed record MaintenanceCommand(string? Name, string? Value, string[] ConfigurationArgs, bool Invalid)
{
    private static readonly string[] ValueCommands = ["--backup", "--restore"];
    private static readonly string[] SwitchCommands = ["--health-check", "--recovery-code", "--setup-code"];

    public static MaintenanceCommand Parse(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);
        string? name = null;
        string? value = null;
        var invalid = false;
        var remaining = new List<string>();
        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            var takesValue = ValueCommands.Contains(argument);
            if (!takesValue && !SwitchCommands.Contains(argument))
            {
                remaining.Add(argument);
                continue;
            }
            invalid |= name is not null;
            name = argument;
            if (takesValue)
            {
                if (index + 1 < args.Length && !args[index + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    value = args[++index];
                }
                else
                {
                    invalid = true;
                }
            }
        }
        return new MaintenanceCommand(name, value, [.. remaining], invalid);
    }
}

public static class ServerConfiguration
{
    // Shared by the server and every maintenance command, so appsettings, environment variables
    // and --Journal:DataDirectory= options always select the same data directory.
    public static string DataDirectory(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return Path.GetFullPath(configuration["Journal:DataDirectory"] ?? Path.Combine(AppContext.BaseDirectory, "data"));
    }
}

public static class Maintenance
{
    public const string Usage = "Usage: --backup <new-directory>, --restore <backup-directory>, --health-check, --setup-code, or --recovery-code. Configuration options such as --Journal:DataDirectory=<directory> are also accepted.";

    public static async Task<int> Run(MaintenanceCommand command, IConfiguration configuration, AuditLog audit)
    {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(audit);
        if (command.Invalid || command.Name is null)
        {
            Console.Error.WriteLine(Usage);
            return 2;
        }
        return command.Name switch
        {
            "--health-check" => await HealthCheck(),
            "--recovery-code" => await CreateRecoveryCode(ServerConfiguration.DataDirectory(configuration)),
            "--setup-code" => await ShowSetupCode(ServerConfiguration.DataDirectory(configuration)),
            _ => await BackupOrRestore(command, ServerConfiguration.DataDirectory(configuration), audit),
        };
    }

    private static async Task<int> HealthCheck()
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
            var result = await client.GetAsync(Environment.GetEnvironmentVariable("JOURNAL_HEALTH_URL") ?? "http://127.0.0.1:8080/ready");
            return result.IsSuccessStatusCode ? 0 : 1;
        }
        catch (HttpRequestException) { return 1; }
        catch (TaskCanceledException) { return 1; }
    }

    // Prints the code a person enters in the app to set up this server. It is never logged.
    private static async Task<int> ShowSetupCode(string root)
    {
        var code = await SetupCode.Read(new StoragePaths(root).BootstrapFile, CancellationToken.None);
        if (code is null)
        {
            Console.Error.WriteLine("There is no setup code. This server is already set up, or it hasn't started yet.");
            return 1;
        }
        var address = ServerAddress(Environment.GetEnvironmentVariable("JOURNAL_URL"));
        Console.WriteLine((address is null ? "Setup code: " : "Setup code for " + address + ": ") + SetupCode.Display(code));
        return 0;
    }

    // The HTTPS address the server is published at (JOURNAL_URL in the Compose deployment), so a person with
    // several servers can tell which one the code belongs to. Anything else is not shown.
    private static string? ServerAddress(string? configured)
    {
        var text = configured?.Trim().TrimEnd('/');
        return Uri.TryCreate(text, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps && !string.IsNullOrEmpty(uri.Host) ? text : null;
    }

    private static async Task<int> CreateRecoveryCode(string root)
    {
        try
        {
            Console.WriteLine(await RecoveryCode.Create(root));
            return 0;
        }
        catch (Exception error) when (error is SqliteException or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Could not create a recovery code: " + error.Message);
            return 1;
        }
    }

    private static async Task<int> BackupOrRestore(MaintenanceCommand command, string root, AuditLog audit)
    {
        var archive = Path.GetFullPath(command.Value ?? throw new InvalidOperationException("Missing directory."));
        try
        {
            if (command.Name == "--backup")
            {
                await BackupArchive.Create(root, archive);
                audit.BackupCreated();
                Console.WriteLine("Backup created. It retains your chosen encryption mode. Keep your password or recovery key separately.");
            }
            else
            {
                var signedOut = await BackupArchive.Restore(archive, root);
                audit.BackupRestored(signedOut);
                Console.WriteLine("Backup restored to " + root + ".");
                Console.WriteLine(signedOut == 1
                    ? "1 device was signed out, because the backup may include access you revoked later."
                    : signedOut + " devices were signed out, because the backup may include access you revoked later.");
                Console.WriteLine("Reconnect each device you still use: on the device, choose Connect Again and enter your password or recovery key.");
                Console.WriteLine("For a journal without a password, run --recovery-code once for each device.");
            }
            return 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SqliteException)
        {
            var reason = error is SqliteException ? "The backup database could not be read or uses an unsupported format." : error.Message;
            Console.Error.WriteLine("Backup or restore could not finish: " + reason);
            Console.Error.WriteLine("Preserve the original backup and data directory before retrying.");
            return 1;
        }
    }
}
