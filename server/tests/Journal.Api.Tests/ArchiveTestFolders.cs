namespace Journal.Api.Tests;

// A folder under the system temporary folder that a test owns and removes, links and sparse files included.
internal sealed class TemporaryFolder : IDisposable
{
    public TemporaryFolder()
    {
        FullName = Path.Combine(Path.GetTempPath(), "archive-conformance-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(FullName);
    }

    public string FullName
    {
        get;
    }

    public string Combine(string name) => Path.Combine(FullName, name);

    public void Dispose() => Directory.Delete(FullName, true);
}
