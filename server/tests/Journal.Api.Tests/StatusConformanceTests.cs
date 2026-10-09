using System.Net.Http.Json;
using System.Text.Json;

namespace Journal.Api.Tests;

// protocol/conformance/sync/status-v2.json: both unauthenticated endpoints report the protocol revision and the 13
// frozen capability names. 1.0 apps read the names, so a missing or added one silently breaks them, and agent access
// is available exactly when the names (revision 1) are all listed.
public sealed class StatusConformanceTests
{
    [Fact]
    public async Task BothEndpointsReportTheRevisionAndExactlyTheFrozenCapabilities()
    {
        using var corpus = ConformanceFiles.Json("sync/status-v2.json");
        var frozen = corpus.RootElement.GetProperty("revisionOneFeatures").EnumerateArray().Select(name => name.GetString()!).ToArray();
        using var factory = new JournalFactory();
        using var client = factory.CreateClient();

        foreach (var endpoint in corpus.RootElement.GetProperty("server").GetProperty("endpoints").EnumerateArray())
        {
            var path = endpoint.GetProperty("path").GetString()!;
            var actual = await client.GetFromJsonAsync<JsonElement>(path);
            foreach (var expected in endpoint.GetProperty("body").EnumerateObject())
            {
                Assert.True(actual.TryGetProperty(expected.Name, out var member), $"{path} has no {expected.Name}");
                Assert.True(Contains(member, expected.Value), $"{path} {expected.Name}: {member} does not contain {expected.Value}");
            }
            var listed = actual.GetProperty("features").EnumerateArray().Select(name => name.GetString()!).ToArray();
            Assert.Equal(frozen.Order(), listed.Order());
            Assert.Contains("agent-access-2", listed);
            Assert.Equal(1, actual.GetProperty("protocolRevision").GetInt32());
        }
    }

    // Every member and value of the fixture is in the response; arrays contain each listed element.
    private static bool Contains(JsonElement actual, JsonElement expected) => expected.ValueKind == JsonValueKind.Array
        ? actual.ValueKind == JsonValueKind.Array && expected.EnumerateArray().All(element => actual.EnumerateArray().Any(candidate => candidate.GetRawText() == element.GetRawText()))
        : actual.GetRawText() == expected.GetRawText();
}
