using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Journal.Api.Features;
using Journal.Api.Security;

namespace Journal.Api.Tests;

// The public corpora in protocol/conformance are what other clients are written against. .NET reproduces every
// value independently, and the server's own derivations (verifier hashes, the pairing commitment, input bounds)
// must accept exactly what the corpus describes.
public sealed class ProtocolVectorTests
{
    private static JsonDocument Corpus(string name) => ConformanceFiles.Json(name);

    private static string Text(JsonElement element, string name) =>
        element.GetProperty(name).GetString() ?? throw new InvalidDataException("Missing fixture string.");

    private static byte[] Bytes(JsonElement element, string name) => element.GetProperty(name).GetBytesFromBase64();

    // combined is nonce || ciphertext || tag, with the UTF-8 context as authenticated data.
    private static void AssertSealed(byte[] key, byte[] plaintext, byte[] combined, string context)
    {
        var aad = Encoding.UTF8.GetBytes(context);
        var encrypted = new byte[plaintext.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(combined.AsSpan(0, 12), plaintext, encrypted, tag, aad);
        Assert.Equal(combined[12..^16], encrypted);
        Assert.Equal(combined[^16..], tag);
        var opened = new byte[plaintext.Length];
        aes.Decrypt(combined.AsSpan(0, 12), encrypted, tag, opened, aad);
        Assert.Equal(plaintext, opened);
    }

    private static byte[] RecoveryKey(byte[] password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, 32);

    private static string RecoverySecret(byte[] derivedKey) =>
        Convert.ToHexStringLower(HKDF.DeriveKey(HashAlgorithmName.SHA256, derivedKey, 32, [], "journal:v1:recovery-auth"u8.ToArray()));

    // The library record is sealed like any record, with its kind in the context: opening it as another kind fails.
    [Fact]
    public void TheLibraryRecordFixtureOpensOnlyAsALibraryRecord()
    {
        using var library = Corpus("records/library-record-v1.json");
        using var corpus = Corpus("crypto/encryption-v2.json");
        var key = Bytes(corpus.RootElement.GetProperty("recovery"), "vaultKey");
        var record = library.RootElement.GetProperty("record");
        var combined = Bytes(record, "combined");
        Assert.Equal("journal:v1:record:library:" + Text(record, "id"), Text(record, "context"));
        AssertSealed(key, Encoding.UTF8.GetBytes(Text(record, "plaintext")), combined, Text(record, "context"));
        using var aes = new AesGcm(key, 16);
        var opened = new byte[combined.Length - 28];
        Assert.ThrowsAny<CryptographicException>(() => aes.Decrypt(
            combined.AsSpan(0, 12), combined.AsSpan(12, combined.Length - 28), combined.AsSpan(combined.Length - 16), opened,
            Encoding.UTF8.GetBytes("journal:v1:record:entry:" + Text(record, "id"))));
    }

    [Fact]
    public void PublicFixturesMatchIndependentDotNetEncryptionAndRecovery()
    {
        using var corpus = Corpus("crypto/encryption-v1.json");
        Assert.Equal(1, corpus.RootElement.GetProperty("formatVersion").GetInt32());
        foreach (var vector in corpus.RootElement.GetProperty("envelopes").EnumerateArray())
        {
            AssertSealed(Bytes(vector, "key"), Bytes(vector, "plaintext"), Bytes(vector, "combined"), Text(vector, "context"));
        }
        var recovery = corpus.RootElement.GetProperty("recovery");
        var phrase = Encoding.UTF8.GetBytes(Text(recovery, "phrase").Trim());
        var derived = RecoveryKey(phrase, Bytes(recovery, "salt"), recovery.GetProperty("iterations").GetInt32());
        Assert.Equal(Bytes(recovery, "derivedKey"), derived);
        Assert.Equal(Text(recovery, "authenticationSecret"), RecoverySecret(derived));
    }

    [Fact]
    public void PasswordEnvelopesUseTheExactPasswordAndTheServerStoresOnlyTheVerifierHash()
    {
        using var corpus = Corpus("crypto/encryption-v2.json");
        Assert.Equal(2, corpus.RootElement.GetProperty("corpusVersion").GetInt32());
        var recovery = corpus.RootElement.GetProperty("recovery");
        var password = Text(recovery, "password");
        var salt = Bytes(recovery, "salt");
        var iterations = recovery.GetProperty("iterations").GetInt32();
        Assert.Equal(Bytes(recovery, "passwordUTF8"), Encoding.UTF8.GetBytes(password));
        // Passwords are derived from their NFC form; this one is already in NFC.
        Assert.Equal(password, password.Normalize(NormalizationForm.FormC));
        var derived = RecoveryKey(Encoding.UTF8.GetBytes(password), salt, iterations);
        Assert.Equal(Bytes(recovery, "derivedKey"), derived);
        // Only format 1 trims; a client that trims a password can't open these envelopes.
        Assert.NotEqual(derived, RecoveryKey(Encoding.UTF8.GetBytes(password.Trim()), salt, iterations));
        var secret = RecoverySecret(derived);
        Assert.Equal(Text(recovery, "recoverySecret"), secret);
        Assert.Equal(Text(recovery, "recoveryHash"), Secrets.Hash(secret));
        Assert.True(Secrets.Matches(secret, Text(recovery, "recoveryHash")));

        var versions = new List<int>();
        foreach (var wrapped in recovery.GetProperty("envelopes").EnumerateArray())
        {
            var envelope = wrapped.GetProperty("envelope");
            var version = envelope.GetProperty("formatVersion").GetInt32();
            versions.Add(version);
            Assert.Equal($"journal:v{version}:recovery", Text(wrapped, "context"));
            Assert.Equal(Text(recovery, "salt"), Text(envelope, "salt"));
            Assert.Equal(600_000, envelope.GetProperty("iterations").GetInt32());
            // The bounds the server enforces at setup and password change.
            Assert.True(Secrets.IsBase64(Text(envelope, "salt"), 16, 16));
            Assert.True(Secrets.IsBase64(Text(envelope, "wrappedKey"), 60, 60));
            AssertSealed(derived, Bytes(recovery, "vaultKey"), Bytes(envelope, "wrappedKey"), Text(wrapped, "context"));
        }
        Assert.Equal([2, 3], versions);

        var passwordless = corpus.RootElement.GetProperty("passwordless");
        var empty = passwordless.GetProperty("envelope");
        Assert.Equal(("", "", 0, 4), (Text(empty, "salt"), Text(empty, "wrappedKey"), empty.GetProperty("iterations").GetInt32(), empty.GetProperty("formatVersion").GetInt32()));
        // Administrator recovery codes are verified exactly like recovery secrets.
        Assert.Equal(Text(passwordless, "recoveryHash"), Secrets.Hash(Text(passwordless, "recoveryCode")));
    }

    // A password typed with decomposed characters derives from its NFC form. An envelope made from the exact typed
    // bytes before that rule must still open, so clients try those next when they differ.
    [Fact]
    public void PasswordsDeriveFromTheirNormalizedFormAndExactEnvelopesRemainReadable()
    {
        using var corpus = Corpus("crypto/encryption-v2.json");
        var vector = corpus.RootElement.GetProperty("normalization");
        var vaultKey = Bytes(corpus.RootElement.GetProperty("recovery"), "vaultKey");
        var password = Text(vector, "password");
        Assert.Equal(Bytes(vector, "typedUTF8"), Encoding.UTF8.GetBytes(password));
        Assert.Equal(Bytes(vector, "normalizedUTF8"), Encoding.UTF8.GetBytes(password.Normalize(NormalizationForm.FormC)));
        Assert.NotEqual(Bytes(vector, "typedUTF8"), Bytes(vector, "normalizedUTF8"));
        foreach (var (name, input) in new[] { ("normalized", "normalizedUTF8"), ("exact", "typedUTF8") })
        {
            var variant = vector.GetProperty(name);
            var derived = RecoveryKey(Bytes(vector, input), Bytes(vector, "salt"), vector.GetProperty("iterations").GetInt32());
            Assert.Equal(Bytes(variant, "derivedKey"), derived);
            var secret = RecoverySecret(derived);
            Assert.Equal(Text(variant, "recoverySecret"), secret);
            Assert.Equal(Text(variant, "recoveryHash"), Secrets.Hash(secret));
            var envelope = variant.GetProperty("envelope");
            Assert.Equal(2, envelope.GetProperty("formatVersion").GetInt32());
            Assert.True(Secrets.IsBase64(Text(envelope, "wrappedKey"), 60, 60));
            AssertSealed(derived, vaultKey, Bytes(envelope, "wrappedKey"), "journal:v2:recovery");
        }
    }

    [Fact]
    public void PairingGrantMatchesIndependentDotNetDerivationAndTheServerChecks()
    {
        using var corpus = Corpus("crypto/encryption-v2.json");
        var pairing = corpus.RootElement.GetProperty("pairing");
        var id = Guid.Parse(Text(pairing, "id")).ToString();
        var device = Bytes(pairing, "devicePublicKey");
        var approver = Bytes(pairing, "approverPublicKey");
        Assert.Equal(Text(pairing, "keyCommitment"), PairingEndpoints.Commitment(device));
        var digest = SHA256.HashData([.. Encoding.UTF8.GetBytes($"journal:v2:pairing-check:{id}:"), .. device, .. approver]);
        var code = (BinaryPrimitives.ReadUInt32BigEndian(digest) % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);
        Assert.Equal(Text(pairing, "checkCode"), code);

        // .NET has no portable X25519; the corpus keys and shared secret are those of RFC 7748 section 6.1.
        var grantKey = HKDF.DeriveKey(HashAlgorithmName.SHA256, Bytes(pairing, "sharedSecret"), 32, Encoding.UTF8.GetBytes(id), "journal:v1:pairing"u8.ToArray());
        Assert.Equal(Bytes(pairing, "grantKey"), grantKey);
        Assert.Equal($"journal:v1:pairing:{id}", Text(pairing, "context"));
        var encrypted = Bytes(pairing, "encryptedGrant");
        Assert.Equal(approver, encrypted[..32]);
        var plaintext = Bytes(pairing, "grantPlaintext");
        AssertSealed(grantKey, plaintext, encrypted[32..], Text(pairing, "context"));
        using var contents = JsonDocument.Parse(plaintext);
        var grant = pairing.GetProperty("grant");
        Assert.Equal(Bytes(grant, "masterKey"), Bytes(contents.RootElement, "masterKey"));
        Assert.Equal(Text(grant, "token"), Text(contents.RootElement, "token"));
        Assert.Equal(grant.GetProperty("recoveryVersion").GetInt32(), contents.RootElement.GetProperty("recoveryVersion").GetInt32());

        // What the server checks and stores when the approving device sends the grant.
        Assert.True(Secrets.IsBase64(Text(pairing, "encryptedGrant"), 60, 4096));
        Assert.True(Secrets.IsBase64(Text(pairing, "devicePublicKey"), 32, 32));
        Assert.True(Secrets.IsBase64(Text(pairing, "approverPublicKey"), 32, 32));
        Assert.Equal(64, Text(grant, "token").Length);
        Assert.Equal(Text(pairing, "deviceTokenHash"), Secrets.Hash(Text(grant, "token")));
    }

    [Fact]
    public void RecordAndImageMatchIndependentDotNetEncryption()
    {
        using var corpus = Corpus("crypto/encryption-v2.json");
        var content = corpus.RootElement.GetProperty("content");
        var key = Bytes(content, "key");
        Assert.Equal(Bytes(corpus.RootElement.GetProperty("recovery"), "vaultKey"), key);
        var record = content.GetProperty("record");
        var image = content.GetProperty("attachment");
        var recordId = Guid.Parse(Text(record, "id"));
        var imageId = Guid.Parse(Text(image, "id"));
        Assert.Equal($"journal:v1:record:{Text(record, "kind")}:{recordId}", Text(record, "context"));
        Assert.Equal($"journal:v1:attachment:{imageId}", Text(image, "context"));
        AssertSealed(key, Bytes(record, "plaintext"), Bytes(record, "combined"), Text(record, "context"));
        AssertSealed(key, Bytes(image, "plaintext"), Bytes(image, "combined"), Text(image, "context"));
        // The smallest ciphertext the server accepts for records and images in encrypted libraries.
        Assert.True(Bytes(image, "combined").Length >= 29);

        // The plaintext names the same record as its context; UUID case differs between the two.
        using var item = JsonDocument.Parse(Bytes(record, "plaintext"));
        var expected = record.GetProperty("expected");
        Assert.Equal(recordId, Guid.Parse(Text(item.RootElement, "id")));
        Assert.Equal(Text(record, "kind"), Text(item.RootElement, "kind"));
        Assert.Equal(Guid.Parse(Text(expected, "journalID")), Guid.Parse(Text(item.RootElement, "journalID")));
        Assert.Equal(Text(expected, "title"), Text(item.RootElement, "title"));
        Assert.Equal(Text(expected, "date"), Text(item.RootElement, "date"));
        Assert.Equal(Text(expected, "modifiedAt"), Text(item.RootElement, "modifiedAt"));
        var document = item.RootElement.GetProperty("document");
        Assert.Equal(expected.GetProperty("documentVersion").GetInt32(), document.GetProperty("version").GetInt32());
        Assert.Equal(Text(expected, "markdown"), Text(document, "markdown"));
        Assert.Contains($"(attachments/{imageId})", Text(document, "markdown"), StringComparison.Ordinal);
        Assert.Equal(Text(expected.GetProperty("imageTypes"), imageId.ToString()), Text(document.GetProperty("metadata").GetProperty("imageTypes"), imageId.ToString()));
    }
}
