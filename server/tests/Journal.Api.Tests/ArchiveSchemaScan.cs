using System.Buffers.Binary;

namespace Journal.Api.Tests;

// The size of the schema table (sqlite_master), checked from the file's own pages before SQLite parses it
// (protocol/archive.md, Database, Limits). SQLite parses every row of the schema the first time a statement is
// prepared, so a file with a million CREATE VIEW rows would cost minutes and hundreds of megabytes to open. Written from
// the SQLite file format document ("The Schema Table", "B-tree Pages"), not from the Swift reader.
internal static class ArchiveSchemaScan
{
    public const int MaxObjects = 64;
    public const ulong MaxPayloadBytes = 256 * 1024;
    public const int MaxPages = 256;
    private const int MaxDepth = 20;
    private const byte TableInterior = 0x05;
    private const byte TableLeaf = 0x0D;

    // Returns the number of objects. Throws damaged when the schema table is over the limits or its pages are not a
    // table b-tree that can be walked once.
    public static int Check(string file)
    {
        using var stream = File.OpenRead(file);
        var header = new byte[100];
        if (stream.Read(header, 0, header.Length) < header.Length || !header.AsSpan(0, 16).SequenceEqual("SQLite format 3\0"u8))
        {
            throw ArchiveRefusal.Damaged("the file is not a SQLite database");
        }
        var stored = BinaryPrimitives.ReadUInt16BigEndian(header.AsSpan(16));
        var pageSize = stored == 1 ? 65_536 : stored;
        if (pageSize is < 512 or > 65_536 || (pageSize & (pageSize - 1)) != 0)
        {
            throw ArchiveRefusal.Damaged($"the page size {pageSize} is not valid");
        }
        var pageCount = stream.Length / pageSize;
        var pending = new Stack<(long Page, int Depth)>();
        pending.Push((1, 1));
        var visited = new HashSet<long>();
        var rows = 0;
        ulong payload = 0;
        while (pending.Count > 0)
        {
            var (number, depth) = pending.Pop();
            if (depth > MaxDepth || number < 1 || number > pageCount || !visited.Add(number) || visited.Count > MaxPages)
            {
                throw ArchiveRefusal.Damaged("the schema table's pages are not a tree that can be walked once within the limits");
            }
            var page = new byte[pageSize];
            stream.Position = (number - 1) * pageSize;
            stream.ReadExactly(page);
            var start = number == 1 ? 100 : 0;
            var cells = BinaryPrimitives.ReadUInt16BigEndian(page.AsSpan(start + 3));
            switch (page[start])
            {
                case TableLeaf:
                    foreach (var pointer in CellPointers(page, start + 8, cells))
                    {
                        rows++;
                        payload += Varint(page, pointer);
                        if (rows > MaxObjects || payload > MaxPayloadBytes)
                        {
                            throw ArchiveRefusal.Damaged($"the schema has more than {MaxObjects} objects or {MaxPayloadBytes} bytes");
                        }
                    }
                    break;
                case TableInterior:
                    var children = CellPointers(page, start + 12, cells).Select(pointer => (long)ReadChild(page, pointer)).ToList();
                    children.Add(BinaryPrimitives.ReadUInt32BigEndian(page.AsSpan(start + 8)));
                    if (pending.Count + visited.Count + children.Count > MaxPages)
                    {
                        throw ArchiveRefusal.Damaged("the schema table has too many pages");
                    }
                    children.ForEach(child => pending.Push((child, depth + 1)));
                    break;
                default:
                    throw ArchiveRefusal.Damaged("a schema page is not a table b-tree page");
            }
        }
        return rows;
    }

    private static uint ReadChild(byte[] page, int pointer) =>
        pointer + 4 <= page.Length ? BinaryPrimitives.ReadUInt32BigEndian(page.AsSpan(pointer)) : throw ArchiveRefusal.Damaged("a cell lies outside its page");

    private static List<int> CellPointers(byte[] page, int arrayStart, int cells)
    {
        if (arrayStart + (2 * cells) > page.Length)
        {
            throw ArchiveRefusal.Damaged("the cell pointer array runs past its page");
        }
        var pointers = new List<int>(cells);
        for (var index = 0; index < cells; index++)
        {
            var pointer = BinaryPrimitives.ReadUInt16BigEndian(page.AsSpan(arrayStart + (2 * index)));
            if (pointer < arrayStart + (2 * cells) || pointer >= page.Length)
            {
                throw ArchiveRefusal.Damaged("a cell pointer lies outside the cell area");
            }
            pointers.Add(pointer);
        }
        return pointers;
    }

    // SQLite's varint: seven bits per byte with the high bit set while more follow, eight bits in the ninth byte.
    private static ulong Varint(byte[] page, int offset)
    {
        ulong value = 0;
        for (var index = 0; index < 9; index++)
        {
            if (offset + index >= page.Length)
            {
                throw ArchiveRefusal.Damaged("a cell lies outside its page");
            }
            var current = page[offset + index];
            if (index == 8)
            {
                return (value << 8) | current;
            }
            value = (value << 7) | (uint)(current & 0x7F);
            if ((current & 0x80) == 0)
            {
                return value;
            }
        }
        return value;
    }
}
