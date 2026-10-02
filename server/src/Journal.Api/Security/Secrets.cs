using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Security;

public static class Secrets
{
    public static string NewToken() => Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
    public static string Hash(string text) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    public static bool Matches(string text, string hash) => CryptographicOperations.FixedTimeEquals(
        Encoding.UTF8.GetBytes(Hash(text)), Encoding.UTF8.GetBytes(hash));

    // Accepts only canonical padded base64 (RFC 4648 section 4): no whitespace or line breaks and zero
    // padding bits. Every client decoder then reads exactly the bytes the server stored and relays.
    public static bool IsBase64(string? value, int minBytes, int maxBytes)
    {
        if (value is null || value.Length % 4 != 0 || value.Length > (maxBytes + 2) / 3 * 4)
        {
            return false;
        }
        var padding = value.EndsWith("==", StringComparison.Ordinal) ? 2 : value.EndsWith('=') ? 1 : 0;
        for (var index = 0; index < value.Length - padding; index++)
        {
            if (Sextet(value[index]) < 0)
            {
                return false;
            }
        }
        // The low bits of the last encoded character that the padding leaves unused must be zero.
        var unusedBits = padding == 2 ? 0b1111 : 0b11;
        if (padding > 0 && (Sextet(value[value.Length - padding - 1]) & unusedBits) != 0)
        {
            return false;
        }
        var length = value.Length / 4 * 3 - padding;
        return length >= minBytes && length <= maxBytes;
    }

    private static int Sextet(char character) => character switch
    {
        >= 'A' and <= 'Z' => character - 'A',
        >= 'a' and <= 'z' => character - 'a' + 26,
        >= '0' and <= '9' => character - '0' + 52,
        '+' => 62,
        '/' => 63,
        _ => -1,
    };
}

// Serializes mutating transactions in the supported single-instance SQLite deployment.
public sealed class WriteGate : IDisposable
{
    private readonly SemaphoreSlim semaphore = new(1, 1);
    public void Dispose() => semaphore.Dispose();
    public async Task<IDisposable> Enter(CancellationToken ct)
    {
        await semaphore.WaitAsync(ct);
        return new Lease(semaphore);
    }
    private sealed class Lease(SemaphoreSlim semaphore) : IDisposable
    {
        public void Dispose() => semaphore.Release();
    }
}
public sealed record StoragePaths(string Root)
{
    public string AttachmentDirectory => Path.Combine(Root, "attachments");
    public string BootstrapFile => Path.Combine(Root, "setup-code");
}
