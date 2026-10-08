using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Tests;

// The wire formats of protocol/README.md and records.md, parsed strictly and independently of the server.
internal static class ConformanceFormats
{
    // The literal 'Z' carries no offset in a format string, so UTC is assumed for it; a numeric offset is read as given.
    // An ISO 8601 date and time with Z or a numeric offset and 0 to 7 fraction digits, nothing else.
    private static readonly string[] TimestampFormats = Enumerable.Range(0, 8)
        .Select(digits => "yyyy-MM-dd'T'HH:mm:ss" + (digits == 0 ? "" : "." + new string('f', digits)))
        .SelectMany(format => new[] { format + "'Z'", format + "zzz" })
        .ToArray();

    public static bool TryParseTimestamp(string? text, out DateTimeOffset instant) =>
        DateTimeOffset.TryParseExact(text, TimestampFormats, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out instant);

    // A hyphenated UUID, in either case.
    public static bool IsUuid(string? text) => text is { Length: 36 } && Guid.TryParseExact(text, "D", out _);

    // Whole seconds since the epoch, rounded down.
    public static long EpochSeconds(DateTimeOffset instant) => instant.ToUnixTimeSeconds();
}

// AES-256-GCM as the protocol seals everything: nonce (12) || ciphertext || tag (16), with the UTF-8 context as
// authenticated data.
internal static class ConformanceCrypto
{
    private const int NonceBytes = 12;
    private const int TagBytes = 16;

    // Throws ArgumentException when the input can't hold a nonce and a tag, CryptographicException when it doesn't authenticate.
    public static byte[] Open(byte[] key, byte[] combined, string context)
    {
        if (combined.Length < NonceBytes + TagBytes)
        {
            throw new ArgumentException("Too short to hold a nonce and a tag.", nameof(combined));
        }
        var plaintext = new byte[combined.Length - NonceBytes - TagBytes];
        using var aes = new AesGcm(key, TagBytes);
        aes.Decrypt(combined.AsSpan(0, NonceBytes), combined.AsSpan(NonceBytes, plaintext.Length), combined.AsSpan(combined.Length - TagBytes), plaintext, Encoding.UTF8.GetBytes(context));
        return plaintext;
    }
}
