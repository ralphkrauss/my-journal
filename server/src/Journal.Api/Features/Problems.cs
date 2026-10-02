namespace Journal.Api.Features;

// Every error response is an RFC 9457 problem details body with a stable machine-readable `code`
// (listed in protocol/README.md). `error` repeats the code for clients written before problem details.
public static class Problems
{
    public static IResult Of(int status, string code) =>
        TypedResults.Problem(statusCode: status, extensions: Extensions(code));

    // Revision errors also carry the server's current record (null when it has none).
    public static IResult RevisionConflict(string code, object? current)
    {
        var extensions = Extensions(code);
        extensions["current"] = current;
        return TypedResults.Problem(statusCode: StatusCodes.Status409Conflict, extensions: extensions);
    }

    // Applied to every problem the framework writes: exceptions, status code pages and rate limiting.
    public static void Customize(ProblemDetailsContext context)
    {
        ArgumentNullException.ThrowIfNull(context);
        var extensions = context.ProblemDetails.Extensions;
        if (!extensions.TryGetValue("code", out var code) || code is null)
        {
            code = DefaultCode(context.ProblemDetails.Status ?? context.HttpContext.Response.StatusCode);
            extensions["code"] = code;
        }
        extensions.TryAdd("error", code);
    }

    private static Dictionary<string, object?> Extensions(string code) => new()
    {
        ["code"] = code,
        ["error"] = code,
    };

    private static string DefaultCode(int status) => status switch
    {
        StatusCodes.Status400BadRequest => "bad_request",
        StatusCodes.Status401Unauthorized => "unauthorized",
        StatusCodes.Status403Forbidden => "forbidden",
        StatusCodes.Status404NotFound => "not_found",
        StatusCodes.Status405MethodNotAllowed => "method_not_allowed",
        StatusCodes.Status409Conflict => "conflict",
        StatusCodes.Status413PayloadTooLarge => "request_too_large",
        StatusCodes.Status415UnsupportedMediaType => "unsupported_media_type",
        StatusCodes.Status429TooManyRequests => "rate_limited",
        StatusCodes.Status503ServiceUnavailable => "unavailable",
        >= 500 => "internal_error",
        _ => "http_" + status.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };
}
