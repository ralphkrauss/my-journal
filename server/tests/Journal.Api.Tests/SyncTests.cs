using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Journal.Api.Features;
using Journal.Api.Security;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;

namespace Journal.Api.Tests;

public sealed class JournalFactory(string? root = null) : WebApplicationFactory<Program>
{
    // Requests carrying this header appear to come from that network address.
    public const string ClientAddressHeader = "X-Test-Client-Address";
    public string Root { get; } = root ?? Path.Combine(Path.GetTempPath(), "journal-test-" + Guid.NewGuid().ToString("N"));
    public ManualClock? Clock
    {
        get; init;
    }
    public Dictionary<string, string> Settings { get; } = [];
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);
        builder.UseSetting("Journal:DataDirectory", Root).UseEnvironment("Testing");
        foreach (var (key, value) in Settings)
        {
            builder.UseSetting(key, value);
        }
        builder.ConfigureTestServices(services =>
        {
            if (Clock is not null)
            {
                services.AddSingleton<TimeProvider>(Clock);
            }
            services.AddTransient<IStartupFilter, ClientAddressFilter>();
        });
    }
    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing && Directory.Exists(Root))
        {
            Directory.Delete(Root, true);
        }
    }
    private sealed class ClientAddressFilter : IStartupFilter
    {
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
        {
            app.Use((context, nextMiddleware) =>
            {
                if (IPAddress.TryParse(context.Request.Headers[ClientAddressHeader].ToString(), out var address))
                {
                    context.Connection.RemoteIpAddress = address;
                }
                return nextMiddleware(context);
            });
            next(app);
        };
    }
    public async Task<(HttpClient client, DeviceGrant grant)> SetUp(int formatVersion = 1)
    {
        var client = CreateClient();
        var code = await File.ReadAllTextAsync(Path.Combine(Root, "setup-code"));
        var response = await client.PostAsJsonAsync("/v1/setup", new SetupRequest(code, Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", formatVersion));
        response.EnsureSuccessStatusCode();
        var grant = (await response.Content.ReadFromJsonAsync<DeviceGrant>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", grant.Token);
        return (client, grant);
    }
}

public sealed class ManualClock(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;
    public override DateTimeOffset GetUtcNow() => Now;
}

public sealed class SyncTests
{
    private static string Payload(byte value) => Convert.ToBase64String(Enumerable.Repeat(value, 60).ToArray());
    private static PutRecord Write(long revision, byte value = 1) => new(Guid.NewGuid(), revision, "entry", Payload(value));

    [Fact]
    public async Task RetriedOperationReturnsOriginalReceiptWithoutDuplicatingChanges()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        var first = Write(0);
        var response = await client.PutAsJsonAsync($"/v1/sync/{id}", first);
        response.EnsureSuccessStatusCode();
        var receipt = await response.Content.ReadAsStringAsync();
        (await client.PutAsJsonAsync($"/v1/sync/{id}", Write(1, 2))).EnsureSuccessStatusCode();
        var retry = await client.PutAsJsonAsync($"/v1/sync/{id}", first);
        Assert.Equal(receipt, await retry.Content.ReadAsStringAsync());
        var changes = await client.GetFromJsonAsync<JsonElement>("/v1/sync/?after=0");
        Assert.Equal(2, changes.GetProperty("changes").GetArrayLength());
        var reused = await client.PutAsJsonAsync($"/v1/sync/{id}", first with
        {
            Payload = Payload(3)
        });
        Assert.Equal(HttpStatusCode.Conflict, reused.StatusCode);
    }

    [Fact]
    public async Task ReceiptsKeepNoSecondCopyOfThePayloadAndEarlierReceiptsStillAnswerRetries()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        var first = Write(0);
        var receipt = await (await client.PutAsJsonAsync($"/v1/sync/{id}", first)).Content.ReadAsStringAsync();
        using (var database = new SqliteConnection($"Data Source={Path.Combine(factory.Root, "journal.db")};Pooling=False"))
        {
            database.Open();
            using (var stored = database.CreateCommand())
            {
                stored.CommandText = "SELECT length(ResponseJson), ChangeCursor FROM Operations";
                using var reader = stored.ExecuteReader();
                Assert.True(reader.Read());
                Assert.Equal(0, reader.GetInt64(0));
                Assert.False(reader.IsDBNull(1));
            }
            // An operation applied by an earlier version kept its whole receipt instead.
            using var earlier = database.CreateCommand();
            earlier.CommandText = "UPDATE Operations SET ResponseJson = $receipt, ChangeCursor = NULL";
            earlier.Parameters.AddWithValue("$receipt", receipt);
            earlier.ExecuteNonQuery();
        }
        var retry = await client.PutAsJsonAsync($"/v1/sync/{id}", first);
        Assert.Equal(receipt, await retry.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ConcurrentEditsHaveOneWinnerAndPreserveTheCurrentRevision()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        (await client.PutAsJsonAsync($"/v1/sync/{id}", Write(0))).EnsureSuccessStatusCode();
        var responses = await Task.WhenAll(client.PutAsJsonAsync($"/v1/sync/{id}", Write(1, 2)), client.PutAsJsonAsync($"/v1/sync/{id}", Write(1, 3)));
        Assert.Single(responses, x => x.StatusCode == HttpStatusCode.OK);
        var conflict = Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Conflict);
        var body = await conflict.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(2, body.GetProperty("current").GetProperty("revision").GetInt64());
        Assert.Contains(body.GetProperty("current").GetProperty("payload").GetString(), new[] { Payload(2), Payload(3) });
    }

    [Fact]
    public async Task PaginatedOfflineCatchupContainsEveryImmutableRevision()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        for (var i = 0; i < 4; i++)
        {
            (await client.PutAsJsonAsync($"/v1/sync/{id}", Write(i, (byte)i))).EnsureSuccessStatusCode();
        }

        long cursor = 0;
        for (var i = 0; i < 4; i++)
        {
            var page = await client.GetFromJsonAsync<JsonElement>($"/v1/sync/?after={cursor}&limit=1");
            var change = Assert.Single(page.GetProperty("changes").EnumerateArray());
            Assert.Equal(i + 1, change.GetProperty("revision").GetInt64());
            Assert.Equal(Payload((byte)i), change.GetProperty("payload").GetString());
            cursor = page.GetProperty("cursor").GetInt64();
            Assert.Equal(i < 3, page.GetProperty("hasMore").GetBoolean());
        }
    }

    [Fact]
    public async Task RevocationImmediatelyRejectsReadsAndWrites()
    {
        using var factory = new JournalFactory();
        var (client, grant) = await factory.SetUp();
        using var stranger = factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await stranger.GetAsync("/v1/sync/")).StatusCode);
        (await client.DeleteAsync($"/v1/devices/{grant.DeviceId}")).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/sync/")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", Write(0))).StatusCode);
    }

    [Fact]
    public async Task RecoveryRequiresSecretAndSetupCannotReplaceAnExistingVault()
    {
        using var factory = new JournalFactory();
        await factory.SetUp();
        using var client = factory.CreateClient();
        Assert.False(File.Exists(Path.Combine(factory.Root, "setup-code")));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('b', 64), "Phone"))).StatusCode);
        var recovered = await client.PostAsJsonAsync("/v1/recovery", new RecoveryRequest(new string('a', 64), "Phone"));
        recovered.EnsureSuccessStatusCode();
        var grant = (await recovered.Content.ReadFromJsonAsync<DeviceGrant>())!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", grant.Token);
        (await client.GetAsync("/v1/sync/")).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await client.PostAsJsonAsync("/v1/setup", new SetupRequest("wrong", "", "", 0, "", ""))).StatusCode);
    }

    [Fact]
    public async Task WrongSetupCodesPauseSetupWithoutChangingTheCode()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var file = Path.Combine(factory.Root, "setup-code");
        // The file holds the code as shown (XXX-XXX); sending it as is also checks that form is accepted.
        var original = await File.ReadAllTextAsync(file);
        var wrong = original.StartsWith("222-222", StringComparison.Ordinal) ? "333333" : "222222";
        SetupRequest Attempt(string code) => new(code, Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", 1);

        // Typing mistakes that can't be a code are refused without using up attempts.
        foreach (var malformed in new[] { wrong[..5], wrong + "22", "22222O", "222022" })
        {
            var response = await client.PostAsJsonAsync("/v1/setup", Attempt(malformed));
            Assert.Equal((HttpStatusCode.BadRequest, "invalid_setup_code"), (response.StatusCode, await Refusal(response)));
        }
        for (var attempt = 0; attempt < SetupAttempts.Budget; attempt++)
        {
            var response = await client.PostAsJsonAsync("/v1/setup", Attempt(wrong));
            Assert.Equal((HttpStatusCode.Unauthorized, "invalid_setup_code"), (response.StatusCode, await Refusal(response)));
        }
        // Then every attempt waits, even with the right code, and the code the owner was shown stays valid.
        var paused = await client.PostAsJsonAsync("/v1/setup", Attempt(original));
        Assert.Equal((HttpStatusCode.TooManyRequests, "rate_limited"), (paused.StatusCode, await Refusal(paused)));
        Assert.InRange(paused.Headers.RetryAfter?.Delta ?? TimeSpan.Zero, TimeSpan.FromSeconds(1), SetupAttempts.FirstWait);
        Assert.Equal(original, await File.ReadAllTextAsync(file));
        Assert.False((await client.GetFromJsonAsync<JsonElement>("/v1/status")).GetProperty("initialized").GetBoolean());
    }

    [Fact]
    public async Task CheckingTheSetupCodeLeavesItValidForSetup()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var file = Path.Combine(factory.Root, "setup-code");
        var code = await File.ReadAllTextAsync(file);

        var check = await client.PostAsJsonAsync("/v1/setup/check", new SetupCheckRequest(code.Trim().Replace("-", "", StringComparison.Ordinal)));
        Assert.Equal(HttpStatusCode.NoContent, check.StatusCode);
        Assert.Equal(code, await File.ReadAllTextAsync(file));
        Assert.False((await client.GetFromJsonAsync<JsonElement>("/v1/status")).GetProperty("initialized").GetBoolean());
        await factory.SetUp();
        var initialized = await client.PostAsJsonAsync("/v1/setup/check", new SetupCheckRequest(code));
        Assert.Equal((HttpStatusCode.Conflict, "already_initialized"), (initialized.StatusCode, await Refusal(initialized)));
    }

    [Fact]
    public async Task WrongCodesInSetupChecksCountTowardsTheSetupPause()
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var original = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        var wrong = original.StartsWith("222-222", StringComparison.Ordinal) ? "333333" : "222222";
        Task<HttpResponseMessage> Check(string code) => client.PostAsJsonAsync("/v1/setup/check", new SetupCheckRequest(code));

        // Malformed codes and the right code don't use up attempts; wrong codes do, together with setup's.
        for (var attempt = 0; attempt < SetupAttempts.Budget; attempt++)
        {
            var malformed = await Check(wrong[..5]);
            Assert.Equal((HttpStatusCode.BadRequest, "invalid_setup_code"), (malformed.StatusCode, await Refusal(malformed)));
        }
        Assert.Equal(HttpStatusCode.NoContent, (await Check(original)).StatusCode);
        for (var attempt = 1; attempt < SetupAttempts.Budget; attempt++)
        {
            var rejected = await Check(wrong);
            Assert.Equal((HttpStatusCode.Unauthorized, "invalid_setup_code"), (rejected.StatusCode, await Refusal(rejected)));
        }
        var last = await client.PostAsJsonAsync("/v1/setup", new SetupRequest(wrong, Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", 1));
        Assert.Equal(HttpStatusCode.Unauthorized, last.StatusCode);
        var paused = await Check(original);
        Assert.Equal((HttpStatusCode.TooManyRequests, "rate_limited"), (paused.StatusCode, await Refusal(paused)));
        Assert.NotNull(paused.Headers.RetryAfter);
    }

    private static async Task<string> Refusal(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString() ?? "";

    [Theory]
    [InlineData(null)]
    // For example a write interrupted by a full disk: an empty code must never match.
    [InlineData("")]
    // An older server wrote eight-character codes, which setup no longer accepts.
    [InlineData("7KXM4PQR")]
    public async Task MissingDamagedOrOldSetupCodeFailsClosedAndIsReplacedAtStartup(string? contents)
    {
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();
        var file = Path.Combine(factory.Root, "setup-code");
        if (contents is null)
        {
            File.Delete(file);
        }
        else
        {
            await File.WriteAllTextAsync(file, contents);
        }
        // A well-formed code, so the missing or unusable file is what refuses it.
        var response = await client.PostAsJsonAsync("/v1/setup", new SetupRequest("222-222", Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", 1));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("setup_code_missing", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        Assert.False((await client.GetFromJsonAsync<JsonElement>("/v1/status")).GetProperty("initialized").GetBoolean());

        // A server that starts with an empty, damaged or old code file replaces it.
        var root = Path.Combine(Path.GetTempPath(), "journal-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        await File.WriteAllTextAsync(Path.Combine(root, "setup-code"), contents ?? "not a code");
        using var restarted = new JournalFactory(root);
        using var restartedClient = restarted.CreateClient();
        // The new code is stored as shown, so reading the file shows it plainly.
        var code = await File.ReadAllTextAsync(Path.Combine(root, "setup-code"));
        Assert.Matches("^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{3}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{3}\n$", code);
        // People type codes as shown (XXX-XXX) in any case; a pasted code may carry a line break.
        var typed = code.ToLowerInvariant();
        (await restartedClient.PostAsJsonAsync("/v1/setup", new SetupRequest(typed, Convert.ToBase64String(new byte[16]), Convert.ToBase64String(new byte[60]), 600_000, new string('a', 64), "Test Mac", 1))).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task AttachmentRetryIsSafeAndDifferentBytesCannotReplaceAnImage()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        var bytes = Enumerable.Repeat((byte)42, 4096).ToArray();
        (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(bytes))).EnsureSuccessStatusCode();
        (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(bytes))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(new byte[4096]))).StatusCode);
        Assert.Equal(bytes, await client.GetByteArrayAsync($"/v1/attachments/{id}"));
    }

    [Fact]
    public async Task UploadingIdenticalBytesRestoresAMissingImageFile()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        var bytes = Enumerable.Repeat((byte)42, 4096).ToArray();
        (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(bytes))).EnsureSuccessStatusCode();
        // The database row survives while the file is lost, for example after a partial directory copy.
        File.Delete(Path.Combine(factory.Root, "attachments", id.ToString("D")));
        using (var head = new HttpRequestMessage(HttpMethod.Head, $"/v1/attachments/{id}"))
        {
            Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(head)).StatusCode);
        }
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.GetAsync($"/v1/attachments/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(new byte[4096]))).StatusCode);

        (await client.PutAsync($"/v1/attachments/{id}", new ByteArrayContent(bytes))).EnsureSuccessStatusCode();
        using (var head = new HttpRequestMessage(HttpMethod.Head, $"/v1/attachments/{id}"))
        {
            Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(head)).StatusCode);
        }
        Assert.Equal(bytes, await client.GetByteArrayAsync($"/v1/attachments/{id}"));
    }

    [Fact]
    public async Task LargePagesStopAtTheByteBudgetButAlwaysMakeProgress()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var large = Convert.ToBase64String(new byte[4 * 1024 * 1024]);
        foreach (var payload in new[] { large, large, Payload(7) })
        {
            (await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", payload))).EnsureSuccessStatusCode();
        }

        // Two maximum-size records exceed the page budget, so each page carries one of them.
        var first = await client.GetFromJsonAsync<JsonElement>("/v1/sync/?after=0&limit=100");
        var change = Assert.Single(first.GetProperty("changes").EnumerateArray());
        Assert.True(first.GetProperty("hasMore").GetBoolean());
        // Clients refuse a page with more to come whose cursor does not move past `after`.
        Assert.Equal(change.GetProperty("cursor").GetInt64(), first.GetProperty("cursor").GetInt64());
        Assert.True(first.GetProperty("cursor").GetInt64() > 0);
        var second = await client.GetFromJsonAsync<JsonElement>($"/v1/sync/?after={first.GetProperty("cursor").GetInt64()}&limit=100");
        Assert.Equal(2, second.GetProperty("changes").GetArrayLength());
        Assert.False(second.GetProperty("hasMore").GetBoolean());
    }

    [Theory]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB=")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAR==")]
    public async Task NonCanonicalBase64IsRejectedBecauseClientsDecodeStrictly(string payload)
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var response = await client.PutAsJsonAsync($"/v1/sync/{Guid.NewGuid()}", new PutRecord(Guid.NewGuid(), 0, "entry", payload));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("invalid_record", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
    }

    [Fact]
    public async Task ReadingAfterAChangeThisServerDoesNotHaveReportsAChangedServer()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        (await client.PutAsJsonAsync($"/v1/sync/{id}", Write(0))).EnsureSuccessStatusCode();
        (await client.GetAsync($"/v1/sync/?after=1&afterRecord={id}&afterRevision=1")).EnsureSuccessStatusCode();
        // A data directory copied back from an older snapshot reuses cursors for other changes.
        var changed = await client.GetAsync($"/v1/sync/?after=1&afterRecord={Guid.NewGuid()}&afterRevision=1");
        Assert.Equal(HttpStatusCode.Conflict, changed.StatusCode);
        Assert.Equal("server_changed", (await changed.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        Assert.Equal(HttpStatusCode.Conflict, (await client.GetAsync($"/v1/sync/?after=5&afterRecord={id}&afterRevision=1")).StatusCode);
    }

    [Fact]
    public async Task ReadingAfterAnotherVersionAtTheSameRevisionReportsAChangedServer()
    {
        using var factory = new JournalFactory();
        var (client, _) = await factory.SetUp();
        var id = Guid.NewGuid();
        var written = Write(0);
        (await client.PutAsJsonAsync($"/v1/sync/{id}", written)).EnsureSuccessStatusCode();
        var digest = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(written.Payload)));
        (await client.GetAsync($"/v1/sync/?after=1&afterRecord={id}&afterRevision=1&afterDigest={digest}")).EnsureSuccessStatusCode();
        // A data directory copied back from an older snapshot can give the same record and revision to another version.
        var other = await client.GetAsync($"/v1/sync/?after=1&afterRecord={id}&afterRevision=1&afterDigest={new string('0', 64)}");
        Assert.Equal(HttpStatusCode.Conflict, other.StatusCode);
        Assert.Equal("server_changed", (await other.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync($"/v1/sync/?after=1&afterDigest={digest}")).StatusCode);
    }

    [Fact]
    public async Task PairingRequiresAuthorizedApprovalAndPrivatePollCredential()
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        var unauthorized = await phone.PostAsJsonAsync("/v1/pairing/lookup", new LookupPairing(pair.Code));
        Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);
        Assert.Equal("Bearer", unauthorized.Headers.WwwAuthenticate.ToString());
        Assert.Equal("unauthorized", (await unauthorized.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        await PairingFlow.Challenge(owner, phone, pair);
        Assert.Equal(HttpStatusCode.NotFound, (await phone.PostAsJsonAsync($"/v1/pairing/{pair.Id}/poll", new PollPairing("wrong"))).StatusCode);
        var token = new string('c', 64);
        (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(token))).EnsureSuccessStatusCode();
        var poll = await phone.PostAsJsonAsync($"/v1/pairing/{pair.Id}/poll", new PollPairing(pair.PollToken));
        Assert.True((await poll.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("approved").GetBoolean());
        phone.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        (await phone.GetAsync("/v1/sync/")).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PostAsJsonAsync($"/v1/pairing/{pair.Id}/approve", PairingFlow.Approval(token))).StatusCode);
        // Legacy requests that send the key itself, without a commitment, are refused.
        Assert.Equal(HttpStatusCode.BadRequest, (await phone.PostAsJsonAsync("/v1/pairing", new
        {
            deviceName = "Old",
            publicKey = Payload(1)
        })).StatusCode);
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task CancelPairingPreventsLateEnrollmentAndRevokesAnAlreadyApprovedGrant(bool approved)
    {
        using var factory = new JournalFactory();
        var (owner, _) = await factory.SetUp();
        using var phone = factory.CreateClient();
        var pair = await PairingFlow.Begin(phone);
        await PairingFlow.Challenge(owner, phone, pair);
        var id = pair.Id;
        var secret = pair.PollToken;
        var token = new string('d', 64);
        var approval = PairingFlow.Approval(token);
        if (approved)
        {
            (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", approval)).EnsureSuccessStatusCode();
        }

        Assert.Equal(HttpStatusCode.NotFound, (await phone.PostAsJsonAsync($"/v1/pairing/{id}/cancel", new PollPairing("wrong"))).StatusCode);
        (await phone.PostAsJsonAsync($"/v1/pairing/{id}/cancel", new PollPairing(secret))).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.NotFound, (await owner.PostAsJsonAsync($"/v1/pairing/{id}/approve", approval)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await phone.PostAsJsonAsync($"/v1/pairing/{id}/poll", new PollPairing(secret))).StatusCode);
        phone.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        Assert.Equal(HttpStatusCode.Unauthorized, (await phone.GetAsync("/v1/sync/")).StatusCode);
    }

}
