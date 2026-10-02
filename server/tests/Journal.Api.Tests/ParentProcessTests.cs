using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;

namespace Journal.Api.Tests;

public sealed class ParentProcessTests
{
    // The Mac app passes its process ID. If the app crashes or is force quit, the server must not keep
    // running and holding the address and data directory the next launch needs.
    [Fact]
    public async Task TheServerStopsCleanlyAfterTheAppThatStartedItExits()
    {
        var root = Path.Combine(Path.GetTempPath(), "journal-parent-" + Guid.NewGuid().ToString("N"));
        using var app = Process.Start(new ProcessStartInfo("sleep", "120") { UseShellExecute = false }) ??
            throw new InvalidOperationException("The stand-in app did not start.");
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        start.ArgumentList.Add(typeof(Program).Assembly.Location);
        start.Environment["Journal__DataDirectory"] = root;
        start.Environment["ASPNETCORE_URLS"] = "http://127.0.0.1:0";
        start.Environment["Journal__ParentProcessId"] = app.Id.ToString(CultureInfo.InvariantCulture);
        using var server = new Process { StartInfo = start };
        var log = new ConcurrentQueue<string>();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void Record(object sender, DataReceivedEventArgs line)
        {
            if (line.Data is not { } text)
            {
                return;
            }
            log.Enqueue(text);
            if (text.Contains("Application started", StringComparison.Ordinal))
            {
                started.TrySetResult();
            }
        }
        server.OutputDataReceived += Record;
        server.ErrorDataReceived += Record;
        Assert.True(server.Start());
        server.BeginOutputReadLine();
        server.BeginErrorReadLine();
        try
        {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(30));
            // Past its first check, the server keeps running while the app does.
            await Task.Delay(TimeSpan.FromSeconds(2.5));
            Assert.False(server.HasExited, string.Join('\n', log));

            app.Kill();
            await app.WaitForExitAsync();
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            await server.WaitForExitAsync(timeout.Token);
            Assert.Equal(0, server.ExitCode);
            Assert.Contains(log, line => line.Contains("has exited. Stopping the server.", StringComparison.Ordinal));
        }
        finally
        {
            if (!app.HasExited)
            {
                app.Kill();
                await app.WaitForExitAsync();
            }
            if (!server.HasExited)
            {
                server.Kill(entireProcessTree: true);
                await server.WaitForExitAsync();
            }
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }
}
