using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Features;

namespace Journal.Api.Tests;

public sealed class ProtectionModeTests
{
    [Theory]
    [InlineData(2)]
    [InlineData(3)]
    public async Task PasswordVaultPreservesVersionAndRequiresRecoveryAuthentication(int version)
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp(version);
        using (client)
        {
            using var envelope = JsonDocument.Parse(await client.GetStringAsync("/v1/recovery"));
            Assert.Equal(version, envelope.RootElement.GetProperty("formatVersion").GetInt32());
            client.DefaultRequestHeaders.Authorization = null;
            var denied = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('b', 64), "Other device"));
            Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/sync/")).StatusCode);
            var accepted = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Recovered device"));
            accepted.EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task PasswordlessServerRequiresDeviceAuthorizationAndConsumesAdministratorRecoveryCode()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var setup = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        (await client.PostAsJsonAsync("/v1/setup", new SetupRequest(setup, "", "", 0, new string('a', 64), "Mac", 4))).EnsureSuccessStatusCode();
        using var envelope = JsonDocument.Parse(await client.GetStringAsync("/v1/recovery"));
        Assert.Equal(("", 0, 4), (envelope.RootElement.GetProperty("salt").GetString(), envelope.RootElement.GetProperty("iterations").GetInt32(), envelope.RootElement.GetProperty("formatVersion").GetInt32()));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/sync/")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest("", "Phone"))).StatusCode);
        var code = await Journal.Api.Data.RecoveryCode.Create(factory.Root);
        var response = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(code, "Phone"));
        response.EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(code, "Replay"))).StatusCode);
        var grant = await response.Content.ReadFromJsonAsync<DeviceGrant>();
        Assert.NotNull(grant);
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", grant.Token);
        (await client.GetAsync("/v1/sync/")).EnsureSuccessStatusCode();
        var id = Guid.NewGuid();
        (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent([42]))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task UnknownRecoveryVersionCannotInitializeVault()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var code = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        var response = await client.PostAsJsonAsync("/v1/setup", new SetupRequest(code, Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", 99));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True(File.Exists(Path.Combine(factory.Root, "setup-code")));
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/v1/recovery")).StatusCode);
    }
}
