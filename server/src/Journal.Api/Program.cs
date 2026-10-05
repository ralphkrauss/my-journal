using Journal.Api.Data;
using Journal.Api.Features;
using Journal.Api.Hosting;
using Journal.Api.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Connections;
using Microsoft.EntityFrameworkCore;

var command = MaintenanceCommand.Parse(args);
// appsettings.json (logging levels included) is read from the server's own folder, whatever directory it was started
// from: the packaged launcher and the Mac app's embedded server don't set one.
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = command.ConfigurationArgs, ContentRootPath = ContentRoot.For(AppContext.BaseDirectory) });
if (command.Name is not null || command.Invalid)
{
    // Maintenance output goes to stdout; its log events go to stderr.
    using var loggers = LoggerFactory.Create(logging => logging
        .AddConfiguration(builder.Configuration.GetSection("Logging"))
        .AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace));
    Environment.ExitCode = await Maintenance.Run(command, builder.Configuration, new AuditLog(loggers.CreateLogger<AuditLog>()));
    return;
}
var root = ServerConfiguration.DataDirectory(builder.Configuration);
if (Path.Exists(Path.Combine(root, BackupArchive.RestoreMarker)))
{
    Console.Error.WriteLine("A restore did not finish. Preserve this data directory and restore a complete backup into an empty directory before starting Journal.");
    Environment.ExitCode = 1;
    return;
}
bool forwardedHeaders;
try
{
    forwardedHeaders = NetworkPolicy.ConfigureForwardedHeaders(builder);
    PublicOrigin.Validate(builder.Configuration);
}
catch (FormatException error)
{
    Console.Error.WriteLine(error.Message);
    Environment.ExitCode = 1;
    return;
}
NetworkPolicy.ConfigureHostFiltering(builder);
var paths = new StoragePaths(root);
Directory.CreateDirectory(root);
Directory.CreateDirectory(paths.AttachmentDirectory);
if (!OperatingSystem.IsWindows())
{
    File.SetUnixFileMode(root, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
}

builder.Services.AddSingleton(paths);
builder.Services.AddSingleton<WriteGate>();
builder.Services.AddSingleton(new SyncSignal(builder.Configuration.GetValue("Journal:SyncWaitCapacity", SyncSignal.DefaultCapacity)));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<AuditLog>();
builder.Services.AddSingleton<RecoveryAttempts>();
builder.Services.AddSingleton<SetupAttempts>();
builder.Services.AddDbContext<JournalDb>(options => options.UseSqlite(DatabaseStartup.ConnectionString(root)).AddInterceptors(new SecureDeleteInterceptor()));
// Agent access through MCP (protocol/agent-access-server.md).
builder.Services.AddSingleton<AgentAuthorizations>();
builder.Services.AddSingleton<AgentTokens>();
builder.Services.AddSingleton<McpLimits>();
builder.Services.AddSingleton<OAuthClients>();
builder.Services.AddHttpClient(OAuthClients.HttpClientName).ConfigurePrimaryHttpMessageHandler(OAuthClients.Handler);
builder.Services.AddHostedService<AgentExpiry>();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.RespectNullableAnnotations = true;
    options.SerializerOptions.RespectRequiredConstructorParameters = true;
});
builder.Services.AddProblemDetails(options => options.CustomizeProblemDetails = Problems.Customize);
// Request errors raised while reading a body (such as exceeding its size limit) keep their status.
builder.Services.AddExceptionHandler(options => options.StatusCodeSelector = error =>
    error is BadHttpRequestException badRequest ? badRequest.StatusCode : StatusCodes.Status500InternalServerError);
// Only device bearer credentials: no cookies or signed tokens, so no data protection keys are needed.
builder.Services.AddAuthenticationCore(options => options.DefaultScheme = DeviceAuthentication.SchemeName);
new AuthenticationBuilder(builder.Services).AddScheme<AuthenticationSchemeOptions, DeviceAuthentication>(DeviceAuthentication.SchemeName, null);
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(RateLimits.Configure);
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = BodyLimits.Default);
var app = builder.Build();
if (forwardedHeaders)
{
    app.UseForwardedHeaders();
}
app.UseExceptionHandler();
app.UseStatusCodePages();
app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    await next(context);
});
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();
bool ready;
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
    var audit = scope.ServiceProvider.GetRequiredService<AuditLog>();
    ready = await DatabaseStartup.Migrate(db, root, audit, CancellationToken.None);
    if (ready)
    {
        await db.Database.ExecuteSqlRawAsync("PRAGMA journal_mode=WAL;");
        await SyncIdentity.EnsureAssigned(db);
        await EncryptionPurge.Finish(db, paths, audit, CancellationToken.None);
        await PairingEndpoints.RemoveExpired(db, scope.ServiceProvider.GetRequiredService<TimeProvider>().GetUtcNow(), audit, CancellationToken.None);
        await AgentGrantEndpoints.RemoveUnfinished(db, scope.ServiceProvider.GetRequiredService<AgentAuthorizations>(), scope.ServiceProvider.GetRequiredService<WriteGate>(), audit, CancellationToken.None, all: true);
        await AgentGrantEndpoints.PurgeExpired(db, scope.ServiceProvider.GetRequiredService<WriteGate>(), scope.ServiceProvider.GetRequiredService<TimeProvider>(), audit, CancellationToken.None);
        if (PublicOrigin.UnusableJournalUrl(app.Configuration))
        {
            audit.JournalUrlNotUsedForAgents();
        }
        if (!await db.Vaults.AnyAsync() && await SetupCode.Read(paths.BootstrapFile, CancellationToken.None) is null)
        {
            var replaced = File.Exists(paths.BootstrapFile);
            SetupCode.Write(paths.BootstrapFile);
            audit.SetupCodeWritten(replaced ? "the previous file was empty, damaged or in an older format" : "no setup code existed");
        }
        if (!await db.Vaults.AnyAsync())
        {
            audit.SetupPending();
        }
    }
}
if (!ready)
{
    // Disposing flushes the log message explaining why the server stopped.
    await app.DisposeAsync();
    Environment.ExitCode = 1;
    return;
}
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/ready", async (JournalDb db, CancellationToken ct) => await db.Database.CanConnectAsync(ct) ? Results.Ok(new { status = "ready", instanceId = app.Configuration["Journal:InstanceId"] }) : Results.StatusCode(503));
app.MapAccounts();
app.MapPairing();
app.MapSync();
app.MapAttachments();
app.MapEncryption();
app.MapMcp();
app.MapOAuth();
app.MapAgentGrants();
try
{
    app.Run();
}
catch (IOException exception) when (exception.InnerException is AddressInUseException)
{
    Console.Error.WriteLine("The server address is already in use. Stop the other server or choose another address.");
    Environment.ExitCode = 1;
}

public partial class Program
{
}
