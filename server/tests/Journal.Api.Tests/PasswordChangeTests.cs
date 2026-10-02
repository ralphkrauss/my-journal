using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Features;

namespace Journal.Api.Tests;

public sealed class PasswordChangeTests
{
    private static ChangePasswordRequest Change(string current, byte marker, int version = 2) => new(
        current, Convert.ToBase64String(Enumerable.Repeat(marker, 16).ToArray()), Convert.ToBase64String(Enumerable.Repeat(marker, 60).ToArray()),
        600_000, new string('b', 64), version);

    [Fact]
    public async Task ChangingThePasswordRequiresTheCurrentOneAndReplacesTheWholeEnvelope()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(2);
        var wrong = await owner.PostAsJsonAsync("/v1/recovery/password", Change(new string('z', 64), 5));
        Assert.Equal(HttpStatusCode.Forbidden, wrong.StatusCode);
        Assert.Equal("wrong_password", (await wrong.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        Assert.Equal(HttpStatusCode.BadRequest, (await owner.PostAsJsonAsync("/v1/recovery/password", Change(new string('a', 64), 5, version: 3))).StatusCode);
        var before = await owner.GetStringAsync("/v1/recovery/envelope");

        Assert.Equal(HttpStatusCode.NoContent, (await owner.PostAsJsonAsync("/v1/recovery/password", Change(new string('a', 64), 5))).StatusCode);
        var envelope = await owner.GetFromJsonAsync<JsonElement>("/v1/recovery/envelope");
        Assert.NotEqual(before, envelope.ToString());
        Assert.Equal(Convert.ToBase64String(Enumerable.Repeat((byte)5, 60).ToArray()), envelope.GetProperty("wrappedKey").GetString());
        Assert.Equal(2, envelope.GetProperty("formatVersion").GetInt32());
        using var anonymous = factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Old"))).StatusCode);
        (await anonymous.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('b', 64), "New"))).EnsureSuccessStatusCode();
        // A second change based on the replaced password fails rather than overwriting.
        Assert.Equal(HttpStatusCode.Forbidden, (await owner.PostAsJsonAsync("/v1/recovery/password", Change(new string('a', 64), 6))).StatusCode);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task OnlyMasterPasswordLibrariesCanChangeTheirPassword(int version)
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp(version);
        var response = await owner.PostAsJsonAsync("/v1/recovery/password", Change(new string('a', 64), 5, version));
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }
}
