using System.Text.Json;

namespace Journal.Api.Tests;

// The cross-client conformance fixtures (protocol/conformance) are copied to the test output with their folder
// layout, so every test reads the same files other clients are written against.
internal static class ConformanceFiles
{
    public static string Path(string relative) =>
        System.IO.Path.Combine(AppContext.BaseDirectory, "conformance", relative);

    public static byte[] Bytes(string relative) => File.ReadAllBytes(Path(relative));

    public static JsonDocument Json(string relative) => JsonDocument.Parse(File.ReadAllBytes(Path(relative)));
}
