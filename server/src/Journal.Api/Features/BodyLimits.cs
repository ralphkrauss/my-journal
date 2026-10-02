using Microsoft.AspNetCore.Http.Metadata;

namespace Journal.Api.Features;

// Request body limits. Kestrel applies Default to every request; routes that need more raise it with
// endpoint metadata, which routing applies before any body is read (protocol/README.md, Limits).
public static class BodyLimits
{
    // Account, pairing and other JSON requests are a few kilobytes at most.
    public const long Default = 64 * 1024;
    // A record payload of 4 MiB is about 5.6 MB of base64; JSON escaping of '/' can add a little more.
    public const long SyncRecord = 8 * 1024 * 1024;

    public static TBuilder WithBodyLimit<TBuilder>(this TBuilder builder, long bytes) where TBuilder : IEndpointConventionBuilder =>
        builder.WithMetadata(new BodyLimit(bytes));

    private sealed record BodyLimit(long? MaxRequestBodySize) : IRequestSizeLimitMetadata;
}
