using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Journal.Api.Features;

namespace Journal.Api.Tests;

// Reproduces protocol/conformance/pairing/pairing-v1.json from the protocol text alone (README, Pairing and
// Invite pairing): the invite proof, the server origin it binds, the QR text and the check code.
public sealed class PairingConformanceTests
{
    private const string InvitePrefix = "MYJOURNAL";
    private const int InviteHeaderBytes = 16 + 32 + 32;

    private static JsonDocument Corpus() => ConformanceFiles.Json("pairing/pairing-v1.json");

    private static string Text(JsonElement element, string name) => element.GetProperty(name).GetString()!;

    private static byte[] Raw(JsonElement element, string name) => element.GetProperty(name).GetBytesFromBase64();

    // The lower-case https origin, with the port only when it isn't 443; null for anything else.
    private static string? Origin(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || uri.UserInfo.Length > 0 || uri.Host.Length == 0)
        {
            return null;
        }
        var port = uri.Port == 443 ? "" : ":" + uri.Port.ToString(CultureInfo.InvariantCulture);
        return $"https://{uri.Host.ToLowerInvariant()}{port}";
    }

    private static byte[] WithLength(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        var length = new byte[2];
        BinaryPrimitives.WriteUInt16BigEndian(length, (ushort)bytes.Length);
        return [.. length, .. bytes];
    }

    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[]? FromBase64Url(string text)
    {
        if (text.Length == 0 || text.Length % 4 == 1 || text.Any(character => !(char.IsAsciiLetterOrDigit(character) || character is '-' or '_')))
        {
            return null;
        }
        var padded = text.Replace('-', '+').Replace('_', '/').PadRight((text.Length + 3) / 4 * 4, '=');
        return Convert.FromBase64String(padded);
    }

    private enum Scan
    {
        Invite,
        NotInvite,
        NewerVersion,
        UnreachableServer,
    }

    // A scanned text is an invite of this version when it is MYJOURNAL1. and base64url of handle, approver key,
    // secret and a server address that is an https origin.
    private static (Scan result, string? server) Read(string text)
    {
        if (!text.StartsWith(InvitePrefix, StringComparison.Ordinal))
        {
            return (Scan.NotInvite, null);
        }
        var rest = text[InvitePrefix.Length..];
        var digits = rest.TakeWhile(char.IsAsciiDigit).Count();
        if (digits == 0 || digits == rest.Length || rest[digits] != '.')
        {
            return (Scan.NotInvite, null);
        }
        if (rest[..digits] != "1")
        {
            return (Scan.NewerVersion, null);
        }
        var payload = FromBase64Url(rest[(digits + 1)..]);
        if (payload is null || payload.Length <= InviteHeaderBytes)
        {
            return (Scan.NotInvite, null);
        }
        var server = Encoding.UTF8.GetString(payload[InviteHeaderBytes..]);
        return Origin(server) is null ? (Scan.UnreachableServer, null) : (Scan.Invite, server);
    }

    [Fact]
    public void InviteProofIsTheHmacOfTheDocumentedMessageAndBindsTheNormalizedOrigin()
    {
        using var corpus = Corpus();
        foreach (var vector in corpus.RootElement.GetProperty("inviteProofs").EnumerateArray())
        {
            var name = Text(vector, "name");
            var origin = Origin(Text(vector, "server"));
            Assert.True(Text(vector, "origin") == origin, $"{name}: origin");
            var handle = Raw(vector, "handle");
            Assert.True(Text(vector, "handleHex") == Convert.ToHexStringLower(handle), $"{name}: handle");
            byte[] message =
            [
                .. "journal:v2:pairing-invite"u8, 0,
                .. handle, .. Raw(vector, "approverKey"), .. Raw(vector, "commitment"),
                .. WithLength(origin!), .. WithLength(Text(vector, "deviceName")),
            ];
            Assert.True(Raw(vector, "message").SequenceEqual(message), $"{name}: message");
            var proof = HMACSHA256.HashData(Raw(vector, "secret"), message);
            Assert.True(Raw(vector, "proof").SequenceEqual(proof), $"{name}: proof");
        }
    }

    [Fact]
    public void ServerAddressesNormalizeToAnHttpsOriginOrNone()
    {
        using var corpus = Corpus();
        foreach (var vector in corpus.RootElement.GetProperty("origins").EnumerateArray())
        {
            var expected = vector.GetProperty("origin").GetString();
            var address = Text(vector, "address");
            Assert.True(expected == Origin(address), $"'{address}' gives {Origin(address) ?? "no origin"}, expected {expected ?? "none"}");
        }
    }

    [Fact]
    public void InviteTextCarriesTheHandleKeysSecretAndAddressAndScannedTextsAreClassified()
    {
        using var corpus = Corpus();
        foreach (var vector in corpus.RootElement.GetProperty("inviteProofs").EnumerateArray())
        {
            byte[] payload = [.. Raw(vector, "handle"), .. Raw(vector, "approverKey"), .. Raw(vector, "secret"), .. Encoding.UTF8.GetBytes(Text(vector, "server"))];
            Assert.True($"{InvitePrefix}1.{Base64Url(payload)}" == Text(vector, "text"), Text(vector, "name"));
            Assert.Equal((Scan.Invite, Text(vector, "server")), Read(Text(vector, "text")));
        }
        var expected = new Dictionary<string, Scan>
        {
            ["invite"] = Scan.Invite,
            ["notInvite"] = Scan.NotInvite,
            ["newerVersion"] = Scan.NewerVersion,
            ["unreachableServer"] = Scan.UnreachableServer,
        };
        foreach (var scanned in corpus.RootElement.GetProperty("scannedTexts").EnumerateArray())
        {
            var (result, server) = Read(Text(scanned, "text"));
            Assert.True(expected[Text(scanned, "result")] == result, $"'{Text(scanned, "text")}' reads as {result}");
            if (scanned.TryGetProperty("server", out var address))
            {
                Assert.Equal(address.GetString(), server);
            }
        }

        // The corpus has no unreachable-server case: an address that isn't an https origin is one by the rule above.
        var plain = Base64Url([.. new byte[InviteHeaderBytes], .. "http://journal.example.ts.net"u8]);
        Assert.Equal(Scan.UnreachableServer, Read($"{InvitePrefix}1.{plain}").result);
    }

    [Fact]
    public void CheckCodeDerivesFromBothKeysAndTheServersCommitmentAgrees()
    {
        using var corpus = Corpus();
        foreach (var vector in corpus.RootElement.GetProperty("checkCodes").EnumerateArray())
        {
            var device = Raw(vector, "devicePublicKey");
            var approver = Raw(vector, "approverPublicKey");
            var commitment = Convert.ToBase64String(SHA256.HashData([.. "journal:v2:pairing-commitment"u8, .. device]));
            Assert.Equal(Text(vector, "commitment"), commitment);
            Assert.Equal(commitment, PairingEndpoints.Commitment(device));
            var id = Text(vector, "pairingID").ToLowerInvariant();
            var digest = SHA256.HashData([.. Encoding.UTF8.GetBytes($"journal:v2:pairing-check:{id}:"), .. device, .. approver]);
            var code = (BinaryPrimitives.ReadUInt32BigEndian(digest) % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);
            Assert.Equal(Text(vector, "checkCode"), code);
            Assert.Equal(Text(vector, "shown"), $"{code[..3]} {code[3..]}");
        }
    }
}
