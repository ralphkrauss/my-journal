using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Tests;

// How a typed credential opens a recovery envelope (protocol/README.md, Recovery formats), shared by the readers of both
// archive kinds.
internal static class ArchiveCrypto
{
    // The credentials a password opens an envelope with: formats 2 and 3 use its NFC form first and, when that differs
    // from what was typed, the exact text; format 1 trims. Nothing else is tried.
    public static IEnumerable<string> PasswordCandidates(int formatVersion, string typed)
    {
        if (formatVersion == 1)
        {
            yield return typed.Trim();
            yield break;
        }
        var normalized = typed.Normalize(NormalizationForm.FormC);
        yield return normalized;
        if (!string.Equals(normalized, typed, StringComparison.Ordinal))
        {
            yield return typed;
        }
    }

    // The vault key, or null when no candidate opens the envelope.
    public static byte[]? UnwrapVaultKey(int formatVersion, byte[] salt, int iterations, byte[] wrappedKey, string password)
    {
        foreach (var candidate in PasswordCandidates(formatVersion, password))
        {
            var wrappingKey = Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(candidate), salt, iterations, HashAlgorithmName.SHA256, 32);
            try
            {
                return ConformanceCrypto.Open(wrappingKey, wrappedKey, $"journal:v{formatVersion}:recovery");
            }
            catch (Exception exception) when (exception is CryptographicException or ArgumentException)
            {
            }
        }
        return null;
    }
}
