using System.Numerics;
using System.Text;
using System.Text.Json;

namespace Journal.Api.Tests;

// The JSON and name rules shared by both archive kinds (protocol/archive.md, Rules for both kinds), written out here
// because System.Text.Json accepts a repeated member name, a byte order mark and any number where a size is read.
internal static class ArchiveStrictJson
{
    private const int MaxDepth = 32;

    // The most values of every kind (objects, arrays, strings, numbers and literals) a header and a manifest may hold:
    // about three per image for 100,000 images (protocol/archive.md, Limits).
    public const int MaxHeaderValues = 1_000;
    public const int MaxManifestValues = 400_000;
    public const long MaxSafeInteger = (1L << 53) - 1;

    // UTF-8 JSON without a byte order mark, comments or trailing commas, nesting at most 32 deep and no member name
    // repeated in any object. Throws a damaged refusal otherwise.
    public static JsonDocument Parse(ReadOnlySpan<byte> utf8, string what, int maximumValues)
    {
        if (utf8.StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }))
        {
            throw ArchiveRefusal.Damaged($"{what} starts with a byte order mark");
        }
        try
        {
            RejectRepeatedMembers(utf8, maximumValues);
            return JsonDocument.Parse(utf8.ToArray(), new JsonDocumentOptions { MaxDepth = MaxDepth });
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or ArgumentException or DecoderFallbackException)
        {
            throw ArchiveRefusal.Damaged($"{what} is not valid JSON: {exception.Message}");
        }
    }

    // Walks the tokens once, keeping the member names of every open object (compared as strings of UTF-16 code units,
    // which for valid UTF-8 text is the same as comparing the bytes) and counting values. The reader itself refuses
    // comments, trailing commas, invalid UTF-8, trailing text and nesting over the maximum.
    private static void RejectRepeatedMembers(ReadOnlySpan<byte> utf8, int maximumValues)
    {
        var reader = new Utf8JsonReader(utf8, new JsonReaderOptions { MaxDepth = MaxDepth });
        var names = new Stack<HashSet<string>?>();
        var values = 0;
        while (reader.Read())
        {
            if (reader.TokenType is not (JsonTokenType.PropertyName or JsonTokenType.EndObject or JsonTokenType.EndArray) && ++values > maximumValues)
            {
                throw ArchiveRefusal.Damaged($"more than {maximumValues} JSON values");
            }
            switch (reader.TokenType)
            {
                case JsonTokenType.StartObject:
                    names.Push([]);
                    break;
                case JsonTokenType.StartArray:
                    names.Push(null);
                    break;
                case JsonTokenType.EndObject:
                case JsonTokenType.EndArray:
                    names.Pop();
                    break;
                case JsonTokenType.PropertyName:
                    if (!names.Peek()!.Add(reader.GetString()!))
                    {
                        throw ArchiveRefusal.Damaged($"member name {reader.GetString()} is repeated");
                    }
                    break;
            }
        }
    }

    // A JSON integer written without sign, fraction, exponent or leading zero.
    public static bool TryReadPlainInteger(JsonElement element, out BigInteger value)
    {
        value = BigInteger.Zero;
        if (element.ValueKind != JsonValueKind.Number)
        {
            return false;
        }
        var text = element.GetRawText();
        if (text.Length == 0 || !text.All(char.IsAsciiDigit) || (text.Length > 1 && text[0] == '0'))
        {
            return false;
        }
        value = BigInteger.Parse(text, System.Globalization.CultureInfo.InvariantCulture);
        return true;
    }

    // A size: a plain integer of at most 2^53 - 1.
    public static bool TryReadSize(JsonElement element, out long value)
    {
        value = 0;
        if (!TryReadPlainInteger(element, out var integer) || integer > MaxSafeInteger)
        {
            return false;
        }
        value = (long)integer;
        return true;
    }
}

// Names of this format: exactly the lower-case form, never what Guid.TryParse would accept.
internal static class ArchiveNames
{
    public static bool IsUuid(string text)
    {
        if (text.Length != 36)
        {
            return false;
        }
        for (var index = 0; index < text.Length; index++)
        {
            var hyphen = index is 8 or 13 or 18 or 23;
            if (hyphen ? text[index] != '-' : !IsLowerHex(text[index]))
            {
                return false;
            }
        }
        return true;
    }

    // SHA-256 values: 64 lower-case hexadecimal characters.
    public static bool IsSha256(string text) => text.Length == 64 && text.All(IsLowerHex);

    private static bool IsLowerHex(char character) => character is (>= '0' and <= '9') or (>= 'a' and <= 'f');
}
