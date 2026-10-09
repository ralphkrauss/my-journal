using System.Security.Cryptography;

namespace Journal.Api.Tests;

// What a file archive holds once read: the manifest, the data of every listed file (keyed "journal.sqlite" and the image
// UUID), the entries the profile names and, for an encrypted archive, the vault key.
internal sealed record FileArchiveContents(ArchiveManifest Manifest, IReadOnlyDictionary<string, byte[]> Files, IReadOnlyList<LocatedZipEntry> Entries, byte[] HeaderJson, ArchiveHeader? Header, byte[]? VaultKey);

// The whole reading of a file archive (protocol/archive.md, Reading a file archive, steps 1 to 6), written from the
// document for the conformance tests. Any refusal is an ArchiveRefusal.
internal static class FileArchiveReader
{
    // Container fixtures: the manifest is handed over as text instead of being sealed, so no key is needed. With
    // parseHeader the header is also checked up to the envelope bounds.
    public static FileArchiveContents ReadWithManifest(string path, string manifestJson, bool parseHeader)
    {
        using var container = ZipContainerReader.Open(path);
        var headerJson = container.ReadHeader();
        var header = parseHeader ? ArchiveHeader.Parse(headerJson) : null;
        return Finish(container, headerJson, header, System.Text.Encoding.UTF8.GetBytes(manifestJson), null);
    }

    // A real archive: the typed password opens the envelope, the vault key opens the manifest.
    public static FileArchiveContents ReadEncrypted(string path, string password)
    {
        using var container = ZipContainerReader.Open(path);
        var headerJson = container.ReadHeader();
        var header = ArchiveHeader.Parse(headerJson);
        var vaultKey = ArchiveCrypto.UnwrapVaultKey(header.FormatVersion, header.Salt, header.Iterations, header.WrappedKey, password)
            ?? throw ArchiveRefusal.WrongPassword("the password does not open the recovery envelope");
        byte[] manifestJson;
        try
        {
            manifestJson = ConformanceCrypto.Open(vaultKey, header.SealedManifest, "journal:v2:archive");
        }
        catch (Exception exception) when (exception is CryptographicException or ArgumentException)
        {
            throw ArchiveRefusal.Damaged("the manifest does not authenticate");
        }
        return Finish(container, headerJson, header, manifestJson, vaultKey);
    }

    private static FileArchiveContents Finish(ZipContainerReader container, byte[] headerJson, ArchiveHeader? header, byte[] manifestJson, byte[]? vaultKey)
    {
        var manifest = ArchiveManifest.Parse(manifestJson);
        var files = container.ExtractListed(manifest);
        return new FileArchiveContents(manifest, files, container.OpenedEntries, headerJson, header, vaultKey);
    }
}
