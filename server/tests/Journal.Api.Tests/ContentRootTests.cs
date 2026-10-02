using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.RegularExpressions;
using Journal.Api.Hosting;

namespace Journal.Api.Tests;

public sealed partial class ContentRootTests
{
    [GeneratedRegex(@"Now listening on: (http://127\.0\.0\.1:\d+)")]
    private static partial Regex Listening();

    // The packaged launcher and the Mac app's embedded server start the server from another directory. Its own
    // appsettings.json must still apply, so requests and their query strings aren't logged.
    [Fact]
    public async Task StartedFromAnotherDirectoryTheServerKeepsItsLoggingSettings()
    {
        var elsewhere = Directory.CreateTempSubdirectory("journal-elsewhere-");
        var root = Path.Combine(Path.GetTempPath(), "journal-content-root-" + Guid.NewGuid().ToString("N"));
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, WorkingDirectory = elsewhere.FullName };
        start.ArgumentList.Add(typeof(Program).Assembly.Location);
        start.Environment["Journal__DataDirectory"] = root;
        start.Environment["ASPNETCORE_URLS"] = "http://127.0.0.1:0";
        start.Environment.Remove("ASPNETCORE_ENVIRONMENT");
        start.Environment.Remove("DOTNET_ENVIRONMENT");
        using var server = new Process { StartInfo = start };
        var log = new ConcurrentQueue<string>();
        var address = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Record(object sender, DataReceivedEventArgs line)
        {
            if (line.Data is not { } text)
            {
                return;
            }
            log.Enqueue(text);
            if (Listening().Match(text) is { Success: true } match)
            {
                address.TrySetResult(match.Groups[1].Value);
            }
        }
        server.OutputDataReceived += Record;
        server.ErrorDataReceived += Record;
        Assert.True(server.Start());
        server.BeginOutputReadLine();
        server.BeginErrorReadLine();
        try
        {
            using var client = new HttpClient { BaseAddress = new Uri(await address.Task.WaitAsync(TimeSpan.FromSeconds(30))) };
            (await client.GetAsync("/health?marker=query-must-not-be-logged")).EnsureSuccessStatusCode();
            await Task.Delay(TimeSpan.FromSeconds(1));
            Assert.DoesNotContain(log, line => line.Contains("query-must-not-be-logged", StringComparison.Ordinal));
            Assert.DoesNotContain(log, line => line.Contains("Request starting", StringComparison.Ordinal));
        }
        finally
        {
            if (!server.HasExited)
            {
                server.Kill();
                await server.WaitForExitAsync();
            }
            elsewhere.Delete(true);
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }

    // The Mac app's embedded server keeps its settings in the bundle's Resources folder.
    [Fact]
    public void TheMacBundlesSettingsAreFoundBesideItsExecutable()
    {
        var bundle = Directory.CreateTempSubdirectory("journal-bundle-");
        try
        {
            var executable = Directory.CreateDirectory(Path.Combine(bundle.FullName, "Contents", "MacOS")).FullName;
            var resources = Directory.CreateDirectory(Path.Combine(bundle.FullName, "Contents", "Resources")).FullName;
            File.WriteAllText(Path.Combine(resources, "appsettings.json"), "{}");
            Assert.Equal(resources, ContentRoot.For(executable));
            File.WriteAllText(Path.Combine(executable, "appsettings.json"), "{}");
            Assert.Equal(executable, ContentRoot.For(executable));
        }
        finally
        {
            bundle.Delete(true);
        }
    }
}
