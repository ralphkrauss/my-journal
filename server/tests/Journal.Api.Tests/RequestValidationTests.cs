using System.Net;
using System.Text;
using Journal.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

public sealed class RequestValidationTests
{
    [Theory]
    [InlineData("/v1/recovery", "{\"recoverySecret\":null,\"deviceName\":\"Phone\"}")]
    [InlineData("/v1/recovery", "{\"deviceName\":\"Phone\"}")]
    [InlineData("/v1/pairing/lookup", "{\"code\":null}")]
    [InlineData("/v1/pairing/00000000-0000-0000-0000-000000000001/approve", "{\"deviceToken\":null,\"encryptedGrant\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}")]
    public async Task MissingOrNullCredentialsAreRejectedWithoutEnrollment(string path, string json)
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        using var ownedClient = client;
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        using var response = await client.PostAsync(path, content);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await using var scope = factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<JournalDb>();
        Assert.Equal(1, await db.Devices.CountAsync());
        Assert.False(await db.PairRequests.AnyAsync());
    }
}
