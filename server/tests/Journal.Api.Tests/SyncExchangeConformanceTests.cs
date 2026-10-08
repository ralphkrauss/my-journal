using System.Text;
using System.Text.Json;

namespace Journal.Api.Tests;

// Replays protocol/conformance/sync/exchanges-v1.json, the conversation clients read their responses from, against
// a new server. Responses are compared as JSON, member by member, never as text.
public sealed class SyncExchangeConformanceTests
{
    [Fact]
    public async Task ServerAnswersTheRecordedConversationExactly()
    {
        using var corpus = ConformanceFiles.Json("sync/exchanges-v1.json");
        using var factory = new JournalFactory();
        var (authenticated, _) = await factory.SetUp(2);
        using var anonymous = factory.CreateClient();
        var bodies = new Dictionary<string, JsonElement>();
        var differences = new List<string>();

        foreach (var step in corpus.RootElement.GetProperty("steps").EnumerateArray())
        {
            var name = step.GetProperty("name").GetString()!;
            var request = step.GetProperty("request");
            var useCredential = !request.TryGetProperty("authenticated", out var flag) || flag.GetBoolean();
            using var response = await Send(useCredential ? authenticated : anonymous, request);
            var text = await response.Content.ReadAsStringAsync();
            var found = Check(step.GetProperty("response"), response, text, bodies, name);
            differences.AddRange(found.Select(difference => $"{name}: {difference}"));
            if (JsonBody(text) is { } actual)
            {
                bodies[name] = actual;
            }
            differences.AddRange(ProblemDifferences(response, text).Select(difference => $"{name}: {difference}"));
        }

        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }

    private static async Task<HttpResponseMessage> Send(HttpClient client, JsonElement request)
    {
        using var message = new HttpRequestMessage(
            new HttpMethod(request.GetProperty("method").GetString()!),
            new Uri(request.GetProperty("path").GetString()!, UriKind.Relative));
        if (request.TryGetProperty("body", out var body))
        {
            message.Content = new StringContent(body.GetRawText(), Encoding.UTF8, "application/json");
        }
        return await client.SendAsync(message);
    }

    private static JsonElement? JsonBody(string text)
    {
        try
        {
            return JsonDocument.Parse(text).RootElement.Clone();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static List<string> Check(JsonElement expected, HttpResponseMessage response, string text, Dictionary<string, JsonElement> earlier, string step)
    {
        var found = new List<string>();
        var status = expected.GetProperty("status").GetInt32();
        if ((int)response.StatusCode != status)
        {
            found.Add($"status {(int)response.StatusCode}, expected {status}");
        }
        if (expected.TryGetProperty("contentType", out var contentType) && response.Content.Headers.ContentType?.MediaType != contentType.GetString())
        {
            found.Add($"content type {response.Content.Headers.ContentType?.MediaType}, expected {contentType.GetString()}");
        }
        if (expected.TryGetProperty("headers", out var headers))
        {
            foreach (var header in headers.EnumerateObject())
            {
                var value = response.Headers.TryGetValues(header.Name, out var values) ? string.Join(", ", values) : null;
                if (value != header.Value.GetString())
                {
                    found.Add($"header {header.Name} is {value ?? "missing"}, expected {header.Value.GetString()}");
                }
            }
        }
        if (!expected.TryGetProperty("body", out var body))
        {
            return found;
        }
        if (JsonBody(text) is not { } actual)
        {
            found.Add("the body is not JSON");
            return found;
        }
        if (expected.TryGetProperty("identicalTo", out var earlierName))
        {
            var previous = earlier[earlierName.GetString()!];
            found.AddRange(Differences(previous, actual, "", subset: false, []));
            return found;
        }
        var subset = expected.TryGetProperty("match", out var mode) && mode.GetString() == "subset";
        var formats = expected.TryGetProperty("volatile", out var volatileValues)
            ? volatileValues.EnumerateObject().ToDictionary(member => member.Name, member => member.Value.GetString()!)
            : [];
        found.AddRange(Differences(body, actual, "", subset, formats));
        return found;
    }

    // Every error that has a body is a problem details object whose code and error agree.
    private static IEnumerable<string> ProblemDifferences(HttpResponseMessage response, string text)
    {
        if ((int)response.StatusCode < 400 || text.Length == 0)
        {
            yield break;
        }
        if (response.Content.Headers.ContentType?.MediaType != "application/problem+json")
        {
            yield return $"error content type is {response.Content.Headers.ContentType?.MediaType}";
        }
        if (JsonBody(text) is not { ValueKind: JsonValueKind.Object } problem)
        {
            yield return "the error body is not a JSON object";
            yield break;
        }
        foreach (var member in new[] { "type", "title", "status", "code", "error" })
        {
            if (!problem.TryGetProperty(member, out _))
            {
                yield return $"the error has no {member}";
            }
        }
        if (problem.TryGetProperty("status", out var status) && status.ValueKind == JsonValueKind.Number && status.GetInt32() != (int)response.StatusCode)
        {
            yield return $"the error's status is {status.GetInt32()}";
        }
        if (problem.TryGetProperty("code", out var code) && problem.TryGetProperty("error", out var error) && code.ToString() != error.ToString())
        {
            yield return $"code {code} and error {error} differ";
        }
    }

    // exact: the same members and values. subset: every expected member and array element is present.
    // volatile pointers hold a value the server chooses and are compared by format.
    private static List<string> Differences(JsonElement expected, JsonElement actual, string pointer, bool subset, Dictionary<string, string> formats)
    {
        var found = new List<string>();
        if (formats.TryGetValue(pointer, out var format))
        {
            if (!HasFormat(actual, format))
            {
                found.Add($"{pointer} is {actual}, expected a {format}");
            }
            return found;
        }
        if (expected.ValueKind != actual.ValueKind)
        {
            found.Add($"{Describe(pointer)} is {actual}, expected {expected}");
            return found;
        }
        switch (expected.ValueKind)
        {
            case JsonValueKind.Object:
                found.AddRange(ObjectDifferences(expected, actual, pointer, subset, formats));
                break;
            case JsonValueKind.Array:
                found.AddRange(ArrayDifferences(expected, actual, pointer, subset, formats));
                break;
            case JsonValueKind.String when expected.GetString() != actual.GetString():
            case JsonValueKind.Number when expected.GetDecimal() != actual.GetDecimal():
                found.Add($"{Describe(pointer)} is {actual}, expected {expected}");
                break;
        }
        return found;
    }

    private static List<string> ObjectDifferences(JsonElement expected, JsonElement actual, string pointer, bool subset, Dictionary<string, string> formats)
    {
        var found = new List<string>();
        foreach (var member in expected.EnumerateObject())
        {
            if (actual.TryGetProperty(member.Name, out var value))
            {
                found.AddRange(Differences(member.Value, value, $"{pointer}/{member.Name}", subset, formats));
            }
            else
            {
                found.Add($"{pointer}/{member.Name} is missing");
            }
        }
        if (!subset)
        {
            found.AddRange(actual.EnumerateObject()
                .Where(member => !expected.TryGetProperty(member.Name, out _))
                .Select(member => $"{pointer}/{member.Name} is not expected"));
        }
        return found;
    }

    private static List<string> ArrayDifferences(JsonElement expected, JsonElement actual, string pointer, bool subset, Dictionary<string, string> formats)
    {
        var found = new List<string>();
        var actualItems = actual.EnumerateArray().ToList();
        var expectedItems = expected.EnumerateArray().ToList();
        if (subset)
        {
            foreach (var item in expectedItems.Where(item => !actualItems.Any(candidate => Differences(item, candidate, pointer, true, formats).Count == 0)))
            {
                found.Add($"{pointer} lacks {item}");
            }
            return found;
        }
        if (actualItems.Count != expectedItems.Count)
        {
            found.Add($"{pointer} has {actualItems.Count} elements, expected {expectedItems.Count}");
        }
        for (var index = 0; index < Math.Min(actualItems.Count, expectedItems.Count); index++)
        {
            found.AddRange(Differences(expectedItems[index], actualItems[index], $"{pointer}/{index}", false, formats));
        }
        return found;
    }

    private static bool HasFormat(JsonElement value, string format) => value.ValueKind == JsonValueKind.String && format switch
    {
        "uuid" => ConformanceFormats.IsUuid(value.GetString()),
        "timestamp" => ConformanceFormats.TryParseTimestamp(value.GetString(), out _),
        _ => throw new InvalidDataException($"Unknown volatile format {format}."),
    };

    private static string Describe(string pointer) => pointer.Length == 0 ? "the body" : pointer;
}
