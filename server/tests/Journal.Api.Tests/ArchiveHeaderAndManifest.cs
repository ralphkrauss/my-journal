using System.Numerics;
using System.Text.Json;
using Journal.Api.Security;

namespace Journal.Api.Tests;

// The envelope of a file archive's archive.json: what a reader checks before it asks for a password.
internal sealed record ArchiveHeader(int FormatVersion, byte[] Salt, int Iterations, byte[] WrappedKey, byte[] SealedManifest)
{
    private const int SaltBytes = 16;
    private const int MinimumIterations = 100_000;
    private const int MaximumIterations = 2_000_000;
    private const int MaximumManifestBytes = 16 << 20;

    // archiveVersion greater than 2 is newer; a missing, non-integer or smaller one is damaged. A newer header is
    // refused before anything else of it is read, because its other members mean whatever that version says.
    public static ArchiveHeader Parse(ReadOnlySpan<byte> json)
    {
        using var document = ArchiveStrictJson.Parse(json, "archive.json");
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("archiveVersion", out var versionElement))
        {
            throw ArchiveRefusal.Damaged("archive.json has no archiveVersion");
        }
        if (!ArchiveStrictJson.TryReadPlainInteger(versionElement, out var version) || version < 2)
        {
            throw ArchiveRefusal.Damaged("archiveVersion is not an integer of at least 2");
        }
        if (version > 2)
        {
            throw ArchiveRefusal.Newer($"archiveVersion {version}");
        }
        if (!root.TryGetProperty("recovery", out var recovery) || recovery.ValueKind != JsonValueKind.Object)
        {
            throw ArchiveRefusal.Damaged("archive.json has no recovery envelope");
        }
        var format = BoundedInteger(recovery, "formatVersion", 1, 2);
        var iterations = BoundedInteger(recovery, "iterations", MinimumIterations, MaximumIterations);
        var salt = Base64Member(recovery, "salt", SaltBytes, SaltBytes);
        var wrappedKey = Base64Member(recovery, "wrappedKey", 1, 1024);
        var sealedManifest = Base64Member(root, "manifest", 1, MaximumManifestBytes);
        return new ArchiveHeader(format, salt, iterations, wrappedKey, sealedManifest);
    }

    private static int BoundedInteger(JsonElement envelope, string name, int minimum, int maximum)
    {
        if (!envelope.TryGetProperty(name, out var element) || !ArchiveStrictJson.TryReadPlainInteger(element, out var value))
        {
            throw ArchiveRefusal.Damaged($"recovery.{name} is missing or not an integer");
        }
        if (value < minimum || value > maximum)
        {
            throw ArchiveRefusal.Damaged($"recovery.{name} {value} is outside {minimum} to {maximum}");
        }
        return (int)value;
    }

    private static byte[] Base64Member(JsonElement parent, string name, int minimumBytes, int maximumBytes)
    {
        if (!parent.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String || !Secrets.IsBase64(element.GetString(), minimumBytes, maximumBytes))
        {
            throw ArchiveRefusal.Damaged($"{name} is missing, not base64 or outside {minimumBytes} to {maximumBytes} bytes");
        }
        return Convert.FromBase64String(element.GetString()!);
    }
}

internal sealed record ManifestEntry(string Sha256, long Bytes);

// The manifest of a file archive, validated the way protocol/archive.md says before any key is used as a name.
internal sealed record ArchiveManifest(ManifestEntry Database, IReadOnlyDictionary<string, ManifestEntry> Attachments)
{
    public const long MaximumDatabaseBytes = 32L << 30;
    public const long MaximumImageBytes = 25L << 20;
    public const long MaximumTotalBytes = 1L << 40;

    public static ArchiveManifest Parse(ReadOnlySpan<byte> json)
    {
        using var document = ArchiveStrictJson.Parse(json, "the manifest");
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("database", out var database) || !root.TryGetProperty("attachments", out var attachments) || attachments.ValueKind != JsonValueKind.Object)
        {
            throw ArchiveRefusal.Damaged("the manifest lacks database or attachments");
        }
        var attachmentEntries = new Dictionary<string, ManifestEntry>(StringComparer.Ordinal);
        foreach (var member in attachments.EnumerateObject())
        {
            if (!ArchiveNames.IsUuid(member.Name))
            {
                throw ArchiveRefusal.Damaged("a manifest key is not a lower-case UUID");
            }
            attachmentEntries.Add(member.Name, ReadEntry(member.Value, MaximumImageBytes, $"image {member.Name}"));
        }
        var manifest = new ArchiveManifest(ReadEntry(database, MaximumDatabaseBytes, "the database"), attachmentEntries);
        var total = new BigInteger(manifest.Database.Bytes) + attachmentEntries.Values.Aggregate(BigInteger.Zero, (sum, entry) => sum + entry.Bytes);
        if (total > MaximumTotalBytes)
        {
            throw ArchiveRefusal.Damaged("the listed sizes add up to more than 1 TiB");
        }
        return manifest;
    }

    private static ManifestEntry ReadEntry(JsonElement element, long maximumBytes, string what)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty("sha256", out var hash) || hash.ValueKind != JsonValueKind.String || !ArchiveNames.IsSha256(hash.GetString()!))
        {
            throw ArchiveRefusal.Damaged($"{what} has no lower-case SHA-256");
        }
        if (!element.TryGetProperty("bytes", out var bytes) || !ArchiveStrictJson.TryReadSize(bytes, out var size))
        {
            throw ArchiveRefusal.Damaged($"{what} has no size written as a plain integer of at most 2^53 - 1");
        }
        if (size > maximumBytes)
        {
            throw ArchiveRefusal.Damaged($"{what} is over {maximumBytes} bytes");
        }
        return new ManifestEntry(hash.GetString()!, size);
    }
}
