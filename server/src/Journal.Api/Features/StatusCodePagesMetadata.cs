using Microsoft.AspNetCore.Diagnostics;

namespace Journal.Api.Features;

public static class StatusCodePagesMetadata
{
    // MCP and OAuth responses are exactly what their specifications define; the problem-details pages the rest of the
    // API adds to empty error responses would change them.
    public static TBuilder DisableStatusCodePages<TBuilder>(this TBuilder builder) where TBuilder : IEndpointConventionBuilder =>
        builder.AddEndpointFilter(async (context, next) =>
        {
            if (context.HttpContext.Features.Get<IStatusCodePagesFeature>() is { } pages)
            {
                pages.Enabled = false;
            }
            return await next(context);
        });
}
