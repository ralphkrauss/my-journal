using System.Text;
using System.Text.Json;

namespace Journal.Api.Tests;

// An independent reader of the record contract (protocol/records.md: Record fields, Documents, Reading rules;
// permanent-deletion.md: Marker; entry-archiving.md), checked against protocol/conformance/records.
public sealed class RecordConformanceTests
{
    private enum Reading
    {
        Editable,
        ReadOnly,
        Unreadable,
    }

    private sealed record ReadRecord(
        Reading Reading,
        string Original,
        string? Id = null,
        string? Kind = null,
        string? Title = null,
        long? Date = null,
        long? ModifiedAt = null,
        string? JournalId = null,
        long? DeletedAt = null,
        long? ArchivedAt = null,
        string? DefaultTemplateId = null,
        bool? DeletedWithJournal = null,
        long? PermanentlyDeletedAt = null,
        string? PermanentDeletionId = null,
        string? RestoredFromDeletionId = null,
        int? DocumentVersion = null,
        string? Markdown = null,
        string[]? LegacyBlockTexts = null);

    private static readonly string[] RecordMembers =
    [
        "id", "kind", "title", "document", "date", "modifiedAt", "deletedWithJournal", "journalID", "deletedAt",
        "defaultTemplateID", "archivedAt", "permanentlyDeletedAt", "permanentDeletionID", "restoredFromDeletionID",
    ];
    private static readonly string[] KnownKinds = ["journal", "entry", "template"];
    private static readonly string[] MetadataMembers = ["blockIDs", "segmentLengths", "imageTypes"];
    private static readonly string[] BlockMembers = ["id", "kind", "runs", "attachmentID", "imageDescription", "mediaType"];
    private static readonly string[] BlockKinds = ["paragraph", "heading", "subheading", "bullet", "numbered", "image"];
    private static readonly string[] RunFlags = ["bold", "italic", "underline"];
    private static readonly string[] RunMembers = ["text", "bold", "italic", "underline", "link"];

    // The record's stored id and kind are those of its sync path. Whatever the outcome, the original text is kept.
    private static ReadRecord Read(string storedId, string storedKind, string text)
    {
        JsonDocument parsed;
        try
        {
            parsed = JsonDocument.Parse(text);
        }
        catch (JsonException)
        {
            return new ReadRecord(Reading.Unreadable, text);
        }
        using (parsed)
        {
            var root = parsed.RootElement;
            return root.ValueKind == JsonValueKind.Object ? ReadObject(storedId, storedKind, text, root) : new ReadRecord(Reading.Unreadable, text);
        }
    }

    private static ReadRecord ReadObject(string storedId, string storedKind, string text, JsonElement root)
    {
        var unreadable = new ReadRecord(Reading.Unreadable, text);
        if (!Present(root, "id", JsonValueKind.String, out var id) || !ConformanceFormats.IsUuid(id.GetString()) ||
            !Present(root, "kind", JsonValueKind.String, out var kind) ||
            !Present(root, "title", JsonValueKind.String, out var title) ||
            !Present(root, "date", JsonValueKind.String, out var date) || !ConformanceFormats.TryParseTimestamp(date.GetString(), out var dateInstant) ||
            !Present(root, "modifiedAt", JsonValueKind.String, out var modified) || !ConformanceFormats.TryParseTimestamp(modified.GetString(), out var modifiedInstant) ||
            !Present(root, "deletedWithJournal", null, out var deletedWithJournal) || deletedWithJournal.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
            !Present(root, "document", JsonValueKind.Object, out var document))
        {
            return unreadable;
        }
        if (!string.Equals(id.GetString(), storedId, StringComparison.OrdinalIgnoreCase) || kind.GetString() != storedKind)
        {
            return unreadable;
        }
        var optionalUuids = new[] { "journalID", "defaultTemplateID", "permanentDeletionID", "restoredFromDeletionID" };
        var optionalTimestamps = new[] { "deletedAt", "archivedAt", "permanentlyDeletedAt" };
        if (optionalUuids.Any(name => !OptionalUuid(root, name)) || optionalTimestamps.Any(name => !OptionalTimestamp(root, name, out _)))
        {
            return unreadable;
        }
        var kindName = kind.GetString()!;
        var isKnownKind = KnownKinds.Contains(kindName);
        var isMarker = Present(root, "permanentlyDeletedAt", JsonValueKind.String, out _);
        var entryNeedsJournal = kindName == "entry" && !isMarker && !Present(root, "journalID", JsonValueKind.String, out _);
        var archivedOnWrongKind = kindName != "entry" && Present(root, "archivedAt", JsonValueKind.String, out _);
        var restoredOnUnknownKind = !isKnownKind && Present(root, "restoredFromDeletionID", JsonValueKind.String, out _);
        if (entryNeedsJournal || archivedOnWrongKind || restoredOnUnknownKind || !HasCanonicalMarkerFields(root, kindName, title.GetString()!, document, dateInstant, modifiedInstant))
        {
            return unreadable;
        }

        var reading = !isKnownKind || root.EnumerateObject().Any(member => !RecordMembers.Contains(member.Name)) ? Reading.ReadOnly : Reading.Editable;
        var content = ReadDocument(document);
        if (content.Reading == Reading.ReadOnly)
        {
            reading = Reading.ReadOnly;
        }
        else if (content.Reading == Reading.Unreadable)
        {
            return unreadable;
        }
        OptionalTimestamp(root, "deletedAt", out var deletedAt);
        OptionalTimestamp(root, "archivedAt", out var archivedAt);
        OptionalTimestamp(root, "permanentlyDeletedAt", out var permanentlyDeletedAt);
        var details = reading == Reading.Editable;
        return new ReadRecord(reading, text, storedId.ToLowerInvariant(), storedKind, title.GetString(), Seconds(dateInstant), Seconds(modifiedInstant),
            Lower(root, "journalID"), Seconds(deletedAt), Seconds(archivedAt), Lower(root, "defaultTemplateID"), deletedWithJournal.GetBoolean(),
            Seconds(permanentlyDeletedAt), Lower(root, "permanentDeletionID"), Lower(root, "restoredFromDeletionID"),
            details ? content.Version : null, details ? content.Markdown : null, details ? content.LegacyBlockTexts : null);
    }

    private sealed record DocumentContent(Reading Reading, int? Version = null, string? Markdown = null, string[]? LegacyBlockTexts = null);

    private static DocumentContent ReadDocument(JsonElement document)
    {
        if (!Present(document, "version", JsonValueKind.Number, out var versionValue) || !versionValue.TryGetInt32(out var version))
        {
            return new DocumentContent(Reading.Unreadable);
        }
        return version switch
        {
            2 => ReadMarkdownDocument(document),
            1 => ReadLegacyDocument(document),
            _ => new DocumentContent(Reading.ReadOnly),
        };
    }

    private static DocumentContent ReadMarkdownDocument(JsonElement document)
    {
        var known = document.EnumerateObject().All(member => member.Name is "version" or "markdown" or "metadata");
        if (!Present(document, "markdown", JsonValueKind.String, out var markdown) || !MetadataIsWellFormed(document) || !known)
        {
            return new DocumentContent(Reading.ReadOnly);
        }
        return new DocumentContent(Reading.Editable, 2, markdown.GetString());
    }

    private static bool MetadataIsWellFormed(JsonElement document)
    {
        if (!document.TryGetProperty("metadata", out var metadata) || metadata.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (metadata.ValueKind != JsonValueKind.Object || metadata.EnumerateObject().Any(member => !MetadataMembers.Contains(member.Name)))
        {
            return false;
        }
        return MemberIsNullOr(metadata, "blockIDs", value => value.ValueKind == JsonValueKind.Array && value.EnumerateArray().All(item => item.ValueKind == JsonValueKind.String && ConformanceFormats.IsUuid(item.GetString())))
            && MemberIsNullOr(metadata, "segmentLengths", value => value.ValueKind == JsonValueKind.Array && value.EnumerateArray().All(item => item.ValueKind == JsonValueKind.Number && item.TryGetInt64(out _)))
            && MemberIsNullOr(metadata, "imageTypes", value => value.ValueKind == JsonValueKind.Object && value.EnumerateObject().All(item => ConformanceFormats.IsUuid(item.Name) && item.Value.ValueKind == JsonValueKind.String));
    }

    private static bool MemberIsNullOr(JsonElement owner, string name, Func<JsonElement, bool> isWellFormed) =>
        !owner.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null || isWellFormed(value);

    private static DocumentContent ReadLegacyDocument(JsonElement document)
    {
        if (!Present(document, "blocks", JsonValueKind.Array, out var blocks) || document.EnumerateObject().Any(member => member.Name is not ("version" or "blocks")))
        {
            return new DocumentContent(Reading.ReadOnly);
        }
        var texts = new List<string>();
        foreach (var block in blocks.EnumerateArray())
        {
            if (block.ValueKind != JsonValueKind.Object || block.EnumerateObject().Any(member => !BlockMembers.Contains(member.Name)) ||
                !Present(block, "id", JsonValueKind.String, out var blockId) || !ConformanceFormats.IsUuid(blockId.GetString()) ||
                !Present(block, "kind", JsonValueKind.String, out var blockKind) || !BlockKinds.Contains(blockKind.GetString()) ||
                !Present(block, "runs", JsonValueKind.Array, out var runs) || !runs.EnumerateArray().All(RunIsWellFormed))
            {
                return new DocumentContent(Reading.ReadOnly);
            }
            texts.Add(string.Concat(runs.EnumerateArray().Select(run => run.GetProperty("text").GetString())));
        }
        return new DocumentContent(Reading.Editable, 1, null, [.. texts]);
    }

    private static bool RunIsWellFormed(JsonElement run) => run.ValueKind == JsonValueKind.Object
        && run.EnumerateObject().All(member => RunMembers.Contains(member.Name))
        && Present(run, "text", JsonValueKind.String, out _)
        && RunFlags.All(name => MemberIsNullOr(run, name, value => value.ValueKind is JsonValueKind.True or JsonValueKind.False))
        && MemberIsNullOr(run, "link", value => value.ValueKind == JsonValueKind.String);

    // A record with permanent-deletion fields is either a canonical marker or unreadable (permanent-deletion.md).
    private static bool HasCanonicalMarkerFields(JsonElement root, string kind, string title, JsonElement document, DateTimeOffset date, DateTimeOffset modifiedAt)
    {
        var deletedAtPresent = OptionalTimestamp(root, "permanentlyDeletedAt", out var permanentlyDeletedAt) && permanentlyDeletedAt is not null;
        var deletionId = Present(root, "permanentDeletionID", JsonValueKind.String, out _);
        if (!deletedAtPresent)
        {
            return !deletionId;
        }
        OptionalTimestamp(root, "deletedAt", out var deletedAt);
        var emptyDocument = document.TryGetProperty("markdown", out var markdown)
            ? markdown.ValueKind == JsonValueKind.String && markdown.GetString()!.Length == 0
            : document.TryGetProperty("blocks", out var blocks) && blocks.ValueKind == JsonValueKind.Array && blocks.GetArrayLength() == 0;
        return KnownKinds.Contains(kind) && deletionId && !Present(root, "restoredFromDeletionID", JsonValueKind.String, out _)
            && title.Length == 0 && emptyDocument
            && !Present(root, "journalID", JsonValueKind.String, out _) && !Present(root, "defaultTemplateID", JsonValueKind.String, out _) && !Present(root, "archivedAt", JsonValueKind.String, out _)
            && root.GetProperty("deletedWithJournal").ValueKind == JsonValueKind.False
            && date == permanentlyDeletedAt && modifiedAt == permanentlyDeletedAt && deletedAt == permanentlyDeletedAt;
    }

    private static bool Present(JsonElement owner, string name, JsonValueKind? kind, out JsonElement value) =>
        owner.TryGetProperty(name, out value) && value.ValueKind != JsonValueKind.Null && (kind is null || value.ValueKind == kind);

    private static bool OptionalUuid(JsonElement owner, string name) =>
        !Present(owner, name, null, out var value) || (value.ValueKind == JsonValueKind.String && ConformanceFormats.IsUuid(value.GetString()));

    private static bool OptionalTimestamp(JsonElement owner, string name, out DateTimeOffset? instant)
    {
        instant = null;
        if (!Present(owner, name, null, out var value))
        {
            return true;
        }
        if (value.ValueKind != JsonValueKind.String || !ConformanceFormats.TryParseTimestamp(value.GetString(), out var parsed))
        {
            return false;
        }
        instant = parsed;
        return true;
    }

    private static string? Lower(JsonElement owner, string name) => Present(owner, name, JsonValueKind.String, out var value) ? value.GetString()!.ToLowerInvariant() : null;

    private static long? Seconds(DateTimeOffset? instant) => instant is { } value ? ConformanceFormats.EpochSeconds(value) : null;

    private static long Seconds(DateTimeOffset instant) => ConformanceFormats.EpochSeconds(instant);

    private static string? Nullable(JsonElement owner, string name) => owner.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static long? NullableNumber(JsonElement owner, string name) => owner.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt64() : null;

    [Fact]
    public void RecordsAreClassifiedAndReadAsTheCorpusSaysAndUnreadableOnesKeepTheirBytes()
    {
        using var corpus = ConformanceFiles.Json("records/records-v1.json");
        var differences = new List<string>();
        foreach (var record in corpus.RootElement.GetProperty("records").EnumerateArray())
        {
            var name = record.GetProperty("name").GetString()!;
            var expected = record.GetProperty("expected");
            var text = record.GetProperty("plaintext").GetString()!;
            var read = Read(record.GetProperty("id").GetString()!, record.GetProperty("kind").GetString()!, text);
            void Expect(string member, object? wanted, object? actual)
            {
                if (!Equals(wanted, actual))
                {
                    differences.Add($"{name}: {member} is {actual ?? "null"}, expected {wanted ?? "null"}");
                }
            }

            var wantedReading = expected.GetProperty("reading").GetString();
            Expect("reading", wantedReading, read.Reading.ToString().ToLowerInvariant()[..1] + read.Reading.ToString()[1..]);
            // Only editable records are rewritten; the others are written back as they were received.
            Expect("rewrite", wantedReading == "editable" ? "rewritten" : "unchanged", expected.GetProperty("rewrite").GetString());
            Assert.Same(text, read.Original);
            if (read.Reading == Reading.Unreadable)
            {
                continue;
            }
            Expect("id", Nullable(expected, "id"), read.Id);
            Expect("kind", Nullable(expected, "kind"), read.Kind);
            Expect("title", Nullable(expected, "title"), read.Title);
            Expect("date", NullableNumber(expected, "date"), read.Date);
            Expect("modifiedAt", NullableNumber(expected, "modifiedAt"), read.ModifiedAt);
            Expect("journalID", Nullable(expected, "journalID"), read.JournalId);
            Expect("deletedAt", NullableNumber(expected, "deletedAt"), read.DeletedAt);
            Expect("archivedAt", NullableNumber(expected, "archivedAt"), read.ArchivedAt);
            Expect("defaultTemplateID", Nullable(expected, "defaultTemplateID"), read.DefaultTemplateId);
            Expect("deletedWithJournal", expected.GetProperty("deletedWithJournal").GetBoolean(), read.DeletedWithJournal);
            Expect("permanentlyDeletedAt", NullableNumber(expected, "permanentlyDeletedAt"), read.PermanentlyDeletedAt);
            Expect("permanentDeletionID", Nullable(expected, "permanentDeletionID"), read.PermanentDeletionId);
            Expect("restoredFromDeletionID", Nullable(expected, "restoredFromDeletionID"), read.RestoredFromDeletionId);
            Expect("documentVersion", expected.TryGetProperty("documentVersion", out var version) && version.ValueKind == JsonValueKind.Number ? version.GetInt32() : null, read.DocumentVersion);
            Expect("markdown", Nullable(expected, "markdown"), read.Markdown);
            var wantedBlocks = expected.TryGetProperty("legacyBlockTexts", out var blocks) && blocks.ValueKind == JsonValueKind.Array ? string.Join("|", blocks.EnumerateArray().Select(block => block.GetString())) : null;
            Expect("legacyBlockTexts", wantedBlocks, read.LegacyBlockTexts is null ? null : string.Join("|", read.LegacyBlockTexts));
        }
        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }

    [Fact]
    public void TimestampsAreStrictIso8601AndFloorToWholeSeconds()
    {
        using var corpus = ConformanceFiles.Json("records/timestamps-v1.json");
        foreach (var valid in corpus.RootElement.GetProperty("valid").EnumerateArray())
        {
            var text = valid.GetProperty("text").GetString();
            Assert.True(ConformanceFormats.TryParseTimestamp(text, out var instant), $"'{text}' is refused");
            Assert.True(valid.GetProperty("epochSeconds").GetInt64() == Seconds(instant), $"'{text}' is {Seconds(instant)}");
        }
        foreach (var invalid in corpus.RootElement.GetProperty("invalid").EnumerateArray())
        {
            Assert.False(ConformanceFormats.TryParseTimestamp(invalid.GetString(), out _), $"'{invalid.GetString()}' is accepted");
        }
    }

    // 1 to 64 characters from 0-9A-Za-z, not ending in 0.
    private static bool ValidRank(string rank) => rank.Length is >= 1 and <= 64
        && rank.All(char.IsAsciiLetterOrDigit) && !rank.EndsWith('0');

    [Fact]
    public void JournalRanksAreValidAndOrderedByteByByte()
    {
        using var corpus = ConformanceFiles.Json("records/journal-ranks-v1.json");
        var root = corpus.RootElement;
        foreach (var rank in root.GetProperty("valid").EnumerateArray().Select(item => item.GetString()!))
        {
            Assert.True(ValidRank(rank), $"'{rank}' is refused");
        }
        foreach (var rank in root.GetProperty("invalid").EnumerateArray().Select(item => item.GetString()!))
        {
            Assert.False(ValidRank(rank), $"'{rank}' is accepted");
        }
        foreach (var pair in root.GetProperty("ordered").EnumerateArray().Select(item => item.EnumerateArray().Select(rank => rank.GetString()!).ToArray()))
        {
            Assert.True(string.CompareOrdinal(pair[0], pair[1]) < 0, $"'{pair[0]}' is not before '{pair[1]}'");
        }
        foreach (var between in root.GetProperty("between").EnumerateArray().Where(item => item.GetProperty("rank").ValueKind == JsonValueKind.String))
        {
            var rank = between.GetProperty("rank").GetString()!;
            Assert.True(ValidRank(rank), $"'{rank}' is refused");
            Assert.True(Nullable(between, "lower") is not { } lower || string.CompareOrdinal(lower, rank) < 0, $"'{rank}' is not after its lower bound");
            Assert.True(Nullable(between, "upper") is not { } upper || string.CompareOrdinal(rank, upper) < 0, $"'{rank}' is not before its upper bound");
        }
        foreach (var spaced in root.GetProperty("spaced").EnumerateArray())
        {
            var ranks = spaced.GetProperty("ranks").EnumerateArray().Select(item => item.GetString()!).ToArray();
            Assert.Equal(spaced.GetProperty("count").GetInt32(), ranks.Length);
            Assert.All(ranks, rank => Assert.True(ValidRank(rank), $"'{rank}' is refused"));
            Assert.True(ranks.Zip(ranks.Skip(1)).All(pair => string.CompareOrdinal(pair.First, pair.Second) < 0), "spaced ranks ascend");
        }
    }
}
