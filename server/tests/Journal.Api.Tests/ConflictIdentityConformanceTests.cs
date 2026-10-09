using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Journal.Api.Tests;

// Reproduces protocol/conformance/records/conflict-copy-ids-v1.json from protocol/conflicts.md alone (Identities): the
// identity of an entry parked next to a permanent deletion and of the copy of the other version of an entry or
// template, and the identities the cases of conflict-resolution-v1.json expect. The server never interprets payloads, but Windows and
// Android will derive these identities too, and a .NET Guid built from the bytes is mixed-endian: the string is built
// from the bytes instead.
public sealed class ConflictIdentityConformanceTests
{
    private static JsonDocument Corpus() => ConformanceFiles.Json("records/conflict-copy-ids-v1.json");

    private static string Lower(IEnumerable<byte> bytes) => string.Concat(bytes.Select(value => value.ToString("x2", System.Globalization.CultureInfo.InvariantCulture)));

    private static byte[] VaultKey()
    {
        using var crypto = ConformanceFiles.Json("crypto/encryption-v2.json");
        return crypto.RootElement.GetProperty("recovery").GetProperty("vaultKey").GetBytesFromBase64();
    }

    private static string Identity(byte[] derivationKey, string label, string recordId, string text)
    {
        var digest = Lower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
        var message = $"{label}\n{recordId.ToLowerInvariant()}\n{digest}";
        var tag = HMACSHA256.HashData(derivationKey, Encoding.UTF8.GetBytes(message));
        var bytes = tag[..16];
        bytes[6] = (byte)((bytes[6] & 0x0F) | 0x80);
        bytes[8] = (byte)((bytes[8] & 0x3F) | 0x80);
        var hex = Lower(bytes);
        return $"{hex[..8]}-{hex[8..12]}-{hex[12..16]}-{hex[16..20]}-{hex[20..]}";
    }

    [Fact]
    public void ParkedAndCopyIdentitiesFollowTheContractForEveryCase()
    {
        using var corpus = Corpus();
        var root = corpus.RootElement;
        var info = Encoding.UTF8.GetBytes(root.GetProperty("info").GetString()!);
        var encrypted = HKDF.DeriveKey(HashAlgorithmName.SHA256, VaultKey(), 32, salt: [], info: info);
        var plaintext = SHA256.HashData(info);
        var derivation = root.GetProperty("derivation");
        Assert.Equal(derivation.GetProperty("encrypted").GetProperty("hkdfOutput").GetString(), Lower(encrypted));
        Assert.Equal(derivation.GetProperty("plaintext").GetProperty("sha256OfInfo").GetString(), Lower(plaintext));

        var seen = new HashSet<string>();
        foreach (var item in root.GetProperty("cases").EnumerateArray())
        {
            var name = item.GetProperty("name").GetString()!;
            var key = item.GetProperty("protection").GetString() == "encrypted" ? encrypted : plaintext;
            var identity = Identity(key, item.GetProperty("label").GetString()!, item.GetProperty("recordID").GetString()!, item.GetProperty("text").GetString()!);
            Assert.True(item.GetProperty("id").GetString() == identity, name);
            Assert.Equal('8', identity[14]);
            Assert.Contains(identity[19], "89ab");
            Assert.True(seen.Add(identity), name);
        }
        Assert.True(seen.Count >= 6);
    }

    [Fact]
    public void TheIdentitiesTheResolutionCasesExpectFollowTheContractFromTheExactTexts()
    {
        using var crypto = ConformanceFiles.Json("crypto/encryption-v2.json");
        var info = Encoding.UTF8.GetBytes(Corpus().RootElement.GetProperty("info").GetString()!);
        var key = HKDF.DeriveKey(HashAlgorithmName.SHA256, VaultKey(), 32, salt: [], info: info);
        using var resolution = ConformanceFiles.Json("records/conflict-resolution-v1.json");
        var copies = 0;
        var parked = 0;
        foreach (var item in resolution.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = item.GetProperty("name").GetString()!;
            var recordId = item.GetProperty("recordID").GetString()!;
            var expected = item.GetProperty("expected");
            switch (expected.GetProperty("outcome").GetString())
            {
                case "keepBoth":
                    // The copy is made of the other version, whatever this device holds.
                    Assert.Equal(expected.GetProperty("copy").GetProperty("id").GetString(), Identity(key, "conflict-copy", recordId, item.GetProperty("other").GetString()!));
                    copies++;
                    break;
                case "parked":
                    // The edited version is parked: the one that is not the marker.
                    var edited = expected.GetProperty("markerIsLocal").GetBoolean() ? "other" : "local";
                    Assert.Equal(expected.GetProperty("parked").GetProperty("id").GetString(), Identity(key, "conflict-park", recordId, item.GetProperty(edited).GetString()!));
                    parked++;
                    break;
                default:
                    break;
            }
            Assert.NotNull(name);
        }
        Assert.True(copies >= 15);
        Assert.True(parked >= 4);
    }
}
