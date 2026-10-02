using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Security;

// Key material of agent access (protocol/agent-access-server.md, Keys and tokens). A grant's copy key is never stored
// in the clear: each token carries its own secret, and the server keeps the copy key wrapped under that secret only
// while the token lives.
public static class AgentKeys
{
    public const int KeyLength = 32;
    public const int WrappedLength = 12 + KeyLength + 16;

    // The approving device's wrap, opened once when the authorization code is redeemed.
    public static byte[] Wrap(ReadOnlySpan<byte> copyKey, ReadOnlySpan<byte> secret, Guid grantId) =>
        Seal(copyKey, secret, GrantWrapInfo, Context(grantId));

    // The copy key, or null when the secret doesn't open this wrap (authentication fails).
    public static byte[]? Unwrap(ReadOnlySpan<byte> wrapped, ReadOnlySpan<byte> secret, Guid grantId) =>
        Open(wrapped, secret, GrantWrapInfo, Context(grantId));

    private static byte[] Seal(ReadOnlySpan<byte> copyKey, ReadOnlySpan<byte> secret, byte[] info, byte[] context)
    {
        var wrap = HKDF.DeriveKey(HashAlgorithmName.SHA256, secret.ToArray(), KeyLength, [], info);
        try
        {
            var result = new byte[WrappedLength];
            RandomNumberGenerator.Fill(result.AsSpan(0, 12));
            using var aes = new AesGcm(wrap, 16);
            aes.Encrypt(result.AsSpan(0, 12), copyKey, result.AsSpan(12, KeyLength), result.AsSpan(12 + KeyLength), context);
            return result;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(wrap);
        }
    }

    private static byte[]? Open(ReadOnlySpan<byte> wrapped, ReadOnlySpan<byte> secret, byte[] info, byte[] context)
    {
        if (wrapped.Length != WrappedLength || secret.Length != KeyLength)
        {
            return null;
        }
        var wrap = HKDF.DeriveKey(HashAlgorithmName.SHA256, secret.ToArray(), KeyLength, [], info);
        var key = new byte[KeyLength];
        try
        {
            using var aes = new AesGcm(wrap, 16);
            aes.Decrypt(wrapped[..12], wrapped.Slice(12, KeyLength), wrapped[(12 + KeyLength)..], key, context);
            return key;
        }
        catch (AuthenticationTagMismatchException)
        {
            CryptographicOperations.ZeroMemory(key);
            return null;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(wrap);
        }
    }

    // The copy key wrapped for one token: its own HKDF info and a context naming the token, so a wrap can't be moved to
    // another token or mistaken for the approving device's.
    public static byte[] WrapForToken(ReadOnlySpan<byte> copyKey, ReadOnlySpan<byte> secret, Guid grantId, Guid tokenId) =>
        Seal(copyKey, secret, TokenWrapInfo, TokenContext(grantId, tokenId));

    public static byte[]? UnwrapForToken(ReadOnlySpan<byte> wrapped, ReadOnlySpan<byte> secret, Guid grantId, Guid tokenId) =>
        Open(wrapped, secret, TokenWrapInfo, TokenContext(grantId, tokenId));

    private static readonly byte[] GrantWrapInfo = "journal:v1:agent-grant-wrap"u8.ToArray();
    private static readonly byte[] TokenWrapInfo = "journal:v1:agent-token-wrap"u8.ToArray();

    private static byte[] Context(Guid grantId) => Encoding.UTF8.GetBytes("journal:v1:agent-grant:" + grantId.ToString("D"));

    private static byte[] TokenContext(Guid grantId, Guid tokenId) =>
        Encoding.UTF8.GetBytes("journal:v1:agent-token-wrap:" + grantId.ToString("D") + ":" + tokenId.ToString("D"));
}

// An access or refresh token: its row ID, a verifier whose hash the server keeps, and the secret its key wrap needs.
public sealed class AgentToken
{
    public const string AccessPrefix = "mjat_";
    public const string RefreshPrefix = "mjrt_";
    private const int Length = 16 + 32 + AgentKeys.KeyLength;

    private AgentToken(string kind, Guid id, byte[] verifier, byte[] secret)
    {
        Kind = kind;
        Id = id;
        Verifier = verifier;
        Secret = secret;
    }

    public string Kind
    {
        get;
    }
    public Guid Id
    {
        get;
    }
    public byte[] Verifier
    {
        get;
    }
    public byte[] Secret
    {
        get;
    }

    public string VerifierHash => Convert.ToHexStringLower(SHA256.HashData(Verifier));

    public static AgentToken New(string kind) =>
        new(kind, Guid.NewGuid(), RandomNumberGenerator.GetBytes(32), RandomNumberGenerator.GetBytes(AgentKeys.KeyLength));

    public string Encoded
    {
        get
        {
            var bytes = new byte[Length];
            Id.TryWriteBytes(bytes.AsSpan(0, 16), bigEndian: true, out _);
            Verifier.CopyTo(bytes, 16);
            Secret.CopyTo(bytes, 48);
            return (Kind == Data.OAuthTokenKind.Access ? AccessPrefix : RefreshPrefix) + Base64Url.EncodeToString(bytes);
        }
    }

    public static AgentToken? Parse(string? text, string expectedKind)
    {
        var prefix = expectedKind == Data.OAuthTokenKind.Access ? AccessPrefix : RefreshPrefix;
        if (text is null || text.Length > 200 || !text.StartsWith(prefix, StringComparison.Ordinal))
        {
            return null;
        }
        byte[] bytes;
        try
        {
            bytes = Base64Url.DecodeFromChars(text.AsSpan(prefix.Length));
        }
        catch (FormatException)
        {
            return null;
        }
        if (bytes.Length != Length)
        {
            return null;
        }
        return new AgentToken(expectedKind, new Guid(bytes.AsSpan(0, 16), bigEndian: true), bytes[16..48], bytes[48..]);
    }

    public bool Matches(string storedHash) => CryptographicOperations.FixedTimeEquals(
        Encoding.ASCII.GetBytes(VerifierHash), Encoding.ASCII.GetBytes(storedHash));
}
