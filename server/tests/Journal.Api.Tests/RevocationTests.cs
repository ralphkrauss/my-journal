using System.IO.Pipelines;
using System.Net;
using Journal.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

public sealed class RevocationTests
{
    [Fact]
    public async Task RevocationDuringAttachmentUploadPreventsCommitAndRemovesTemporaryBytes()
    {
        using var factory = new JournalFactory();
        var (client, grant) = await factory.SetUp();
        using var ownedClient = client;
        var directory = Path.Combine(factory.Root, "attachments");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var watcher = new FileSystemWatcher(directory, ".upload-*");
        watcher.Created += (_, _) => started.TrySetResult();
        watcher.EnableRaisingEvents = true;
        var body = new Pipe();
        await body.Writer.WriteAsync(new byte[30]);
        var id = Guid.NewGuid();
        var uploading = factory.Server.SendAsync(context =>
        {
            context.Request.Method = "PUT";
            context.Request.Path = $"/v1/attachments/{id}";
            context.Request.Headers.Authorization = $"Bearer {grant.Token}";
            context.Request.ContentLength = 60;
            context.Request.Body = body.Reader.AsStream();
        });
        try
        {
            // Creating the temporary file proves the endpoint passed its initial authentication.
            await started.Task.WaitAsync(TimeSpan.FromSeconds(10));
            using var revoked = await client.DeleteAsync($"/v1/devices/{grant.DeviceId}");
            revoked.EnsureSuccessStatusCode();
        }
        finally
        {
            await body.Writer.WriteAsync(new byte[30]);
            await body.Writer.CompleteAsync();
            await uploading.WaitAsync(TimeSpan.FromSeconds(10));
            await body.Reader.CompleteAsync();
        }
        var response = await uploading;
        Assert.Equal((int)HttpStatusCode.Unauthorized, response.Response.StatusCode);
        Assert.Empty(Directory.EnumerateFiles(directory));
        await using var scope = factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
        Assert.False(await db.Attachments.AnyAsync());
    }

}
