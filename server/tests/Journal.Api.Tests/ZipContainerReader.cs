using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Journal.Api.Tests;

// One entry of the central directory, as the profile reads it: sizes, offsets and the method come from the central
// directory only. NameBytes are the bytes of the name, compared as bytes.
internal sealed record ZipEntry(string Name, byte[] NameBytes, ushort Flags, ushort Method, uint Crc32, ulong CompressedSize, ulong Size, ulong LocalHeaderOffset);

// An entry whose local header was read: where its data starts and where its range (first local header byte to last
// data byte) ends.
internal sealed record LocatedZipEntry(ZipEntry Entry, ulong DataOffset, ulong RangeEnd);

// The ZIP layer of the file archive (protocol/archive.md, ZIP profile: readers), parsed here and not by
// System.IO.Compression.ZipArchive, which hides duplicates, overlaps and CRC-32 and opens every entry at once.
internal sealed class ZipContainerReader : IDisposable
{
    public const int MaximumCentralDirectoryBytes = 64 << 20;
    public const int MaximumEntries = 300_000;
    public const int MaximumHeaderBytes = 16 << 20;
    private const int Chunk = 256 * 1024;
    private const int MaximumEndRecordScan = 22 + 65535;
    private const uint EndRecordSignature = 0x06054b50;
    private const uint Zip64LocatorSignature = 0x07064b50;
    private const uint Zip64EndRecordSignature = 0x06064b50;
    private const uint CentralSignature = 0x02014b50;
    private const uint LocalSignature = 0x04034b50;
    private const ushort Saturated16 = 0xFFFF;
    private const uint Saturated32 = 0xFFFFFFFF;

    private readonly SafeFileHandle _file;
    private readonly ulong _length;
    private readonly ulong _directoryOffset;
    private readonly Dictionary<string, ZipEntry> _kept;
    private LocatedZipEntry? _header;
    private List<LocatedZipEntry> _opened = [];

    private ZipContainerReader(SafeFileHandle file, ulong length, ulong directoryOffset, Dictionary<string, ZipEntry> kept, IReadOnlyList<ZipEntry> order)
    {
        _file = file;
        _length = length;
        _directoryOffset = directoryOffset;
        _kept = kept;
        KeptEntries = order;
    }

    // The entries the profile names, in central directory order. Every other entry was skipped as it streamed past.
    public IReadOnlyList<ZipEntry> KeptEntries
    {
        get;
    }

    // archive.json and the listed entries once ExtractListed has located them, in central directory order. Unlisted
    // entries are never opened, so they are not here.
    public IReadOnlyList<LocatedZipEntry> OpenedEntries => KeptEntries.Select(entry => _opened.FirstOrDefault(opened => opened.Entry == entry)).OfType<LocatedZipEntry>().ToList();

    // Finds the end records, checks the central directory's size and entry count, and reads the directory keeping only
    // the profile names. Nothing of an entry is opened.
    public static ZipContainerReader Open(string path)
    {
        var file = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            var length = (ulong)RandomAccess.GetLength(file);
            var end = FindEndRecords(file, length);
            var directory = ReadAt(file, length, end.DirectoryOffset, (int)end.DirectorySize);
            var (kept, order) = ParseDirectory(directory, end.Entries);
            return new ZipContainerReader(file, length, end.DirectoryOffset, kept, order);
        }
        catch
        {
            file.Dispose();
            throw;
        }
    }

    public void Dispose() => _file.Dispose();

    // archive.json: declared size at most 16 MiB, then the entry rules, CRC-32 checked before anything decodes it.
    public byte[] ReadHeader()
    {
        if (!_kept.TryGetValue("archive.json", out var entry))
        {
            throw ArchiveRefusal.Damaged("there is no archive.json");
        }
        if (entry.Size > MaximumHeaderBytes)
        {
            throw ArchiveRefusal.Damaged("archive.json is larger than 16 MiB");
        }
        _header = Locate(entry);
        using var content = new MemoryStream();
        Extract(_header, content, null);
        return content.ToArray();
    }

    // The data of journal.sqlite and every listed image, keyed by "journal.sqlite" and the UUID. The manifest is checked
    // against the central directory, then the data ranges, and only then is any data read.
    public Dictionary<string, byte[]> ExtractListed(ArchiveManifest manifest)
    {
        var header = _header ?? throw new InvalidOperationException("Read the header first.");
        var listed = new List<(string Key, string EntryName, ManifestEntry Manifest)> { ("journal.sqlite", "journal.sqlite", manifest.Database) };
        listed.AddRange(manifest.Attachments.Select(image => (image.Key, "attachments/" + image.Key, image.Value)));
        var located = new List<LocatedZipEntry> { header };
        foreach (var (_, entryName, listedEntry) in listed)
        {
            if (!_kept.TryGetValue(entryName, out var entry))
            {
                throw ArchiveRefusal.Damaged($"{entryName} is listed but has no entry");
            }
            if (entry.Size != (ulong)listedEntry.Bytes)
            {
                throw ArchiveRefusal.Damaged($"{entryName} has another size than the manifest lists");
            }
            located.Add(Locate(entry));
        }
        RequireDisjoint(located);
        _opened = located;
        var files = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        for (var index = 0; index < listed.Count; index++)
        {
            using var content = new MemoryStream();
            Extract(located[index + 1], content, listed[index].Manifest.Sha256);
            files[listed[index].Key] = content.ToArray();
        }
        return files;
    }

    // Reads the local header of an entry: signature, the same name bytes and method as the central entry; its sizes and
    // CRC-32 are never looked at. The data starts after the local name and extra field.
    public LocatedZipEntry Locate(ZipEntry entry)
    {
        var headerEnd = Add(entry.LocalHeaderOffset, 30);
        if (headerEnd > _directoryOffset)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has its local header outside the file before the central directory");
        }
        var local = ReadAt(_file, _length, entry.LocalHeaderOffset, 30);
        if (BinaryPrimitives.ReadUInt32LittleEndian(local) != LocalSignature)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} is not at a local header");
        }
        if (BinaryPrimitives.ReadUInt16LittleEndian(local.AsSpan(8)) != entry.Method)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has another method in its local header");
        }
        var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(local.AsSpan(26));
        var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(local.AsSpan(28));
        var dataOffset = Add(Add(headerEnd, nameLength), extraLength);
        if (dataOffset > _directoryOffset)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has its local name and extra field past the central directory");
        }
        var localName = ReadAt(_file, _length, headerEnd, nameLength);
        if (!localName.AsSpan().SequenceEqual(entry.NameBytes))
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has another name in its local header");
        }
        var rangeEnd = Add(dataOffset, entry.CompressedSize);
        if (rangeEnd > _directoryOffset)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has data that reaches the central directory or the end of the file");
        }
        return new LocatedZipEntry(entry, dataOffset, rangeEnd);
    }

    private static void RequireDisjoint(List<LocatedZipEntry> located)
    {
        var ranges = located.Select(item => (Start: item.Entry.LocalHeaderOffset, End: item.RangeEnd, item.Entry.Name)).OrderBy(range => range.Start).ToList();
        for (var index = 1; index < ranges.Count; index++)
        {
            if (ranges[index].Start < ranges[index - 1].End)
            {
                throw ArchiveRefusal.Damaged($"the data of {ranges[index - 1].Name} and {ranges[index].Name} overlap");
            }
        }
    }

    // The entry rules: no encryption, method 0 or 8, the stored and deflate size rules, a deflate stream that ends at the
    // declared compressed size with exactly the declared bytes, then count, CRC-32 and SHA-256 in that order. Bytes are
    // written to the destination only up to the declared size.
    private void Extract(LocatedZipEntry located, Stream destination, string? expectedSha256)
    {
        var entry = located.Entry;
        if ((entry.Flags & 0x0001) != 0 || (entry.Flags & 0x0040) != 0)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} is encrypted");
        }
        if (entry.Method is not (0 or 8))
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} uses method {entry.Method}");
        }
        if (entry.Method == 0 && entry.CompressedSize != entry.Size)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} is stored with a compressed size that is not its size");
        }
        if (entry.Method == 8 && (entry.CompressedSize == 0 || (UInt128)entry.Size > (UInt128)entry.CompressedSize * 8))
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} is deflated with an empty stream or expands more than 8 times");
        }
        using var sha256 = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var crc = Crc32.Start();
        ulong written = 0;
        void Emit(ReadOnlySpan<byte> bytes)
        {
            crc = Crc32.Update(crc, bytes);
            sha256.AppendData(bytes);
            destination.Write(bytes);
            written += (ulong)bytes.Length;
        }
        using var raw = new SingleByteSource(_file, located.DataOffset, entry.CompressedSize);
        if (entry.Method == 0)
        {
            CopyStored(raw, entry.Size, Emit);
        }
        else
        {
            InflateExactly(raw, entry, Emit);
        }
        if (written != entry.Size)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} produced {written} bytes, not {entry.Size}");
        }
        if (Crc32.Finish(crc) != entry.Crc32)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has a CRC-32 that differs from the central directory");
        }
        if (expectedSha256 is not null && !string.Equals(Convert.ToHexStringLower(sha256.GetHashAndReset()), expectedSha256, StringComparison.Ordinal))
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} differs from the SHA-256 in the manifest");
        }
    }

    private static void CopyStored(SingleByteSource raw, ulong size, Action<ReadOnlySpan<byte>> emit)
    {
        var buffer = new byte[Chunk];
        ulong remaining = size;
        while (remaining > 0)
        {
            var count = raw.ReadBlock(buffer.AsSpan(0, (int)Math.Min((ulong)Chunk, remaining)));
            if (count == 0)
            {
                throw ArchiveRefusal.Damaged("a stored entry ends before its declared size");
            }
            emit(buffer.AsSpan(0, count));
            remaining -= (ulong)count;
        }
    }

    // DeflateStream is fed one byte per read, so the number of bytes it has taken is exactly what the final block
    // needed. It must have taken them all, and it must be finished: a further read yields nothing.
    private static void InflateExactly(SingleByteSource raw, ZipEntry entry, Action<ReadOnlySpan<byte>> emit)
    {
        using var inflater = new DeflateStream(raw, CompressionMode.Decompress, leaveOpen: true);
        var buffer = new byte[Chunk];
        ulong remaining = entry.Size;
        try
        {
            while (remaining > 0)
            {
                var count = inflater.Read(buffer.AsSpan(0, (int)Math.Min((ulong)Chunk, remaining)));
                if (count == 0)
                {
                    throw ArchiveRefusal.Damaged($"{entry.Name} has a deflate stream that ends before its declared size");
                }
                emit(buffer.AsSpan(0, count));
                remaining -= (ulong)count;
            }
            if (inflater.Read(buffer.AsSpan(0, 1)) != 0)
            {
                throw ArchiveRefusal.Damaged($"{entry.Name} has a deflate stream that would produce more than its declared size");
            }
        }
        catch (InvalidDataException exception)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has a deflate stream that is not valid: {exception.Message}");
        }
        if (raw.Consumed != entry.CompressedSize)
        {
            throw ArchiveRefusal.Damaged($"{entry.Name} has {entry.CompressedSize - raw.Consumed} bytes after its deflate stream");
        }
    }

    private sealed record EndRecords(ulong DirectoryOffset, ulong DirectorySize, ulong Entries);

    private static EndRecords FindEndRecords(SafeFileHandle file, ulong length)
    {
        if (length < 22)
        {
            throw ArchiveRefusal.Damaged("the file is too short to have an end record");
        }
        var tailLength = (int)Math.Min(length, MaximumEndRecordScan);
        var tailStart = length - (ulong)tailLength;
        var tail = ReadAt(file, length, tailStart, tailLength);
        var candidates = new List<int>();
        for (var position = tailLength - 22; position >= 0; position--)
        {
            if (BinaryPrimitives.ReadUInt32LittleEndian(tail.AsSpan(position)) == EndRecordSignature
                && position + 22 + BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(position + 20)) == tailLength)
            {
                candidates.Add(position);
            }
        }
        if (candidates.Count != 1)
        {
            throw ArchiveRefusal.Damaged($"{candidates.Count} end records reach the end of the file");
        }
        var recordPosition = tailStart + (ulong)candidates[0];
        var record = tail.AsSpan(candidates[0], 22);
        var disk = BinaryPrimitives.ReadUInt16LittleEndian(record[4..]);
        var directoryDisk = BinaryPrimitives.ReadUInt16LittleEndian(record[6..]);
        var entriesOnDisk = BinaryPrimitives.ReadUInt16LittleEndian(record[8..]);
        var entries = BinaryPrimitives.ReadUInt16LittleEndian(record[10..]);
        var size = BinaryPrimitives.ReadUInt32LittleEndian(record[12..]);
        var offset = BinaryPrimitives.ReadUInt32LittleEndian(record[16..]);

        ulong directoryEnd = recordPosition;
        ulong fullDisk = disk;
        ulong fullDirectoryDisk = directoryDisk;
        ulong fullEntriesOnDisk = entriesOnDisk;
        ulong fullEntries = entries;
        ulong fullSize = size;
        ulong fullOffset = offset;
        var locatorPosition = recordPosition - 20;
        if (recordPosition >= 20 && BinaryPrimitives.ReadUInt32LittleEndian(ReadAt(file, length, locatorPosition, 4)) == Zip64LocatorSignature)
        {
            var locator = ReadAt(file, length, locatorPosition, 20);
            var recordDisk = BinaryPrimitives.ReadUInt32LittleEndian(locator.AsSpan(4));
            var zip64Position = BinaryPrimitives.ReadUInt64LittleEndian(locator.AsSpan(8));
            var totalDisks = BinaryPrimitives.ReadUInt32LittleEndian(locator.AsSpan(16));
            if (recordDisk != 0 || totalDisks > 1)
            {
                throw ArchiveRefusal.Damaged("the ZIP64 locator names another disk");
            }
            if (Add(zip64Position, 56) > locatorPosition)
            {
                throw ArchiveRefusal.Damaged("the ZIP64 end record does not lie before the locator");
            }
            var zip64 = ReadAt(file, length, zip64Position, 56);
            if (BinaryPrimitives.ReadUInt32LittleEndian(zip64) != Zip64EndRecordSignature)
            {
                throw ArchiveRefusal.Damaged("the ZIP64 locator does not point at a ZIP64 end record");
            }
            var zip64Size = BinaryPrimitives.ReadUInt64LittleEndian(zip64.AsSpan(4));
            if (zip64Size < 44 || Add(Add(zip64Position, 12), zip64Size) > locatorPosition)
            {
                throw ArchiveRefusal.Damaged("the ZIP64 end record has an impossible size");
            }
            fullDisk = BinaryPrimitives.ReadUInt32LittleEndian(zip64.AsSpan(16));
            fullDirectoryDisk = BinaryPrimitives.ReadUInt32LittleEndian(zip64.AsSpan(20));
            fullEntriesOnDisk = BinaryPrimitives.ReadUInt64LittleEndian(zip64.AsSpan(24));
            fullEntries = BinaryPrimitives.ReadUInt64LittleEndian(zip64.AsSpan(32));
            fullSize = BinaryPrimitives.ReadUInt64LittleEndian(zip64.AsSpan(40));
            fullOffset = BinaryPrimitives.ReadUInt64LittleEndian(zip64.AsSpan(48));
            if ((disk != Saturated16 && disk != fullDisk)
                || (directoryDisk != Saturated16 && directoryDisk != fullDirectoryDisk)
                || (entriesOnDisk != Saturated16 && entriesOnDisk != fullEntriesOnDisk)
                || (entries != Saturated16 && entries != fullEntries)
                || (size != Saturated32 && size != fullSize)
                || (offset != Saturated32 && offset != fullOffset))
            {
                throw ArchiveRefusal.Damaged("the ordinary and the ZIP64 end records disagree");
            }
            directoryEnd = zip64Position;
        }
        else if (disk == Saturated16 || directoryDisk == Saturated16 || entriesOnDisk == Saturated16 || entries == Saturated16 || size == Saturated32 || offset == Saturated32)
        {
            throw ArchiveRefusal.Damaged("the end record is saturated and there is no ZIP64 locator");
        }
        if (fullDisk != 0 || fullDirectoryDisk != 0 || fullEntriesOnDisk != fullEntries)
        {
            throw ArchiveRefusal.Damaged("the archive is not on one disk");
        }
        if (fullSize > MaximumCentralDirectoryBytes || fullEntries > MaximumEntries)
        {
            throw ArchiveRefusal.Damaged("the central directory is over 64 MiB or 300,000 entries");
        }
        if (Add(fullOffset, fullSize) != directoryEnd)
        {
            throw ArchiveRefusal.Damaged("the central directory does not end where the end record begins");
        }
        return new EndRecords(fullOffset, fullSize, fullEntries);
    }

    private static (Dictionary<string, ZipEntry> Kept, List<ZipEntry> Order) ParseDirectory(byte[] directory, ulong declaredEntries)
    {
        var kept = new Dictionary<string, ZipEntry>(StringComparer.Ordinal);
        var order = new List<ZipEntry>();
        ulong count = 0;
        var position = 0;
        while (position < directory.Length)
        {
            if (directory.Length - position < 46 || BinaryPrimitives.ReadUInt32LittleEndian(directory.AsSpan(position)) != CentralSignature)
            {
                throw ArchiveRefusal.Damaged("the central directory holds something that is not an entry");
            }
            var header = directory.AsSpan(position, 46);
            var flags = BinaryPrimitives.ReadUInt16LittleEndian(header[8..]);
            var method = BinaryPrimitives.ReadUInt16LittleEndian(header[10..]);
            var crc = BinaryPrimitives.ReadUInt32LittleEndian(header[16..]);
            var compressed32 = BinaryPrimitives.ReadUInt32LittleEndian(header[20..]);
            var size32 = BinaryPrimitives.ReadUInt32LittleEndian(header[24..]);
            var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(header[28..]);
            var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(header[30..]);
            var commentLength = BinaryPrimitives.ReadUInt16LittleEndian(header[32..]);
            var disk16 = BinaryPrimitives.ReadUInt16LittleEndian(header[34..]);
            var offset32 = BinaryPrimitives.ReadUInt32LittleEndian(header[42..]);
            var next = position + 46 + nameLength + extraLength + commentLength;
            if (next > directory.Length)
            {
                throw ArchiveRefusal.Damaged("a central directory entry runs past the end of the directory");
            }
            if ((flags & 0x2000) != 0)
            {
                throw ArchiveRefusal.Damaged("the central directory is encrypted");
            }
            count++;
            if (count > MaximumEntries)
            {
                throw ArchiveRefusal.Damaged("the central directory has more than 300,000 entries");
            }
            var nameBytes = directory.AsSpan(position + 46, nameLength).ToArray();
            if (ProfileName(nameBytes) is { } name)
            {
                var extra = directory.AsSpan(position + 46 + nameLength, extraLength);
                var (size, compressed, offset, disk) = ApplyZip64(extra, size32, compressed32, offset32, disk16, name);
                if (disk != 0)
                {
                    throw ArchiveRefusal.Damaged($"{name} starts on another disk");
                }
                var entry = new ZipEntry(name, nameBytes, flags, method, crc, compressed, size, offset);
                if (!kept.TryAdd(name, entry))
                {
                    throw ArchiveRefusal.Damaged($"{name} appears twice");
                }
                order.Add(entry);
            }
            position = next;
        }
        if (count != declaredEntries)
        {
            throw ArchiveRefusal.Damaged($"the end record counts {declaredEntries} entries and the directory holds {count}");
        }
        return (kept, order);
    }

    // archive.json, journal.sqlite or attachments/<lower-case UUID>, compared as bytes; null for any other name.
    private static string? ProfileName(byte[] nameBytes)
    {
        if (nameBytes.Any(value => value >= 0x80))
        {
            return null;
        }
        var text = Encoding.ASCII.GetString(nameBytes);
        if (text is "archive.json" or "journal.sqlite")
        {
            return text;
        }
        return text.StartsWith("attachments/", StringComparison.Ordinal) && ArchiveNames.IsUuid(text["attachments/".Length..]) ? text : null;
    }

    // The ZIP64 extra field carries, in this order, only the values whose 32-bit field is saturated.
    private static (ulong Size, ulong Compressed, ulong Offset, uint Disk) ApplyZip64(ReadOnlySpan<byte> extra, uint size32, uint compressed32, uint offset32, ushort disk16, string name)
    {
        ulong size = size32;
        ulong compressed = compressed32;
        ulong offset = offset32;
        uint disk = disk16;
        var needed = (size32 == Saturated32 ? 8 : 0) + (compressed32 == Saturated32 ? 8 : 0) + (offset32 == Saturated32 ? 8 : 0) + (disk16 == Saturated16 ? 4 : 0);
        if (needed == 0)
        {
            return (size, compressed, offset, disk);
        }
        var data = FindExtraField(extra, 0x0001);
        if (data.Length < needed)
        {
            throw ArchiveRefusal.Damaged($"{name} has saturated fields and a missing or short ZIP64 extra field");
        }
        var cursor = 0;
        if (size32 == Saturated32)
        {
            size = BinaryPrimitives.ReadUInt64LittleEndian(data[cursor..]);
            cursor += 8;
        }
        if (compressed32 == Saturated32)
        {
            compressed = BinaryPrimitives.ReadUInt64LittleEndian(data[cursor..]);
            cursor += 8;
        }
        if (offset32 == Saturated32)
        {
            offset = BinaryPrimitives.ReadUInt64LittleEndian(data[cursor..]);
            cursor += 8;
        }
        if (disk16 == Saturated16)
        {
            disk = BinaryPrimitives.ReadUInt32LittleEndian(data[cursor..]);
        }
        return (size, compressed, offset, disk);
    }

    private static ReadOnlySpan<byte> FindExtraField(ReadOnlySpan<byte> extra, ushort identifier)
    {
        while (extra.Length >= 4)
        {
            var id = BinaryPrimitives.ReadUInt16LittleEndian(extra);
            var length = BinaryPrimitives.ReadUInt16LittleEndian(extra[2..]);
            if (4 + length > extra.Length)
            {
                break;
            }
            if (id == identifier)
            {
                return extra.Slice(4, length);
            }
            extra = extra[(4 + length)..];
        }
        return [];
    }

    private static byte[] ReadAt(SafeFileHandle file, ulong fileLength, ulong offset, int count)
    {
        if (Add(offset, (ulong)count) > fileLength)
        {
            throw ArchiveRefusal.Damaged("a structure lies outside the file");
        }
        var buffer = new byte[count];
        RandomAccess.Read(file, buffer, (long)offset);
        return buffer;
    }

    // Unsigned 64-bit arithmetic with overflow detection: an overflow is damaged.
    private static ulong Add(ulong left, ulong right)
    {
        try
        {
            return checked(left + right);
        }
        catch (OverflowException)
        {
            throw ArchiveRefusal.Damaged("an offset or size overflows");
        }
    }

    // Compressed bytes from the file, handed out one per read and counted, so the deflate decoder cannot take more than
    // the stream needs.
    private sealed class SingleByteSource : Stream
    {
        private readonly SafeFileHandle _file;
        private readonly ulong _start;
        private readonly ulong _length;
        private readonly byte[] _buffer = new byte[Chunk];
        private int _buffered;
        private int _next;

        public SingleByteSource(SafeFileHandle file, ulong start, ulong length)
        {
            _file = file;
            _start = start;
            _length = length;
        }

        public ulong Consumed
        {
            get; private set;
        }

        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));

        public override int Read(Span<byte> destination)
        {
            if (destination.Length == 0)
            {
                return 0;
            }
            return ReadBlock(destination[..1]);
        }

        // Up to destination.Length bytes of what remains of the entry's compressed data.
        public int ReadBlock(Span<byte> destination)
        {
            var wanted = (int)Math.Min((ulong)destination.Length, _length - Consumed);
            var done = 0;
            while (done < wanted)
            {
                if (_next == _buffered)
                {
                    var request = (int)Math.Min((ulong)Chunk, _length - Consumed);
                    _buffered = RandomAccess.Read(_file, _buffer.AsSpan(0, request), (long)(_start + Consumed));
                    _next = 0;
                    if (_buffered == 0)
                    {
                        break;
                    }
                }
                var take = Math.Min(wanted - done, _buffered - _next);
                _buffer.AsSpan(_next, take).CopyTo(destination[done..]);
                _next += take;
                done += take;
                Consumed += (ulong)take;
            }
            return done;
        }

        public override void Flush()
        {
        }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}

// CRC-32 (IEEE, reflected, polynomial 0xEDB88320), as ZIP stores it.
internal static class Crc32
{
    private static readonly uint[] Table = Enumerable.Range(0, 256).Select(index =>
    {
        var value = (uint)index;
        for (var bit = 0; bit < 8; bit++)
        {
            value = (value & 1) != 0 ? 0xEDB88320 ^ (value >> 1) : value >> 1;
        }
        return value;
    }).ToArray();

    public static uint Start() => 0xFFFFFFFF;

    public static uint Update(uint state, ReadOnlySpan<byte> bytes)
    {
        foreach (var value in bytes)
        {
            state = Table[(state ^ value) & 0xFF] ^ (state >> 8);
        }
        return state;
    }

    public static uint Finish(uint state) => ~state;
}
