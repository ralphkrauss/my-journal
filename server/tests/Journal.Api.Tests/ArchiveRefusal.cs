namespace Journal.Api.Tests;

// The message classes of protocol/archive.md (Failures) that conformance fixtures compare. "Couldn't open" is not a
// property of an archive's bytes, so a reader that only looks at bytes never produces it.
internal enum ArchiveOutcome
{
    Accept,
    Damaged,
    Newer,
    WrongPassword,
}

// A reader stops with this when the archive must be refused. The reason is for a person debugging a failing case; the
// class is what fixtures compare.
internal sealed class ArchiveRefusal : Exception
{
    private ArchiveRefusal(ArchiveOutcome outcome, string reason)
        : base(reason)
    {
        Outcome = outcome;
    }

    public ArchiveOutcome Outcome
    {
        get;
    }

    public static ArchiveRefusal Damaged(string reason) => new(ArchiveOutcome.Damaged, reason);

    public static ArchiveRefusal Newer(string reason) => new(ArchiveOutcome.Newer, reason);

    public static ArchiveRefusal WrongPassword(string reason) => new(ArchiveOutcome.WrongPassword, reason);

    // Runs a reader and gives the class it ends in with the reason, never letting a bug of the reader pass as a class.
    public static (ArchiveOutcome Outcome, string Reason) Classify(Action read)
    {
        try
        {
            read();
            return (ArchiveOutcome.Accept, "");
        }
        catch (ArchiveRefusal refusal)
        {
            return (refusal.Outcome, refusal.Message);
        }
    }
}

internal static class ArchiveOutcomes
{
    // The words fixtures use for the classes.
    public static ArchiveOutcome Parse(string name) => name switch
    {
        "accept" => ArchiveOutcome.Accept,
        "damaged" => ArchiveOutcome.Damaged,
        "newer" => ArchiveOutcome.Newer,
        "wrongPassword" => ArchiveOutcome.WrongPassword,
        _ => throw new InvalidDataException($"Unknown outcome {name}."),
    };
}
