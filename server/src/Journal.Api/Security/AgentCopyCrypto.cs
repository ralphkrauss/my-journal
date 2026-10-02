using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Journal.Api.Security;

// The per-grant copy's formats (protocol/agent-access-server.md, The per-grant copy). The server derives these keys
// only while it serves one request, from the copy key unwrapped with the request's access token.
public sealed class AgentCopyKeys : IDisposable
{
    private readonly byte[] encryption;
    private readonly byte[] identity;

    private AgentCopyKeys(byte[] copyKey)
    {
        encryption = HKDF.DeriveKey(HashAlgorithmName.SHA256, copyKey, 32, [], "journal:v1:agent-copy:encryption"u8.ToArray());
        identity = HKDF.DeriveKey(HashAlgorithmName.SHA256, copyKey, 32, [], "journal:v1:agent-copy:item-id"u8.ToArray());
    }

    public static AgentCopyKeys FromCopyKey(byte[] copyKey)
    {
        ArgumentNullException.ThrowIfNull(copyKey);
        return new AgentCopyKeys(copyKey);
    }

    public string ItemId(Guid recordId) =>
        Convert.ToHexStringLower(HMACSHA256.HashData(identity, Encoding.UTF8.GetBytes("journal:v1:agent-item:" + recordId.ToString("D")))[..16]);

    // Decrypts one item; null when it doesn't authenticate at its position or doesn't name the record its ID came from.
    public CopyItem? Open(Guid grantId, string itemId, string payload)
    {
        byte[] combined;
        try
        {
            combined = Convert.FromBase64String(payload);
        }
        catch (FormatException)
        {
            return null;
        }
        if (combined.Length < 12 + 16 + 1)
        {
            return null;
        }
        var plaintext = new byte[combined.Length - 28];
        try
        {
            using var aes = new AesGcm(encryption, 16);
            aes.Decrypt(combined.AsSpan(0, 12), combined.AsSpan(12, plaintext.Length), combined.AsSpan(combined.Length - 16), plaintext,
                Encoding.UTF8.GetBytes("journal:v1:agent-copy:" + grantId.ToString("D") + ":" + itemId));
            var item = JsonSerializer.Deserialize<CopyItem>(plaintext, CopyItem.Json);
            return item is not null && item.IsWellFormed && ItemId(item.Id) == itemId ? item : null;
        }
        catch (Exception error) when (error is AuthenticationTagMismatchException or JsonException)
        {
            return null;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public void Dispose()
    {
        CryptographicOperations.ZeroMemory(encryption);
        CryptographicOperations.ZeroMemory(identity);
    }
}

// A decrypted item: a shared journal's name, or an entry's readable text.
public sealed record CopyItem(string Kind, Guid Id, string? Name, Guid? JournalId, string? Title, DateTimeOffset? Date, DateTimeOffset? ArchivedAt, string? Text)
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public bool IsWellFormed => Kind switch
    {
        "journal" => Name is not null,
        "entry" => JournalId is not null && Title is not null && Date is not null && Text is not null,
        _ => false,
    };
}
