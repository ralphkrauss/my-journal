using System.Security.Cryptography;
using System.Text;

namespace Journal.Api.Security;

// The one-time setup code in the protected data directory. A missing, empty or damaged file never
// yields a usable code: setup fails closed and the next start writes a new one. Codes are six
// characters without look-alikes (no 0, O, 1 or I), shown and stored as XXX-XXX. That gives
// 32^6 (about 1.07 billion) codes; guessing is only possible by asking the server, which limits
// attempts from all addresses together (SetupAttempts). A code file from an older server with
// eight-character codes is not valid, so the next start replaces it.
public static class SetupCode
{
    public const string Alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    public const int Length = 6;

    // Returns the code without its hyphen, or null when the file is missing or does not hold a valid code.
    // The file holds the display form (XXX-XXX); a bare code is accepted too.
    public static async Task<string?> Read(string path, CancellationToken ct)
    {
        string text;
        try
        {
            text = (await File.ReadAllTextAsync(path, ct)).Trim();
        }
        catch (FileNotFoundException)
        {
            return null;
        }
        var code = Normalize(text);
        return IsValid(code) ? code : null;
    }

    public static bool IsValid(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return text.Length == Length && text.All(Alphabet.Contains);
    }

    // What a person typed or pasted: any case, with or without the hyphen and spaces. Only ASCII letters are
    // changed to upper case, so no other character can become part of the alphabet.
    public static string Normalize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return string.Concat(text.Where(character => character is not ('-' or ' ' or '\t' or '\n' or '\r'))
            .Select(character => character is >= 'a' and <= 'z' ? (char)(character - 32) : character));
    }

    public static string Display(string code)
    {
        ArgumentNullException.ThrowIfNull(code);
        return code.Length == Length ? code[..3] + "-" + code[3..] : code;
    }

    // Writes a new code in its display form (XXX-XXX and a line break, so it reads well with cat) to a
    // private temporary file, flushes it to storage and renames it over the target, so an interruption leaves the previous file or the complete new one, never a partial one.
    public static void Write(string path)
    {
        var temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
        if (!OperatingSystem.IsWindows())
        {
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        }
        try
        {
            using (var stream = new FileStream(temporary, options))
            {
                var code = RandomNumberGenerator.GetString(Alphabet, Length);
                stream.Write(Encoding.ASCII.GetBytes(Display(code) + "\n"));
                stream.Flush(true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }
}
