using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Journal.Api.Features;
using Journal.Api.Security;

namespace Journal.Api.Tests;

// protocol/conformance/crypto/negative-v1.json: what a client must refuse. The sealed values are opened here
// with AES-GCM as the protocol describes, and the server's own bounds are checked against the same file.
public sealed class CryptoNegativeConformanceTests
{
    private static JsonDocument Corpus() => ConformanceFiles.Json("crypto/negative-v1.json");

    private static string Text(JsonElement element, string name) => element.GetProperty(name).GetString()!;

    [Fact]
    public void ValuesThatMustNotOpenAreRefusedAndTheUntouchedVectorOpens()
    {
        using var corpus = Corpus();
        foreach (var vector in corpus.RootElement.GetProperty("open").EnumerateArray())
        {
            var name = Text(vector, "name");
            var key = vector.GetProperty("key").GetBytesFromBase64();
            var combined = vector.GetProperty("combined").GetBytesFromBase64();
            var context = Text(vector, "context");
            if (Text(vector, "result") == "opens")
            {
                Assert.True(vector.GetProperty("plaintext").GetBytesFromBase64().SequenceEqual(ConformanceCrypto.Open(key, combined, context)), name);
                continue;
            }
            Assert.Equal("authenticationFails", Text(vector, "result"));
            var refused = false;
            try
            {
                ConformanceCrypto.Open(key, combined, context);
            }
            catch (Exception exception) when (exception is CryptographicException or ArgumentException)
            {
                refused = true;
            }
            Assert.True(refused, $"{name} opened");
        }
    }

    [Fact]
    public void ServerAcceptsOnlyCanonicalBase64()
    {
        using var corpus = Corpus();
        var base64 = corpus.RootElement.GetProperty("base64");
        foreach (var vector in base64.GetProperty("canonical").EnumerateArray())
        {
            var text = Text(vector, "text");
            var bytes = Convert.FromBase64String(text);
            Assert.Equal(Text(vector, "hex"), Convert.ToHexStringLower(bytes));
            Assert.Equal(text, Convert.ToBase64String(bytes));
            Assert.True(Secrets.IsBase64(text, 0, 1 << 20), $"'{text}' is canonical");
        }
        foreach (var vector in base64.GetProperty("rejected").EnumerateArray())
        {
            Assert.False(Secrets.IsBase64(Text(vector, "text"), 0, 1 << 20), Text(vector, "note"));
        }
    }

    private static async Task<HttpResponseMessage> Setup(JournalFactory factory, HttpClient client, JsonElement parameters)
    {
        var code = await File.ReadAllTextAsync(Path.Combine(factory.Root, "setup-code"));
        var salt = Convert.ToBase64String(new byte[parameters.GetProperty("saltBytes").GetInt32()]);
        return await client.PostAsJsonAsync("/v1/setup", new SetupRequest(code, salt, Convert.ToBase64String(new byte[60]), parameters.GetProperty("iterations").GetInt32(), new string('a', 64), "Test Mac", 2));
    }

    [Fact]
    public async Task SetupAcceptsExactlyTheRecoveryParametersTheCorpusSays()
    {
        using var corpus = Corpus();
        var cases = corpus.RootElement.GetProperty("recoveryParameters").EnumerateArray().ToList();
        using var rejecting = new JournalFactory();
        using var rejectingClient = rejecting.CreateClient();
        foreach (var parameters in cases.Where(parameters => !parameters.GetProperty("serverAcceptsOnSetup").GetBoolean()))
        {
            using var response = await Setup(rejecting, rejectingClient, parameters);
            Assert.True(response.StatusCode == HttpStatusCode.BadRequest, $"{Text(parameters, "name")} gave {(int)response.StatusCode}");
            Assert.Equal("invalid_setup", (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
        }
        foreach (var parameters in cases.Where(parameters => parameters.GetProperty("serverAcceptsOnSetup").GetBoolean()))
        {
            using var factory = new JournalFactory();
            using var client = factory.CreateClient();
            using var response = await Setup(factory, client, parameters);
            Assert.True(response.StatusCode == HttpStatusCode.OK, $"{Text(parameters, "name")} gave {(int)response.StatusCode}");
        }

        // The refusals above didn't use up the setup code: a valid request on the same server still sets it up.
        var valid = cases.First(parameters => parameters.GetProperty("serverAcceptsOnSetup").GetBoolean());
        using var afterwards = await Setup(rejecting, rejectingClient, valid);
        Assert.Equal(HttpStatusCode.OK, afterwards.StatusCode);
    }
}
