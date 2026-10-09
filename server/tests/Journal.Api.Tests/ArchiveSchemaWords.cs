using System.Text;

namespace Journal.Api.Tests;

// The words of a stored CREATE statement that no pragma reports and that change what a table does
// (protocol/archive.md, Database). A statement that contains one outside quotes and comments is refused.
internal static class ArchiveSchemaWords
{
    private static readonly HashSet<string> Refused = ["AS", "CHECK", "COLLATE", "CONFLICT", "DEFERRABLE", "GENERATED", "VIRTUAL"];

    public static IEnumerable<string> RefusedWordsIn(string sql) => Words(sql).Where(Refused.Contains).Order(StringComparer.Ordinal);

    // The upper-case words: runs of ASCII letters, digits, '_' and '$' and of bytes of 0x80 or more (SQLite reads those as
    // one identifier), outside '...', "...", `...` and [...] and outside -- and /* */ comments. An unterminated quote or
    // comment runs to the end.
    public static HashSet<string> Words(string sql)
    {
        var bytes = Encoding.UTF8.GetBytes(sql);
        var found = new HashSet<string>(StringComparer.Ordinal);
        var index = 0;
        while (index < bytes.Length)
        {
            var current = bytes[index];
            var next = index + 1 < bytes.Length ? bytes[index + 1] : (byte)0;
            if (current is (byte)'\'' or (byte)'"' or (byte)'`')
            {
                index = EndOfQuoted(bytes, index, current);
            }
            else if (current == (byte)'[')
            {
                index = EndOfQuoted(bytes, index, (byte)']');
            }
            else if (current == (byte)'-' && next == (byte)'-')
            {
                var newline = Array.IndexOf(bytes, (byte)'\n', index);
                index = newline < 0 ? bytes.Length : newline + 1;
            }
            else if (current == (byte)'/' && next == (byte)'*')
            {
                var end = IndexOf(bytes, "*/"u8, index + 2);
                index = end < 0 ? bytes.Length : end + 2;
            }
            else if (IsWordByte(current))
            {
                var last = index;
                while (last + 1 < bytes.Length && IsWordByte(bytes[last + 1]))
                {
                    last++;
                }
                found.Add(Encoding.UTF8.GetString(bytes, index, last - index + 1).ToUpperInvariant());
                index = last + 1;
            }
            else
            {
                index++;
            }
        }
        return found;
    }

    private static bool IsWordByte(byte value) =>
        value is (>= (byte)'0' and <= (byte)'9') or (>= (byte)'A' and <= (byte)'Z') or (>= (byte)'a' and <= (byte)'z') or (byte)'_' or (byte)'$' or >= 0x80;

    // A doubled quote closes the text and opens the next at once, which skips the same bytes as an escape would.
    private static int EndOfQuoted(byte[] bytes, int start, byte closing)
    {
        var close = Array.IndexOf(bytes, closing, start + 1);
        return close < 0 ? bytes.Length : close + 1;
    }

    private static int IndexOf(byte[] bytes, ReadOnlySpan<byte> pattern, int from) =>
        from > bytes.Length ? -1 : bytes.AsSpan(from).IndexOf(pattern) is var found and >= 0 ? from + found : -1;
}
