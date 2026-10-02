namespace Journal.Api.Hosting;

// Where the server reads appsettings.json from: its own folder, whatever directory it was started from, since the
// packaged launcher and the Mac app's embedded server set none. In the Mac app's bundle the executable is in
// Contents/MacOS and its settings in Contents/Resources.
public static class ContentRoot
{
    public static string For(string executableDirectory)
    {
        var resources = Path.GetFullPath(Path.Combine(executableDirectory, "..", "Resources"));
        return !File.Exists(Path.Combine(executableDirectory, "appsettings.json")) && File.Exists(Path.Combine(resources, "appsettings.json"))
            ? resources
            : executableDirectory;
    }
}
